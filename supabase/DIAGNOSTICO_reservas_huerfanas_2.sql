-- AURA — Reservas huérfanas, parte 2 (2026-08-07). Solo LEE.
--
-- Corrige las consultas 7 y 8 del archivo anterior: filtraban por
-- `usuario_id is null` y no hay ninguna fila así. El problema real son 36
-- reservas cuyo usuario_id apunta a un usuario que ya no existe en
-- public.usuarios (no hay FK sobre esa columna que lo impida).


-- A) ANTES DE BORRAR NADA: ¿ese usuario sigue existiendo en auth.users?
--    Si aparece acá, NO es una cuenta borrada: es alguien que existe en auth
--    pero nunca se copió a public.usuarios (ver FIX_BACKFILL_USUARIOS_OAUTH).
--    En ese caso NO hay que borrar las reservas: hay que recrear su fila en
--    usuarios.
select id,
       email,
       created_at,
       deleted_at,
       last_sign_in_at
  from auth.users
 where id = '1bf59530-3f4f-4d3a-b850-db0166aaf985';


-- B) Todos los usuario_id colgados, con su cuenta y cuántas reservas arrastran.
select r.usuario_id,
       (au.id is not null)  as sigue_en_auth_users,
       au.email             as email_en_auth,
       count(*)             as reservas,
       min(r.created_at)    as primera,
       max(r.created_at)    as ultima
  from public.reservas r
  left join public.usuarios u on u.id = r.usuario_id
  left join auth.users au     on au.id = r.usuario_id
 where u.id is null
 group by r.usuario_id, au.id, au.email
 order by count(*) desc;


-- C) IMPACTO EN CUPO (corregida): clases con reservas colgadas.
--    `lugares_a_devolver` es cuántos lugares quedaron ocupados de más.
select c.id            as clase_id,
       e.nombre        as estudio,
       c.nombre        as clase,
       c.fecha,
       c.lugares_total,
       c.lugares_disponibles,
       count(*) filter (
         where u.id is null
           and coalesce(r.estado, '') not in ('cancelada', 'cancelada_por_estudio')
       ) as huerfanas_activas,
       count(*) filter (
         where coalesce(r.estado, '') not in ('cancelada', 'cancelada_por_estudio')
       ) as reservas_activas_totales
  from public.reservas r
  join public.clases c        on c.id = r.clase_id
  left join public.estudios e on e.id = c.estudio_id
  left join public.usuarios u on u.id = r.usuario_id
 where c.id in (
         select r2.clase_id
           from public.reservas r2
           left join public.usuarios u2 on u2.id = r2.usuario_id
          where u2.id is null
       )
 group by c.id, e.nombre, c.nombre, c.fecha, c.lugares_total, c.lugares_disponibles
 having count(*) filter (
          where u.id is null
            and coalesce(r.estado, '') not in ('cancelada', 'cancelada_por_estudio')
        ) > 0
 order by c.fecha;


-- D) IMPACTO EN PLATA (corregida): ¿alguna colgada entra en liquidación?
--    Cuenta solo si el estado es liquidable Y creditos_usados > 0.
--    Por lo que ya vimos todas tienen creditos_usados = 0, así que esto
--    debería dar 0 filas. Es la confirmación formal.
select r.id,
       r.estado,
       r.creditos_usados,
       r.created_at,
       e.nombre as estudio
  from public.reservas r
  left join public.usuarios u on u.id = r.usuario_id
  left join public.clases c   on c.id = r.clase_id
  left join public.estudios e on e.id = c.estudio_id
 where u.id is null
   and r.estado in ('confirmada', 'presente', 'ausente', 'completada')
   and coalesce(r.creditos_usados, 0) > 0
 order by r.created_at;


-- E) ¿Hay otras tablas con el mismo agujero (usuario_id sin FK)?
--    Para saber si esto es un caso puntual o un patrón.
select c.relname as tabla,
       a.attname as columna,
       exists (
         select 1 from pg_constraint fk
          where fk.conrelid = c.oid
            and fk.contype = 'f'
            and a.attnum = any (fk.conkey)
       ) as tiene_fk
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid
 where n.nspname = 'public'
   and c.relkind = 'r'
   and a.attname in ('usuario_id', 'user_id')
   and a.attnum > 0
   and not a.attisdropped
 order by tiene_fk, c.relname;
