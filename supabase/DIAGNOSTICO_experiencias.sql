-- AURA — Experiencias (workshops): por qué no se ven en el perfil del estudio
-- y si los organizadores están bien guardados. (2026-08-10). Solo LEE.
--
-- No hace falta buscar ningún id: trae TODAS las experiencias futuras.
-- Copiá y corré tal cual.

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 1) TODAS las experiencias futuras, con el veredicto de dónde se ven      │
-- └──────────────────────────────────────────────────────────────────────────┘
-- El home trae 90 días. El perfil del estudio trae 30 y muestra 5.
with ahora as (
  select (now() at time zone 'America/Argentina/Buenos_Aires') as t
),
pos as (
  select c.id,
         row_number() over (
           partition by c.estudio_id order by c.fecha
         ) as posicion_en_perfil
    from public.clases c, ahora a
   where c.fecha >= a.t
     and c.fecha <= a.t + interval '30 days'
)
select e.nombre                                   as estudio,
       c.nombre                                   as experiencia,
       c.fecha,
       (c.fecha - a.t)::interval                  as falta,
       jsonb_array_length(
         coalesce(to_jsonb(c.organizadores), '[]'::jsonb)
       )                                          as cant_organizadores,
       c.organizadores,
       case when c.fecha <= a.t + interval '90 days'
            then 'SÍ' else 'no (más de 90 días)' end  as se_ve_en_home,
       case
         when c.fecha > a.t + interval '30 days'
           then 'NO — el perfil solo trae 30 días'
         when p.posicion_en_perfil > 5
           then 'solo tocando "ver todas" (posición ' || p.posicion_en_perfil || ')'
         else 'sí'
       end                                        as se_ve_en_perfil_estudio
  from public.clases c
  join public.estudios e on e.id = c.estudio_id
  cross join ahora a
  left join pos p on p.id = c.id
 where coalesce(c.tipo, 'clase') = 'workshop'
   and c.fecha >= a.t
 order by c.fecha;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 2) Los organizadores, uno por fila, para leerlos cómodo                  │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Cada experiencia puede tener 2 (o más). Verificá que estén el `nombre` y el
-- `instagram` de los dos.
select e.nombre                    as estudio,
       c.nombre                    as experiencia,
       c.fecha,
       org.valor ->> 'nombre'      as organizador_nombre,
       org.valor ->> 'instagram'   as organizador_arroba
  from public.clases c
  join public.estudios e on e.id = c.estudio_id
  cross join lateral jsonb_array_elements(
    coalesce(to_jsonb(c.organizadores), '[]'::jsonb)
  ) as org(valor)
 where coalesce(c.tipo, 'clase') = 'workshop'
   and c.fecha >= (now() at time zone 'America/Argentina/Buenos_Aires')
 order by c.fecha, organizador_nombre;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 3) ¿Existe policy de lectura pública sobre `clases`?                     │
-- └──────────────────────────────────────────────────────────────────────────┘
-- La app lista clases sin login, así que tiene que haber una de SELECT.
-- Si no aparece ninguna fila con cmd = 'SELECT', ese sería otro problema
-- (pero entonces no se vería NINGUNA clase, así que probablemente sí está).
select policyname, cmd, roles, qual as condicion
  from pg_policies
 where schemaname = 'public'
   and tablename = 'clases'
 order by cmd, policyname;
