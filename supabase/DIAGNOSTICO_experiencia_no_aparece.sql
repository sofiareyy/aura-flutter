-- AURA — Una experiencia publicada no aparece en el perfil del estudio.
-- (2026-08-10). Solo LEE.
--
-- Hipótesis principales, de más a menos probable:
--   A) La fecha cae fuera de la ventana de 30 días que pide la pantalla.
--   B) Está más allá de las 5 primeras clases (la pantalla muestra 5 y el
--      resto queda detrás de "ver todas").
--   C) No hay policy de SELECT público sobre `clases` y la lectura sin login
--      devuelve vacío.
--
-- Reemplazá el nombre del estudio en la consulta 1 y usá ese id en las demás.


-- 1) ¿Cuál es el estudio? Anotá el id.
select id, nombre, activo, tipo_estudio
  from public.estudios
 where nombre ilike '%PONE_ACA_PARTE_DEL_NOMBRE%';


-- 2) LAS EXPERIENCIAS DEL ESTUDIO Y POR QUÉ SE VERÍAN O NO.
--    `dentro_ventana_30d` es la condición exacta que aplica la pantalla
--    (estudios_service.getClasesDeEstudio: fecha entre ahora y ahora+30 días).
--    `posicion` es el lugar que ocupa en la lista ordenada por fecha: si es
--    mayor a 5, queda detrás del "ver todas".
with ahora as (
  select (now() at time zone 'America/Argentina/Buenos_Aires') as t
),
visibles as (
  select c.*,
         row_number() over (order by c.fecha) as posicion
    from public.clases c, ahora a
   where c.estudio_id = PONE_ACA_EL_ID
     and c.fecha >= a.t
     and c.fecha <= a.t + interval '30 days'
)
select c.id,
       c.nombre,
       coalesce(c.tipo, 'clase') as tipo,
       c.fecha,
       c.creditos,
       c.lugares_total,
       c.lugares_disponibles,
       (c.fecha >= a.t)                              as es_futura,
       (c.fecha <= a.t + interval '30 days')         as dentro_ventana_30d,
       v.posicion                                    as posicion_en_lista,
       case
         when c.fecha < a.t
           then 'NO SE VE: ya pasó'
         when c.fecha > a.t + interval '30 days'
           then 'NO SE VE: la pantalla solo trae 30 días'
         when v.posicion > 5
           then 'Se ve solo si el usuario toca "ver todas" (está en la posición ' || v.posicion || ')'
         else 'Debería verse'
       end                                           as veredicto
  from public.clases c
  cross join ahora a
  left join visibles v on v.id = c.id
 where c.estudio_id = PONE_ACA_EL_ID
   and coalesce(c.tipo, 'clase') = 'workshop'
 order by c.fecha;


-- 3) Todas las clases del estudio dentro de la ventana, para ver cuántas hay
--    antes de la experiencia. Si son 5 o más, la experiencia queda escondida.
select coalesce(tipo, 'clase') as tipo,
       count(*) as cantidad,
       min(fecha) as primera,
       max(fecha) as ultima
  from public.clases
 where estudio_id = PONE_ACA_EL_ID
   and fecha >= (now() at time zone 'America/Argentina/Buenos_Aires')
   and fecha <= (now() at time zone 'America/Argentina/Buenos_Aires') + interval '30 days'
 group by coalesce(tipo, 'clase');


-- 4) La experiencia completa, tal cual quedó guardada. Sirve para descartar
--    que haya fallado la publicación (campos vacíos, tipo mal, etc.).
select *
  from public.clases
 where estudio_id = PONE_ACA_EL_ID
   and coalesce(tipo, 'clase') = 'workshop'
 order by fecha desc
 limit 5;


-- 5) ¿Hay policy de SELECT sobre `clases`? La app la lee sin login, así que
--    tiene que existir una para `anon` y/o `authenticated`.
--    Si NO aparece ninguna fila con cmd = 'SELECT', ese es el problema.
select policyname, cmd, roles, qual as condicion
  from pg_policies
 where schemaname = 'public'
   and tablename = 'clases'
 order by cmd, policyname;
