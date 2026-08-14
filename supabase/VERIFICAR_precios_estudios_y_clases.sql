-- AURA — ¿Quedó algún estudio o clase con precio inválido? (2026-08-13)
-- Solo LEE. No modifica nada.
--
-- Descarta que el recálculo de precios de hoy haya dejado a alguien en un
-- estado raro: modo rango sin valores, o clases en cero/null.

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 1) Los 9 estudios: modo, valores y si la config es usable                │
-- └──────────────────────────────────────────────────────────────────────────┘
select e.nombre,
       e.tipo_precio                                          as modo,
       e.creditos_min,
       e.creditos_max,
       jsonb_array_length(
         coalesce(e.horarios_config -> 'valle', '[]'::jsonb)
       )                                                      as franjas_valle,
       case
         when e.creditos_min is null or e.creditos_min <= 0
           then '🔴 SIN PRECIO — las clases saldrían gratis'
         when e.tipo_precio = 'rango'
          and (e.creditos_max is null or e.creditos_max < e.creditos_min)
           then '🔴 RANGO SIN TECHO VÁLIDO'
         when e.tipo_precio = 'rango'
           then '✅ rango ok (valle=' || e.creditos_min || ', pico=' || e.creditos_max || ')'
         else '✅ fijo en ' || e.creditos_min
       end                                                    as estado
  from public.estudios e
 where e.activo = true
 order by e.nombre;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 2) 🔑 Clases futuras con precio inválido (cero o null)                   │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Si da 0 filas, ninguna clase quedó sin precio y la teoría del "precio en
-- cero" queda descartada con datos.
-- (Los workshops quedan afuera: su precio se carga en pesos, aparte.)
select e.nombre  as estudio,
       c.id,
       c.nombre  as clase,
       c.fecha,
       c.creditos,
       c.tipo_precio
  from public.clases c
  join public.estudios e on e.id = c.estudio_id
 where c.fecha >= now()
   and coalesce(c.tipo, 'clase') <> 'workshop'
   and coalesce(c.creditos, 0) <= 0
 order by e.nombre, c.fecha;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 3) Sculpt en detalle: sus clases futuras y a cuánto quedaron             │
-- └──────────────────────────────────────────────────────────────────────────┘
select c.fecha,
       c.nombre,
       c.creditos,
       c.tipo_precio,
       c.lugares_total,
       c.lugares_disponibles
  from public.clases c
  join public.estudios e on e.id = c.estudio_id
 where e.nombre = 'Sculpt Club'
   and c.fecha >= now()
 order by c.fecha
 limit 15;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 4) Resumen de precios por estudio, para ver de un vistazo                │
-- └──────────────────────────────────────────────────────────────────────────┘
select e.nombre,
       count(*)                as clases_futuras,
       min(c.creditos)         as precio_min,
       max(c.creditos)         as precio_max,
       count(*) filter (where coalesce(c.creditos, 0) <= 0) as sin_precio
  from public.clases c
  join public.estudios e on e.id = c.estudio_id
 where c.fecha >= now()
   and coalesce(c.tipo, 'clase') <> 'workshop'
 group by e.nombre
 order by e.nombre;
