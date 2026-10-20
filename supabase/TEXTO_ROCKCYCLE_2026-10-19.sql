-- El aviso de "primera vez" en todas las clases de Rockcycle (58 y 59).
-- APLICADO EN PRODUCCIÓN el 2026-10-19.
--
-- Va en los HORARIOS FIJOS para que lo herede cada clase que genere la
-- grilla de acá en adelante —eso recién es posible desde hoy, cuando
-- `horarios_fijos` ganó la columna `descripcion`— y en las clases FUTURAS ya
-- generadas, que son las que la gente va a abrir.
--
-- Las clases PASADAS no se tocan: son historia, y el texto es una indicación
-- para antes de ir. Mismo criterio que la regla de plata — lo pasado queda
-- sellado.
--
-- `concat_ws` y no una concatenación suelta: si algún día ya hay descripción,
-- el texto se agrega al final separado por un renglón en blanco, y si está
-- vacía no deja un salto de línea colgando adelante.

update public.horarios_fijos
   set descripcion = concat_ws(
         E'\n\n',
         nullif(trim(coalesce(descripcion, '')), ''),
         '¿Primera vez en Rockcycle? Llegá 15 minutos antes para que te ayudemos con el talle del calzado y hacer el ingreso.')
 where estudio_id in (58, 59)
   and coalesce(descripcion, '') not like '%¿Primera vez en Rockcycle?%';

update public.clases
   set descripcion = concat_ws(
         E'\n\n',
         nullif(trim(coalesce(descripcion, '')), ''),
         '¿Primera vez en Rockcycle? Llegá 15 minutos antes para que te ayudemos con el talle del calzado y hacer el ingreso.')
 where estudio_id in (58, 59)
   and fecha > now()
   and not cancelada
   and coalesce(descripcion, '') not like '%¿Primera vez en Rockcycle?%';
