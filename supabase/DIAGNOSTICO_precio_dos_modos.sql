-- AURA — Diagnóstico previo al cambio de precio en dos modos (2026-08-07).
-- Solo LEE. No modifica nada. Corrélo ANTES de la migración para ver con qué
-- precio va a quedar cada estudio, y DESPUÉS para verificar que quedó bien.


-- 1) Cómo está configurado cada estudio hoy, y con qué precio quedaría.
--    `precio_que_tomaria` es lo que va a poner el backfill en creditos_min.
with moda_clases as (
  select estudio_id, creditos,
         row_number() over (
           partition by estudio_id
           order by count(*) desc, creditos desc
         ) as rn,
         count(*) as cantidad
    from public.clases
   where coalesce(tipo, 'clase') <> 'workshop'
     and coalesce(creditos, 0) > 0
   group by estudio_id, creditos
)
select e.id,
       e.nombre,
       e.tipo_estudio,
       e.tipo_precio                             as modo_actual,
       e.creditos_min,
       e.creditos_max,
       e.precio_config ->> 'min'                 as pc_min,
       e.precio_config ->> 'max'                 as pc_max,
       m.creditos                                as precio_mas_usado_en_clases,
       m.cantidad                                as clases_con_ese_precio,
       coalesce(
         e.creditos_min,
         (nullif(e.precio_config ->> 'min', '')::numeric)::int,
         m.creditos,
         10
       )                                         as precio_que_tomaria,
       jsonb_array_length(coalesce(e.horarios_config -> 'pico', '[]'::jsonb))  as bloques_pico,
       jsonb_array_length(coalesce(e.horarios_config -> 'valle', '[]'::jsonb)) as bloques_valle
  from public.estudios e
  left join moda_clases m on m.estudio_id = e.id and m.rn = 1
 where e.activo = true
 order by e.nombre;


-- 2) Dispersión de precios por estudio: si un estudio tiene varios precios
--    distintos entre sus clases, acá se ve cuáles y cuántas de cada uno.
--    Sirve para confirmar que el "precio más usado" es el correcto.
select e.nombre,
       c.creditos,
       count(*) as clases
  from public.clases c
  join public.estudios e on e.id = c.estudio_id
 where coalesce(c.tipo, 'clase') <> 'workshop'
   and e.activo = true
 group by e.nombre, c.creditos
 order by e.nombre, clases desc;


-- 3) ¿Ya se corrió el backfill alguna vez?
select clave, valor, updated_at
  from public.configuracion_global
 where clave = 'precio_dos_modos_backfill';


-- 4) SOLO DESPUÉS de la migración: clases cuyo precio guardado no coincide con
--    el que calcula la config del estudio. Tiene que devolver 0 filas.
--
--    Si la corrés ANTES de la migración da:
--      ERROR: function public.calcular_precio_clase(bigint, ...) does not exist
--    Es esperable: la versión que acepta bigint la crea la migración.
select c.id,
       e.nombre   as estudio,
       c.nombre   as clase,
       c.fecha,
       c.creditos as guardado,
       (calc.res ->> 'creditos')::int as calculado,
       calc.res ->> 'tipo'            as tipo_calculado
  from public.clases c
  join public.estudios e on e.id = c.estudio_id
 cross join lateral (
   select public.calcular_precio_clase(
            c.estudio_id, null,
            extract(isodow from c.fecha)::int,
            to_char(c.fecha, 'HH24:MI')
          ) as res
 ) calc
 where coalesce(c.tipo, 'clase') <> 'workshop'
   and coalesce((calc.res ->> 'ok')::boolean, false)
   and c.creditos is distinct from (calc.res ->> 'creditos')::int
 order by e.nombre, c.fecha;
