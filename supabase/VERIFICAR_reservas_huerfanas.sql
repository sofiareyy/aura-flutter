-- AURA — Verificación post-fix de reservas huérfanas (2026-08-07). Solo LEE.
--
-- Reemplaza la consulta (d) de la migración, que estaba mal: contaba 1 reserva
-- en clases que tienen 0. El left join genera una fila con estado NULL,
-- coalesce lo pasa a '' y '' pasaba el filtro de "no cancelada".
-- Acá el conteo va en un subquery lateral, que devuelve 0 de verdad.


-- 1) ¿Quedó algo colgado? Tiene que dar 0 y 0.
select 'reservas' as tabla, count(*) as colgadas
  from public.reservas r
  left join public.usuarios u on u.id = r.usuario_id
 where u.id is null
union all
select 'lista_espera', count(*)
  from public.lista_espera le
  left join public.usuarios u on u.id::text = le.usuario_id::text
 where u.id is null;


-- 2) La FK nueva. Tiene que aparecer y decir CASCADE.
select con.conname, cl.relname as tabla,
       case con.confdeltype when 'c' then 'CASCADE' else con.confdeltype::text end as on_delete
  from pg_constraint con
  join pg_class cl on cl.oid = con.conrelid
  join pg_namespace n on n.oid = cl.relnamespace
 where n.nspname = 'public'
   and con.contype = 'f'
   and con.conname = 'reservas_usuario_id_fkey';


-- 3) El default de usuario_id tiene que estar en null (sin gen_random_uuid).
select column_name, is_nullable, column_default
  from information_schema.columns
 where table_schema = 'public'
   and table_name = 'reservas'
   and column_name = 'usuario_id';


-- 4) Cupo descuadrado en clases futuras (CORREGIDA).
--    Solo devuelve clases donde lugares_disponibles no coincide con
--    lugares_total menos las reservas activas reales.
select c.id,
       e.nombre  as estudio,
       c.nombre  as clase,
       c.fecha,
       c.lugares_total,
       c.lugares_disponibles,
       coalesce(act.n, 0) as reservas_activas,
       greatest(0, coalesce(c.lugares_total, 0) - coalesce(act.n, 0))
         as disponibles_correcto
  from public.clases c
  left join public.estudios e on e.id = c.estudio_id
  left join lateral (
    select count(*) as n
      from public.reservas r
     where r.clase_id = c.id
       and coalesce(r.estado, '') not in ('cancelada', 'cancelada_por_estudio')
  ) act on true
 where c.fecha >= now()
   and coalesce(c.lugares_disponibles, 0)
       <> greatest(0, coalesce(c.lugares_total, 0) - coalesce(act.n, 0))
 order by c.fecha;


-- 5) Resumen del punto 4: cuántas clases descuadradas hay por estudio.
select e.nombre as estudio, count(*) as clases_descuadradas
  from public.clases c
  left join public.estudios e on e.id = c.estudio_id
  left join lateral (
    select count(*) as n
      from public.reservas r
     where r.clase_id = c.id
       and coalesce(r.estado, '') not in ('cancelada', 'cancelada_por_estudio')
  ) act on true
 where c.fecha >= now()
   and coalesce(c.lugares_disponibles, 0)
       <> greatest(0, coalesce(c.lugares_total, 0) - coalesce(act.n, 0))
 group by e.nombre
 order by count(*) desc;
