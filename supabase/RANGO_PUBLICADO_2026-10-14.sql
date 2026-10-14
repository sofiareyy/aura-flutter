-- "PRECIO REDUCIDO" deja de prometer descuentos que no existen.
-- APLICADO EN PRODUCCIÓN el 2026-10-14. Copia de lo que se corrió.
--
-- EL PROBLEMA, MEDIDO
--
-- El cartel se decidía comparando el precio de la clase contra
-- `estudios.creditos_max`, que NO es un techo observado: es la CONFIGURACIÓN
-- de precios del estudio (`tipo_precio='rango'` ⇒ franja valle cobra
-- `creditos_min`, el resto `creditos_max`).
--
-- Un estudio puede declarar un rango y no realizarlo nunca. Es lo que pasa:
--
--   Rock Studios Palermo   declara 16–18   cobra 16 en sus 252 clases
--   Rock Studios Recoleta  declara 16–18   cobra 16 en sus 193 clases
--   Delta Heat Yoga        declara 14–17   cobra 14 en sus  42 clases
--
-- Los tres tienen TODAS sus clases en franja `valle`: nunca marcaron un
-- horario como pico, así que el techo no se aplica a nada. El cartel les
-- salía en el 100% de sus clases, prometiendo una rebaja contra un precio que
-- el estudio no cobra nunca. Son 487 clases: el 46% de todos los carteles.
--
-- Es la segunda vuelta del mismo bug. El 26/8 se arregló la versión que
-- miraba el NOMBRE de la franja ('normal' o 'valle'), que lo ponía en 823 de
-- 997 clases. Quedó ésta, que mira un techo declarado en vez de uno real.
--
-- Con esta vista: de 1.051 clases con cartel se pasa a 564, y las tres de
-- arriba dejan de mostrarlo.
--
-- POR QUÉ UNA VISTA Y NO UNA COLUMNA
--
-- El comentario del código pedía que el cartel NO dependa de qué página de la
-- lista se trajo, y tenía razón: calcular el máximo sobre las clases cargadas
-- haría que la misma clase mostrara o no el cartel según cuánto hubieras
-- scrolleado. Una agregación del lado del servidor lo resuelve sin
-- denormalizar nada ni mantener un trigger por cada clase que se publica
-- (la grilla publica cientos de una).

create or replace view public.estudios_rango_publicado
with (security_invoker = true) as
  select c.estudio_id,
         min(c.creditos) as cr_min_publicado,
         max(c.creditos) as cr_max_publicado
    from public.clases c
   where c.fecha > now()
     and not c.cancelada
     -- Un servicio de precio fijo no entra en el juego de franjas: su precio
     -- es único por definición. Ya quedaba afuera del cartel en el cliente;
     -- acá se excluye para que tampoco corra el techo del estudio.
     and coalesce(c.tipo_precio, '') <> 'servicio'
   group by c.estudio_id;

-- `security_invoker` para que la vista respete la RLS de `clases` y no se
-- convierta en una puerta que muestre clases de estudios inactivos.
grant select on public.estudios_rango_publicado to anon, authenticated;

comment on view public.estudios_rango_publicado is
  'Rango de precios que el estudio REALMENTE publica hoy (clases futuras, sin cancelar, sin servicios de precio fijo). Lo usa el cartel PRECIO REDUCIDO de Explorar: comparar contra estudios.creditos_max daba falsos positivos en estudios que declaran un rango y cobran siempre el piso.';
