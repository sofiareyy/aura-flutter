-- AURA — Diagnóstico: reservas huérfanas (sin usuario_id) — 2026-08-07.
-- Solo LEE. No modifica nada.
--
-- El DDL de `reservas` no está versionado en el repo (se creó desde el
-- dashboard), así que estas consultas son la única forma de saber si la columna
-- admite null, qué FK tiene, y de dónde salieron esas filas.


-- 1) ¿Cómo está definida la tabla? Interesa `is_nullable` de usuario_id, y si
--    existe una columna `email` (no aparece en ningún insert del repo).
select column_name,
       data_type,
       is_nullable,
       column_default
  from information_schema.columns
 where table_schema = 'public'
   and table_name = 'reservas'
 order by ordinal_position;


-- 2) Foreign keys de reservas y, sobre todo, su ON DELETE.
--    Si usuario_id tiene ON DELETE SET NULL, borrar un usuario de prueba
--    convierte sus reservas en huérfanas en vez de borrarlas: esa sería la
--    explicación de por qué aparecieron 6 "de golpe en el mismo segundo".
select con.conname                              as constraint_name,
       att.attname                              as columna,
       cl2.relname                              as tabla_referenciada,
       case con.confdeltype
         when 'a' then 'NO ACTION'
         when 'r' then 'RESTRICT'
         when 'c' then 'CASCADE'
         when 'n' then 'SET NULL'
         when 'd' then 'SET DEFAULT'
       end                                      as on_delete
  from pg_constraint con
  join pg_class cl on cl.oid = con.conrelid
  join pg_namespace n on n.oid = cl.relnamespace
  join unnest(con.conkey) with ordinality as k(attnum, ord) on true
  join pg_attribute att on att.attrelid = cl.oid and att.attnum = k.attnum
  left join pg_class cl2 on cl2.oid = con.confrelid
 where n.nspname = 'public'
   and cl.relname = 'reservas'
   and con.contype = 'f'
 order by con.conname, k.ord;


-- 3) Las filas huérfanas, completas. Mirá `created_at`, `estado` y
--    `creditos_usados`: son los que definen si además de limpiar hay que
--    corregir algo.
select r.*,
       c.nombre  as clase,
       c.fecha   as clase_fecha,
       e.nombre  as estudio
  from public.reservas r
  left join public.clases c   on c.id = r.clase_id
  left join public.estudios e on e.id = c.estudio_id
 where r.usuario_id is null
 order by r.created_at, r.id;


-- 4) ¿Alguna otra reserva apunta a un usuario que ya no existe?
--    (usuario_id no nulo pero sin fila en usuarios). Es la otra forma de
--    quedar huérfana.
select r.id, r.usuario_id, r.estado, r.creditos_usados, r.created_at
  from public.reservas r
  left join public.usuarios u on u.id = r.usuario_id
 where r.usuario_id is not null
   and u.id is null
 order by r.created_at;


-- 5) ¿Hay algún trigger sobre clases o reservas que no esté en el repo?
--    Buscamos algo que, al generar clases, inserte reservas automáticamente.
select c.relname   as tabla,
       t.tgname    as trigger,
       p.proname   as funcion,
       pg_get_triggerdef(t.oid) as definicion
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  join pg_proc p on p.oid = t.tgfoid
 where n.nspname = 'public'
   and c.relname in ('clases', 'reservas', 'horarios_fijos')
   and not t.tgisinternal
 order by c.relname, t.tgname;


-- 6) ¿Qué funciones INSERTAN en reservas? Incluye las creadas desde el
--    dashboard que no están en el repo. En el repo solo hay 3 caminos
--    (apply_reservation, apply_reservation v2 y la promoción de lista_espera)
--    y los tres cortan si el usuario es null, así que si hay una cuarta, es
--    la sospechosa.
select p.proname                as funcion,
       pg_get_function_identity_arguments(p.oid) as argumentos,
       p.prosecdef              as es_security_definer
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.prosrc ~* 'insert\s+into\s+(public\.)?reservas'
 order by p.proname;


-- 7) IMPACTO EN CUPO: ¿esas reservas están ocupando lugares?
--    Compara los lugares que dice la clase contra las reservas activas reales.
--    `desfasaje` distinto de 0 = el cupo quedó mal contado.
select c.id,
       e.nombre as estudio,
       c.nombre as clase,
       c.fecha,
       c.lugares_total,
       c.lugares_disponibles,
       count(*) filter (
         where r.estado not in ('cancelada', 'cancelada_por_estudio')
       ) as reservas_activas,
       count(*) filter (
         where r.usuario_id is null
           and r.estado not in ('cancelada', 'cancelada_por_estudio')
       ) as huerfanas_activas,
       c.lugares_total
         - count(*) filter (
             where r.estado not in ('cancelada', 'cancelada_por_estudio')
           )
         - coalesce(c.lugares_disponibles, 0) as desfasaje
  from public.clases c
  join public.reservas r on r.clase_id = c.id
  left join public.estudios e on e.id = c.estudio_id
 where c.id in (select clase_id from public.reservas where usuario_id is null)
 group by c.id, e.nombre, c.nombre, c.fecha, c.lugares_total, c.lugares_disponibles
 order by c.fecha;


-- 8) IMPACTO EN PLATA: ¿alguna huérfana entra en una liquidación?
--    Cuenta solo si el estado es liquidable Y creditos_usados > 0.
--    Si devuelve 0 filas, no se cobró nada de más y solo hay que limpiar.
select r.id,
       r.estado,
       r.creditos_usados,
       r.created_at,
       e.nombre as estudio
  from public.reservas r
  left join public.clases c   on c.id = r.clase_id
  left join public.estudios e on e.id = c.estudio_id
 where r.usuario_id is null
   and r.estado in ('confirmada', 'presente', 'ausente', 'completada')
   and coalesce(r.creditos_usados, 0) > 0
 order by r.created_at;
