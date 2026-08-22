-- ============================================================================
-- AURA — Se va el default escondido de 10 créditos
-- ============================================================================
-- (2026-08-22) Arreglo 4 de 5 de la tanda de control de pricing.
--
-- POR QUÉ
-- `horarios_fijos.creditos` tenía `default 10`. Ese 10 no lo eligió nadie: era
-- el valor con el que nacía una grilla cuando el precio no se resolvía por la
-- regla (estudio sin `creditos_min`). El agujero de onboarding.
--
-- POR QUÉ RECIÉN AHORA
-- Sacarlo antes habría sido peor que dejarlo. Sin red, un `creditos` en NULL
-- llega a `clases`, y `reservar_clase` hace `coalesce(v_clase.creditos, 0)`:
-- la clase se vuelve GRATIS en silencio. Cambiar "cobra 10 porque sí" por
-- "no cobra nada" no es un arreglo.
--
-- La red es la migración `20260822150000` (arreglo 2): el trigger ahora
-- RECHAZA la carga cuando la regla no puede resolver un precio. Con eso
-- puesto, un estudio nunca llega a escribir un NULL: o recibe el precio
-- calculado, o recibe el rechazo con el mensaje.
--
-- QUÉ QUEDA DESPUÉS DEL CAMBIO
-- NULL pasa a ser el sentinela correcto y ya está interpretado así en el
-- código: `generar_clases_estudio` hace `if coalesce(v_h.creditos, 0) > 0`
-- para decidir si usa el precio del horario o lo calcula. Un NULL cae del
-- lado de "calculalo", que es lo que se quiere. Un 10 no: se propagaba tal
-- cual a 9 semanas de clases.
--
-- VERIFICADO ANTES DE APLICAR (22/8, contra producción)
--   * 0 de las 70 filas de horarios_fijos están en 10 — nada depende del default
--   * sobre un clon temporal con el trigger real:
--       - insert como postgres sin creditos      -> NULL (sentinela correcto)
--       - insert como estudio (Citra, fijo)      -> 18, la regla, no 10
--       - insert como estudio (Sculpt 14h valle) -> 14, la regla
--       - insert de estudio sin precio           -> sigue rechazado (red del #2)
--
-- `clases.creditos` ya era nullable y sin default: no hay nada que sacar ahí.
-- ============================================================================

alter table public.horarios_fijos
  alter column creditos drop default;

comment on column public.horarios_fijos.creditos is
  'Precio del horario en creditos. Lo escribe el trigger horarios_fijos_fija_precio con la regla del estudio (pico/valle); el estudio no lo elige. NULL = sin resolver, y generar_clases_estudio lo interpreta como "calculalo con la regla". Sin default a proposito: un default hacia nacer grillas a 10 creditos que no eligio nadie.';


-- ── VERIFICACIÓN (correr aparte) ────────────────────────────────────────────
-- select column_default from information_schema.columns
--  where table_schema='public' and table_name='horarios_fijos'
--    and column_name='creditos';
-- Debe dar NULL.
