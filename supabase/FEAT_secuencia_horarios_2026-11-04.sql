-- Secuencia de bienvenida: horarios y encendido (pedido de Sofía, 4/11/2026).
--
--   · Mail 1: al toque (5-15 min después del registro).
--   · Mails 2 y 3: solo a las 10 de la mañana, hora de Argentina. Le toca a la
--     persona si cumplió los 4 (o 30) días a las 10:00 de hoy; si los cumple a
--     las 10:30, espera a las 10 del día siguiente. El cron corre cada 10 min,
--     así que salen entre las 10:00 y las 10:59.
--   · `empieza_at`: antes de ese momento no sale nada de nada. Se prende hoy a
--     la noche con empieza_at = 5/11 a las 10:00: quien se registre esta noche
--     recibe el mail 1 mañana a las 10 (la ventana del mail 1 es de 2 días).
--
-- Apagar: update public.secuencia_config set activa = false, updated_at = now();
-- Volver a la versión sin horarios: FEAT_secuencia_bienvenida_2026-11-04.sql.

begin;

alter table public.secuencia_config add column if not exists empieza_at timestamptz;

create or replace function public.secuencia_a_enviar(p_limite int default 50)
returns table (usuario_id uuid, paso smallint, email text, nombre text)
language sql stable security definer set search_path = public
as $$
  with cfg as (
    select desde,
           -- Las 10:00 de hoy en Argentina.
           ((now() at time zone 'America/Argentina/Buenos_Aires')::date + time '10:00')
             at time zone 'America/Argentina/Buenos_Aires' as slot
      from public.secuencia_config
     where activa and desde is not null
       and (empieza_at is null or now() >= empieza_at)
  ),
  base as (
    select u.id, lower(trim(au.email)) as email, u.nombre, au.created_at, cfg.desde, cfg.slot
      from public.usuarios u
      join auth.users au on au.id = u.id
      cross join cfg
     where au.created_at >= cfg.desde - interval '30 days'
       and coalesce(u.rol, 'usuario') = 'usuario'
       and au.email like '%@%'
       and au.email not like '%@cuenta-eliminada.aura'
       and not public.es_cuenta_interna(au.email)
       and not public._vinculada_a_estudio(u.id)
       and not exists (select 1 from public.mail_bajas b where b.email = lower(trim(au.email)))
       and not exists (select 1 from public.pagos p
                        where p.user_id = u.id and p.status in ('approved', 'cancelled'))
       and not exists (select 1 from public.regalo_campana rc where rc.usuario_id = u.id)
  ),
  cand as (
    select b.*,
      case
        -- 2 y 3: solo en la hora de las 10, y si ya le tocaba a las 10:00.
        when now() >= b.slot and now() < b.slot + interval '1 hour'
         and b.created_at + interval '30 days' <= b.slot
         and b.created_at + interval '33 days' >  b.slot then 3
        when now() >= b.slot and now() < b.slot + interval '1 hour'
         and b.created_at >= b.desde
         and b.created_at + interval '4 days' <= b.slot
         and b.created_at + interval '7 days' >  b.slot then 2
        when b.created_at >= b.desde
         and now() >= b.created_at + interval '5 minutes'
         and now() <  b.created_at + interval '2 days' then 1
      end::smallint as paso
    from base b
  )
  select c.id, c.paso, c.email, c.nombre
    from cand c
   where c.paso is not null
     and not exists (select 1 from public.secuencia_mails m
                      where m.usuario_id = c.id and m.paso = c.paso
                        and (m.estado not like 'error%' or m.intentos >= 3))
   order by c.created_at
   limit p_limite;
$$;

revoke all on function public.secuencia_a_enviar(int) from public, anon, authenticated;
grant execute on function public.secuencia_a_enviar(int) to service_role;

-- Encendido: arranca a contar desde ahora, pero no sale nada antes del 5/11 a las 10.
update public.secuencia_config
   set activa = true,
       desde = now(),
       empieza_at = timestamptz '2026-11-05 10:00:00-03',
       updated_at = now();

commit;
