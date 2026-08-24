-- ============================================================================
-- AURA — El estudio no puede marcar asistencia antes de tiempo
-- ============================================================================
-- Aplicado a mano vía la Management API el 2026-08-24 (quinta tanda del día).
-- Sin Dart ⇒ sin build. Preparación para el alta de Rock Studio.
--
-- ── QUÉ SE MIDIÓ ANTES DE TOCAR NADA ───────────────────────────────────────
-- Marcar asistencia es un UPDATE directo del cliente sobre `reservas`, sin
-- función de por medio. Se auditaron los vectores y **tres de cuatro ya
-- estaban cerrados** por RLS y por `reservas_bloquear_columnas_sensibles`:
--   · un estudio marcando una reserva de OTRO estudio → el UPDATE toca 0 filas
--   · revivir 'cancelada'/'cancelada_por_estudio' → P0001
--   · cambiar `creditos_usados` → P0001
--   · fabricar una reserva → 42501 (`reservas` no tiene policy de INSERT)
--
-- ── EL QUE SÍ ESTABA ABIERTO ───────────────────────────────────────────────
-- El QR no se valida en la base: el estudio podía marcar 'presente' cualquier
-- reserva suya, sin escanear, incluso de clases a 5 o 30 días vista.
-- Eso NO inflaba la liquidación por sí solo —'confirmada' y 'presente' están
-- las dos en `estadosLiquidables`, así que el monto es el mismo—. El daño era
-- otro, y medido:
--
--   sin marcar presente → la alumna cancela a 5 días:
--       {ok:true, creditos_devueltos:18} · saldo 50 → 68
--   con el estudio marcando presente por adelantado:
--       {ok:false, error:"estado_invalido"} · saldo queda en 50
--
-- O sea: marcando presente antes de tiempo el estudio **le trababa la
-- cancelación a la alumna y le retenía los créditos**. Y sí movía plata, por
-- la vía indirecta: sin ese movimiento la reserva se habría cancelado y no
-- sería liquidable; con él, queda liquidable y el estudio cobra.
-- Hecho a escala, ningún alumno podría cancelar nunca. Y no queda rastro: no
-- hay log de cambios de estado en `reservas`.
--
-- ── LA REGLA ───────────────────────────────────────────────────────────────
-- La asistencia se puede marcar **recién cuando la alumna ya no puede
-- cancelar**. Es exactamente el daño, escrito como regla.
-- Usa la MISMA cascada que `cancelar_mi_reserva`: clase → estudio → 720 min.
--
-- Se eligió esto por sobre "rechazar si la clase no empezó, con 10 min de
-- tolerancia" porque esa versión rompía dos casos legítimos: el check-in de
-- quien llega 15-20 minutos antes (clave en un estudio de 50 bicis) y el
-- marcado manual el mismo día de la clase. Con la ventana de cancelación, una
-- clase de las 19:00 con cierre de 12 h se puede marcar desde las 07:00 de ese
-- día: el marcado manual del día sigue andando y el check-in temprano también.
-- El `greatest(cierre, 10)` conserva la tolerancia del escáner para el caso de
-- un estudio que ponga la ventana en 0.
--
-- ── LAS DOS PUNTAS, midiendo efecto ────────────────────────────────────────
-- Como `citrabarre@gmail.com` (estudio real, NO superadmin), ventana 720 min.
-- Todo con rollback.
--
--   QUE IMPIDA                            antes         ahora
--   clase dentro de 5 días           marcó presente   RECHAZADO
--   clase dentro de 30 días          marcó presente   RECHAZADO
--   clase mañana                     marcó presente   RECHAZADO
--   clase en 13 h (ventana abierta)  marcó presente   RECHAZADO
--   idem marcando 'ausente'          marcó ausente    RECHAZADO
--
--   QUE NO ROMPA                          antes         ahora
--   clase en 11 h (ventana cerrada)  marcó presente   marcó presente
--   clase en 20 min (por empezar)    marcó presente   marcó presente
--   clase empezando ahora            marcó presente   marcó presente
--   clase que empezó hace 30 min     marcó presente   marcó presente
--   clase de ayer (corregir tarde)   marcó presente   marcó presente
--   marcar 'ausente' después         marcó ausente    marcó ausente
--   estudio con ventana en 0         marcó presente   marcó presente
--
--   LO DECISIVO — después del intento del estudio, la alumna cancela:
--       antes: {ok:false, error:"estado_invalido"} · saldo 50
--       ahora: {ok:true, creditos_devueltos:18}    · saldo 50 → 68
-- ============================================================================

create or replace function public.reservas_no_marcar_antes_de_tiempo()
returns trigger
language plpgsql
set search_path to 'public'
as $fn$
declare
  v_clase    record;
  v_estudio  record;
  v_cierre   int;
  v_desde    timestamp;
  v_ahora    timestamp := (now() at time zone 'America/Argentina/Buenos_Aires');
begin
  -- Solo la escritura DIRECTA del cliente. Las RPC security definer y el
  -- service_role corren con otro current_user y pasan. Mismo patron que
  -- reservas_bloquear_columnas_sensibles.
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  -- Solo nos importa PASAR a presente/ausente. Cualquier otra transicion
  -- (cancelar, deshacer a confirmada) queda libre.
  if new.estado is not distinct from old.estado
     or coalesce(new.estado, '') not in ('presente', 'ausente') then
    return new;
  end if;

  select * into v_clase from public.clases where id = new.clase_id;
  if not found or v_clase.fecha is null then
    return new;
  end if;

  select * into v_estudio from public.estudios where id = v_clase.estudio_id;

  -- MISMA cascada que cancelar_mi_reserva: clase -> estudio -> 720 (12 h).
  v_cierre := coalesce(
    v_clase.cancelacion_cierre_minutos,
    v_estudio.cancelacion_cierre_minutos,
    720
  );

  -- La asistencia se puede marcar recien cuando la alumna YA NO puede cancelar.
  -- Ese es exactamente el dano que esto evita: marcando presente por adelantado
  -- el estudio le trababa la cancelacion y le retenia los creditos.
  -- El `greatest(v_cierre, 10)` es la tolerancia del escaner: si un estudio
  -- pone la ventana en 0, igual se puede hacer check-in 10 min antes.
  v_desde := v_clase.fecha - make_interval(mins => greatest(v_cierre, 10));

  if v_ahora < v_desde then
    raise exception
      'Todavía no podés marcar asistencia en esta clase: no empezó y la alumna todavía puede cancelar y recuperar sus créditos. Vas a poder a partir del % a las %.',
      to_char(v_desde, 'DD/MM'), to_char(v_desde, 'HH24:MI');
  end if;

  return new;
end
$fn$;

drop trigger if exists trg_reservas_no_marcar_antes on public.reservas;
create trigger trg_reservas_no_marcar_antes
  before update on public.reservas
  for each row
  execute function public.reservas_no_marcar_antes_de_tiempo();
