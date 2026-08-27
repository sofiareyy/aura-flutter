-- `estudios_datos_cobro.valor_credito` NULL = "seguí al valor global".
-- Decisión de la usuaria del 27/8 (opción A).
--
-- QUÉ SIGNIFICA CADA ESTADO, para que nadie lo lea como un bug:
--   · NULL  -> el estudio va al valor global (`configuracion_global.
--              valor_credito_ars`). Es lo NORMAL y lo CORRECTO para un estudio
--              a tarifa estándar. **Un estudio nuevo nace así a propósito.**
--   · número -> override: sólo para un valor NEGOCIADO distinto del estándar.
--
-- Los tres caminos que calculan plata ya aplican ese fallback, verificado el
-- 27/8: la app (`ValorCredito.deEstudio`), el reporte mensual
-- (`reporte-mensual-estudios`, `valorCred(estudio, valorGlobal)`) y la base
-- (`valor_credito_global()`, que además devuelve 1000 ante cualquier error).
--
-- POR QUÉ SE LIMPIAN LOS 9 QUE TENÍAN 1000 EN DURO:
-- tenían una copia congelada del global. Medido: si mañana se sube el crédito
-- global a 1200, esos 9 se quedaban clavados en 1000 y sólo los que estaban en
-- NULL acompañaban. O sea, el problema era al revés de lo que parecía: los
-- raros eran los explícitos, no los NULL.
--
-- Verificado ANTES de aplicar: de los 11 estudios, 2 ya estaban en NULL y 9
-- tenían exactamente 1000. **CERO con un valor negociado distinto**, así que no
-- se pisa ninguna excepción. El `= 1000` del WHERE es el seguro: si alguno
-- tuviera otro número, no se toca.

comment on column public.estudios_datos_cobro.valor_credito is
  'NULL = seguí el valor global (configuracion_global.valor_credito_ars). Es lo normal y un estudio nuevo nace así A PROPÓSITO, no es un alta incompleta. Poner un número SOLO para un valor negociado distinto del estándar.';

update public.estudios_datos_cobro
   set valor_credito = null
 where valor_credito = (select nullif(trim(valor),'')::int
                          from public.configuracion_global
                         where clave = 'valor_credito_ars');
