-- ============================================================================
-- El nombre de las cuentas de Google y Apple es el real (3/11/2026)
--
-- El problema: el trigger `handle_new_user` creaba la fila de `usuarios` con
-- `meta.nombre` (lo escribe el formulario de mail y contraseña) o, si no
-- había, con el comienzo del mail. Google y Apple mandan el nombre en
-- `full_name` / `name`, que el trigger ignoraba. La app sí lo prefería, pero
-- la fila ya existía y no la pisaba. Resultado: 75 de 81 cuentas de Google y
-- 41 de 44 de Apple se llamaban "malekuipers" en vez de "Malena Kuipers", y el
-- estudio no sabía a quién recibía.
--
-- Qué hace:
-- 1. `_nombre_prolijo`: si el nombre viene TODO en mayúsculas o TODO en
--    minúsculas, lo pasa a "Nombre Apellido". Si viene mezclado, lo respeta.
-- 2. `handle_new_user` usa full_name / name antes que el comienzo del mail.
-- 3. Las alumnas que ya existen: si su nombre sigue siendo el comienzo del
--    mail (o sea, nunca lo cambiaron) y Google/Apple mandó uno real, se
--    reemplaza. Lo anterior queda guardado en `_backup_nombres_2026_11_03`.
--    Solo rol 'usuario': estudios y profes no se tocan.
--
-- Las reseñas públicas siguen mostrando solo nombre e inicial ("Malena K.").
-- Volver atrás: ROLLBACK_nombre_real_google_apple_2026-11-03.sql
-- ============================================================================

create or replace function public._nombre_prolijo(p text)
returns text
language sql immutable
as $$
  select case
           when t is null then null
           when t = upper(t) and t <> lower(t) then initcap(lower(t))  -- TODO MAYÚSCULAS
           when t = lower(t) and t <> upper(t) then initcap(t)         -- todo minúsculas
           else t
         end
    from (select nullif(regexp_replace(trim(coalesce(p, '')), '\s+', ' ', 'g'), '') as t) x;
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  BEGIN
    INSERT INTO public.usuarios (
      id,
      nombre,
      email,
      plan,
      creditos,
      rol
    )
    VALUES (
      NEW.id,
      COALESCE(
        -- El que escribió en el formulario de registro con mail.
        NULLIF(TRIM(NEW.raw_user_meta_data->>'nombre'), ''),
        -- El que manda Google o Apple (3/11/2026).
        public._nombre_prolijo(NEW.raw_user_meta_data->>'full_name'),
        public._nombre_prolijo(NEW.raw_user_meta_data->>'name'),
        split_part(NEW.email, '@', 1),
        'Usuario'
      ),
      COALESCE(NEW.email, ''),
      NULL,
      0,
      'usuario'
    )
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'handle_new_user falló para %: %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$function$;

-- Copia de lo que se va a cambiar, para poder volver atrás.
create table if not exists public._backup_nombres_2026_11_03 (
  usuario_id      uuid primary key,
  nombre_anterior text,
  nombre_nuevo    text,
  cambiado_at     timestamptz not null default now()
);
alter table public._backup_nombres_2026_11_03 enable row level security;
revoke all on public._backup_nombres_2026_11_03 from anon, authenticated;

with candidatas as (
  select u.id, u.nombre as anterior,
         coalesce(public._nombre_prolijo(au.raw_user_meta_data->>'full_name'),
                  public._nombre_prolijo(au.raw_user_meta_data->>'name')) as nuevo
    from public.usuarios u
    join auth.users au on au.id = u.id
   where coalesce(u.rol, 'usuario') = 'usuario'
     and lower(trim(u.nombre)) = lower(split_part(u.email, '@', 1))
), guardadas as (
  insert into public._backup_nombres_2026_11_03 (usuario_id, nombre_anterior, nombre_nuevo)
  select id, anterior, nuevo from candidatas
   where nuevo is not null and nuevo <> anterior
  on conflict (usuario_id) do nothing
  returning usuario_id, nombre_nuevo
)
update public.usuarios u
   set nombre = g.nombre_nuevo
  from guardadas g
 where u.id = g.usuario_id;

-- ── Aplicado después, con OK de Sofía (3/11/2026): estudios y profes ──────────
-- 11 de 12 corregidas (reysofia19@ no tiene nombre de Google/Apple).
with candidatas as (
  select u.id, u.nombre as anterior,
         coalesce(public._nombre_prolijo(au.raw_user_meta_data->>'full_name'),
                  public._nombre_prolijo(au.raw_user_meta_data->>'name')) as nuevo
    from public.usuarios u join auth.users au on au.id = u.id
   where coalesce(u.rol, 'usuario') <> 'usuario'
     and lower(trim(u.nombre)) = lower(split_part(u.email, '@', 1))
), guardadas as (
  insert into public._backup_nombres_2026_11_03 (usuario_id, nombre_anterior, nombre_nuevo)
  select id, anterior, nuevo from candidatas where nuevo is not null and nuevo <> anterior
  on conflict (usuario_id) do nothing
  returning usuario_id, nombre_nuevo
)
update public.usuarios u set nombre = g.nombre_nuevo from guardadas g where u.id = g.usuario_id;
