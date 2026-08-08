-- ============================================================================
-- AURA — FIX: no se veían todos los administradores de un estudio (2026-08-07)
-- ============================================================================
--
-- Síntoma: en el backoffice y en el perfil del estudio faltaban admins. Ej: BB
-- no veía a Luciana (admin_estudio en Colegiales y Urquiza).
--
-- La data SIEMPRE estuvo bien. Era un problema de LECTURA, por dos causas que
-- se sumaban:
--
--   1) La única policy de SELECT sobre estudio_admins era
--      "estudio_admins_select_self" -> using (usuario_id = auth.uid()).
--      O sea: una consulta directa desde la app devuelve SOLO tu propia fila.
--
--   2) El panel del estudio (estudio_admin_service.listEstudioAdmins) llama a
--      `admin_list_studio_accesses` y, si falla, cae a leer estudio_admins
--      directo -> le pega la RLS de arriba -> ve un solo registro.
--      El backoffice cae a la MISMA función cuando admin_list_studio_members
--      no responde. Las dos pantallas convergen ahí.
--
-- Por qué los permisos igual funcionaban: los chequeos reales
-- (caller_puede_gestionar_accesos, rol_en_estudio) son SECURITY DEFINER, y las
-- policies de `clases` preguntan siempre por la fila PROPIA
-- (usuario_id = auth.uid()), que es justo lo que la policy self permite. Por eso
-- Luciana podía entrar y editar clases: lo único roto era verla en una lista.
--
-- La migración 20260724120000 arregló los caminos de ESCRITURA de accesos y
-- nunca tocó los de lectura. Esto cierra esa mitad.
-- ============================================================================


-- ── 1. Helper: ¿el caller es miembro de este estudio? ───────────────────────
--
-- SECURITY DEFINER por dos motivos:
--   a) para leer admin_users / estudio_admins salteando RLS;
--   b) porque lo usa una policy SOBRE estudio_admins, y si la policy
--      consultara estudio_admins directamente Postgres tira
--      "infinite recursion detected in policy for relation estudio_admins".
--      El definer corta la recursión.
--
-- auth.uid() dentro de un definer sigue devolviendo al caller real (sale del
-- JWT), así que la autorización es correcta.
--
-- p_estudio_id es BIGINT: los id son bigint y bigint->int no castea solo.
create or replace function public.es_miembro_de_estudio(p_estudio_id bigint)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
           select 1 from public.admin_users where user_id = auth.uid()
         )
      or exists (
           select 1 from public.estudio_admins
            where estudio_id = p_estudio_id
              and usuario_id = auth.uid()
         );
$$;

revoke execute on function public.es_miembro_de_estudio(bigint) from public, anon;
grant execute on function public.es_miembro_de_estudio(bigint) to authenticated;


-- ── 2. Policy: un miembro ve a los demás miembros de SUS estudios ───────────
--
-- Se SUMA a la policy self existente (las policies de SELECT se combinan con
-- OR), no la reemplaza: si algo fallara en el helper, seguís viendo tu fila.
drop policy if exists "estudio_admins_select_miembros" on public.estudio_admins;
create policy "estudio_admins_select_miembros"
  on public.estudio_admins
  for select
  to authenticated
  using (public.es_miembro_de_estudio(estudio_id));


-- ── 3. admin_list_studio_accesses: la función a la que caen las 2 pantallas ─
--
-- No estaba versionada en el repo (se creó desde el dashboard), así que no
-- sabemos con qué firma quedó. Borramos todas las variantes por nombre y la
-- recreamos con la misma lógica que admin_list_studio_members.
--
-- Devuelve (id, nombre, email, rol), que es exactamente lo que consumen las dos
-- pantallas (perfil_estudio_screen y admin_estudios_screen).
do $$
declare
  v_fn record;
begin
  for v_fn in
    select p.oid::regprocedure as firma
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('admin_list_studio_accesses', 'admin_list_studio_members')
  loop
    execute format('drop function if exists %s', v_fn.firma);
  end loop;
end $$;


-- Implementación única. Las dos funciones públicas delegan acá para que no
-- vuelvan a divergir.
create function public.admin_list_studio_members(p_estudio_id bigint)
returns table (id uuid, nombre text, email text, rol text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id  uuid := auth.uid();
  v_authorized boolean;
begin
  if v_caller_id is null then
    return;
  end if;

  -- Superadmin de Aura, o admin REAL del estudio. Una profe no gestiona
  -- accesos, pero SÍ puede ver quiénes son (la lista es informativa y ya la
  -- muestra el perfil del estudio).
  select
    exists (select 1 from public.admin_users where user_id = v_caller_id)
    or exists (
      select 1 from public.estudio_admins
       where estudio_id = p_estudio_id
         and usuario_id = v_caller_id
    )
  into v_authorized;

  if not v_authorized then
    return;
  end if;

  -- LEFT JOIN, no INNER: si un vínculo apunta a un usuario que no está en
  -- public.usuarios (ej. alta por OAuth sin backfill), antes la fila
  -- DESAPARECÍA de la lista. Ahora aparece, con el nombre vacío, y se ve que
  -- hay algo para arreglar en vez de que el admin quede invisible.
  return query
    select ea.usuario_id,
           u.nombre,
           u.email,
           ea.rol
      from public.estudio_admins ea
      left join public.usuarios u on u.id = ea.usuario_id
     where ea.estudio_id = p_estudio_id
     order by
       case ea.rol when 'estudio' then 0 when 'admin_estudio' then 1 else 2 end,
       coalesce(u.email, '');
end;
$$;

grant execute on function public.admin_list_studio_members(bigint)
  to authenticated, service_role;


-- Alias legacy: mismo resultado. Lo llama el panel del estudio
-- (estudio_admin_service.listEstudioAdmins) y es el fallback del backoffice.
-- Con esto las dos pantallas quedan arregladas SIN tocar la app.
create function public.admin_list_studio_accesses(p_estudio_id bigint)
returns table (id uuid, nombre text, email text, rol text)
language sql
security definer
set search_path = public
as $$
  select * from public.admin_list_studio_members(p_estudio_id);
$$;

grant execute on function public.admin_list_studio_accesses(bigint)
  to authenticated, service_role;


-- ── 4. VERIFICACIÓN ─────────────────────────────────────────────────────────
-- Lo que sigue solo lee. Ojo: corriendo desde el SQL editor auth.uid() es null,
-- así que las funciones de arriba devuelven vacío (es lo esperado). Para
-- probarlas de verdad hay que entrar con un usuario desde la app.

-- Policies de SELECT que quedaron sobre estudio_admins: tienen que ser dos.
select policyname, cmd, qual as condicion
  from pg_policies
 where schemaname = 'public'
   and tablename = 'estudio_admins'
   and cmd = 'SELECT'
 order by policyname;

-- La lista real contra la que comparar cada pantalla.
select e.nombre as estudio, ea.rol, u.nombre, u.email
  from public.estudio_admins ea
  join public.estudios e on e.id = ea.estudio_id
  left join public.usuarios u on u.id = ea.usuario_id
 order by e.nombre,
          case ea.rol when 'estudio' then 0 when 'admin_estudio' then 1 else 2 end,
          coalesce(u.email, '');
