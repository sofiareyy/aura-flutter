-- ============================================================================
-- AURA — Tope de sanidad para el precio en créditos
-- ============================================================================
-- (2026-08-22) Arreglo 3 de 5 de la tanda de control de pricing.
--
-- POR QUÉ
-- No había NINGÚN check sobre `creditos` en las dos tablas. Los triggers de
-- precio cubren las clases normales, pero salen temprano con
-- `current_user not in ('authenticated','anon')` y eximen a los workshops, así
-- que quedaban dos caminos sin ningún límite:
--   * las experiencias (workshops), donde el estudio pone el monto libre
--   * cualquier escritura de Aura por SQL o desde una Edge Function
-- Nada impedía un 9999 ni un valor negativo.
--
-- Este es el primer control que aplica a TODOS los escritores, Aura incluida.
-- Es a propósito: es el backstop que no depende de `current_user`.
--
-- EL RANGO: 0 a 500
--
-- Piso en 0, no en 1:
--   * bloquea negativos, que hoy nada impedía y romperían el descuento de
--     créditos en la reserva
--   * deja pasar el cero, que hace falta para las experiencias gratis (ya
--     funcionan) y para la excepción de precio del Modelo C que viene
--     (running clubs gratis)
--
-- Techo en 500, no en 200. El precio de una experiencia sale de
-- `monto ÷ (1 - comision) ÷ valor_credito`. Con los nueve estudios en
-- valor_credito = 1000 y comisión 15%:
--       100 cr = $85.000     200 cr = $170.000
--       500 cr = $425.000    9999 cr = $8.499.150
-- Un retiro de día completo o una formación pasa los $170.000 sin esfuerzo,
-- así que 200 habría bloqueado eventos legítimos. 500 es diez veces la
-- experiencia más cara que existe hoy (50 créditos) y sigue matando el 9999
-- por un factor de veinte.
--
-- El tope en créditos se ajusta solo con la inflación, y en la dirección
-- correcta: si sube `valor_credito`, el mismo evento en pesos pasa a valer
-- MENOS créditos. No hay que revisar este número cada vez que se actualizan
-- precios.
--
-- VERIFICADO ANTES DE APLICAR (22/8, contra producción)
--   * 955 filas reales (885 clases + 70 horarios fijos), 0 fuera de rango
--   * rangos reales: clases 11–50, horarios fijos 11–18, sin nulos ni negativos
--   * en tabla temporal con el constraint y los triggers reales, como
--     `authenticated`: 9999 rechazado, -5 rechazado, 501 rechazado,
--     500 pasa, 400 pasa, 0 pasa, y las clases de los 9 estudios cargan y se
--     reprecian dentro de su rango.
--
-- NOT VALID + VALIDATE: el ADD no escanea la tabla y no puede fallar por datos
-- existentes; el VALIDATE posterior toma un lock más liviano que un ADD
-- directo y, como las 955 filas pasan, es instantáneo. Se termina con el
-- constraint plenamente vigente y sin riesgo en ningún paso.
--
-- SI ALGÚN DÍA HACE FALTA SALIRSE DEL RANGO: hay que tocar el constraint a
-- mano. Es intencional.
-- ============================================================================

alter table public.clases
  drop constraint if exists clases_creditos_sanos;

alter table public.clases
  add constraint clases_creditos_sanos
  check (creditos is null or (creditos >= 0 and creditos <= 500))
  not valid;

alter table public.clases
  validate constraint clases_creditos_sanos;

comment on constraint clases_creditos_sanos on public.clases is
  'Tope de sanidad del precio. 0 permite gratis (experiencias y la excepcion del Modelo C); 500 creditos son ~$425.000 al estudio con valor_credito 1000. Aplica tambien a postgres y service_role, a diferencia de los triggers de precio.';


alter table public.horarios_fijos
  drop constraint if exists horarios_fijos_creditos_sanos;

alter table public.horarios_fijos
  add constraint horarios_fijos_creditos_sanos
  check (creditos is null or (creditos >= 0 and creditos <= 500))
  not valid;

alter table public.horarios_fijos
  validate constraint horarios_fijos_creditos_sanos;

comment on constraint horarios_fijos_creditos_sanos on public.horarios_fijos is
  'Mismo tope que clases_creditos_sanos, para que la grilla no pueda sembrar precios absurdos en 9 semanas de clases.';


-- ── VERIFICACIÓN (correr aparte, no destructiva) ────────────────────────────
-- select conname, convalidated, pg_get_constraintdef(oid)
--   from pg_constraint
--  where conname in ('clases_creditos_sanos','horarios_fijos_creditos_sanos');
--
-- Debe dar convalidated = true en las dos.
