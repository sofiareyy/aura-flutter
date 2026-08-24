-- ============================================================================
-- AURA — Editar el día/hora de una grilla MUEVE las clases, ya no las duplica
-- ============================================================================
-- Aplicado a mano vía la Management API el 2026-08-24 (tercera tanda del día).
-- Sin Dart ⇒ sin build. Los estudios lo tienen ya.
--
-- ── EL BUG ─────────────────────────────────────────────────────────────────
-- Al editar un horario fijo, la app hace tres pasos: (1) actualiza la grilla,
-- (2) `_propagarHorarioFijoAClasesFuturas` copia los campos a las clases
-- futuras — pero NO la fecha —, y (3) vuelve a generar la grilla.
-- Como la fecha no se propagaba, editar el día o la hora fallaba de dos formas
-- distintas según el tamaño del cambio:
--   · corrimiento > 1 hora, o cambio de día → las clases viejas quedaban
--     publicadas en el horario anterior y el generador creaba otras nuevas
--     encima: 9 clases pasaban a ser 18, duplicadas, sin ningún aviso.
--   · corrimiento <= 1 hora → se ignoraba en silencio, porque el chequeo de
--     existencia de `generar_clases_estudio` da por "ya creada" cualquier
--     clase de esa grilla que caiga dentro de ±1 hora.
-- El estudio no tenía forma de arreglarlo salvo borrar la grilla entera.
--
-- ── EL ARREGLO ─────────────────────────────────────────────────────────────
-- Un trigger en `horarios_fijos` que, cuando cambia `dia_semana` o
-- `hora_inicio`, MUEVE las clases futuras de esa grilla. Se mete en el paso 1,
-- así que para cuando corre el paso 3 las clases ya están en el horario nuevo,
-- el chequeo de existencia las encuentra y las saltea: los duplicados no
-- llegan a nacer. **No hace falta tocar Dart.**
--
-- ⚠️ EL TRIGGER ES *INVOKER*, NO SECURITY DEFINER, Y ESO ES A PROPÓSITO.
-- El `update public.clases` de adentro dispara `clases_fija_precio`, que
-- arranca con `if current_user not in ('authenticated','anon') then return new`.
-- Siendo invoker, el update corre con el rol del estudio y el precio se
-- recalcula solo cuando la clase cambia de franja. Si se lo pasara a SECURITY
-- DEFINER correría como `postgres`, el trigger de precio saldría temprano y una
-- clase movida de valle a pico se quedaría con el precio viejo. (Fue
-- exactamente el falso negativo que dio la primera medición de esto, hecha
-- como postgres.)
--
-- ── LAS DOS PUNTAS, midiendo efecto ────────────────────────────────────────
-- Probado como `sculptclub.ar@gmail.com` (estudio real, NO superadmin), en
-- Sculpt Club que está en modo rango (14 valle / 16 pico). Todo con rollback;
-- verificado que quedaron 0 filas.
--
--   QUE FUNCIONE                          antes            ahora
--   hora 10:00→19:00 (valle→pico)   9→18 duplica     9→9 · 19:00 · 14→16 cr
--   hora 19:00→10:00 (pico→valle)   9→18 duplica     9→9 · 10:00 · 16→14 cr
--   día  miércoles→viernes          9→18 duplica     9→9 · viernes
--   hora 10:00→10:30 (30 min)       se ignoraba      9→9 · 10:30
--   día Y hora juntos               9→18 duplica     9→9 · viernes 19:00 · 14→16
--
--   QUE NO ROMPA                          antes            ahora
--   solo la profe                   9→9 ok           9→9 ok, profe actualizada
--   solo el cupo                    9→9 ok           9→9 ok
--   solo los créditos               9→9 ok           9→9 ok
--   clases PASADAS de la grilla     no se tocan      no se tocan (15/7 quedó
--                                                     en 15/7 10:00)
--
-- ── LO QUE QUEDA DECIDIR, ANTES DEL 13/9 ───────────────────────────────────
-- Mover una clase le cambia el horario a quien YA se anotó. Hoy eso no muerde:
-- medido, hay 0 clases futuras de grilla con reservas activas. Desde el 13/9,
-- cuando arranquen los cobros y las reservas reales, hay que elegir entre
-- avisarle a la alumna con una campanita automática (la preferida) o rechazar
-- el cambio si hay anotadas. Ver RETOMAR_ACA.
--
-- Nota: si el estudio movió A MANO una clase suelta de esta grilla, este
-- trigger se la vuelve a alinear con el molde. Es el mismo criterio que ya
-- aplicaba la propagación de nombre/profe/cupo.
-- ============================================================================

create or replace function public.horarios_fijos_mover_clases()
returns trigger
language plpgsql
set search_path to 'public'
as $fn$
declare
  v_hora   int;
  v_minuto int;
begin
  -- Solo actuamos si cambio CUANDO se dicta la clase. El resto de los campos
  -- (profe, cupo, creditos, categorias...) ya los propaga el cliente en
  -- `_propagarHorarioFijoAClasesFuturas`, y no queremos tocar fechas al pedo.
  if new.dia_semana  is not distinct from old.dia_semana
 and new.hora_inicio is not distinct from old.hora_inicio then
    return new;
  end if;

  if new.dia_semana is null or new.dia_semana < 1 or new.dia_semana > 7 then
    return new;
  end if;

  v_hora   := coalesce(extract(hour   from new.hora_inicio)::int, 8);
  v_minuto := coalesce(extract(minute from new.hora_inicio)::int, 0);

  -- Se MUEVEN las clases futuras de esta grilla, en su misma semana.
  -- `date_trunc('week', ...)` da el lunes, que es el mismo ancla que usa
  -- `generar_clases_estudio` (`v_week_start := hoy - (isodow - 1)`), asi que
  -- la fecha resultante es identica a la que generaria la grilla nueva. Por
  -- eso, cuando el cliente vuelve a generar, el chequeo de existencia
  -- (horario_fijo_id + fecha ±1 hora) las encuentra y las saltea: los
  -- duplicados no llegan a nacer.
  --
  -- Las PASADAS no se tocan: son historia, y de ahi cuelgan asistencias y
  -- liquidaciones.
  update public.clases c
     set fecha = (date_trunc('week', c.fecha)::date + (new.dia_semana - 1))::timestamp
                 + make_interval(hours => v_hora, mins => v_minuto)
   where c.horario_fijo_id = new.id
     and c.fecha >= (now() at time zone 'America/Argentina/Buenos_Aires')::date;

  return new;
end
$fn$;

drop trigger if exists trg_horarios_fijos_mover_clases on public.horarios_fijos;
create trigger trg_horarios_fijos_mover_clases
  after update on public.horarios_fijos
  for each row
  execute function public.horarios_fijos_mover_clases();
