-- ============================================================================
-- AURA — Sin precio configurado no se pueden cargar clases
-- ============================================================================
-- (2026-08-22) Arreglo 2 de 5 de la tanda de control de pricing.
--
-- EL AGUJERO
-- Cuando `calcular_precio_clase` no podía resolver un precio (estudio sin
-- `creditos_min`, o estudio inexistente) los dos triggers dejaban pasar la
-- escritura a propósito, "para no bloquear la carga". El resultado no era
-- neutro: la clase nacía con el default de la columna
-- `horarios_fijos.creditos`, que es 10. Un número que no eligió nadie,
-- invisible, y que después queda fijo hasta que alguien recalcule.
--
-- Es el agujero de onboarding: entre "creo el estudio" y "le configuro el
-- precio" hay una ventana donde el estudio puede cargar toda su grilla a 10
-- créditos.
--
-- EL ARREGLO
-- Rechazar en vez de dejar pasar. El mensaje es para que lo lea la dueña de
-- un estudio, no un backend: dice qué falta y qué hacer.
--
--     "Falta configurar el precio de este estudio para poder cargar clases.
--      Escribinos y lo activamos."
--
-- Compone bien con el prefijo que ya pone la pantalla de editar clase
-- ("No se pudo guardar: ..."), y se lee solo en la API y el backoffice.
--
-- POR QUÉ NO ROMPE NADA HOY
-- Verificado contra producción antes de aplicar: los 9 estudios devuelven
-- ok=true, 0 clases huérfanas, 0 horarios fijos huérfanos. Nadie cae en este
-- camino.
--
-- Las reservas tampoco se rompen si algún día un estudio quedara sin precio:
-- una reserva toca `lugares_disponibles`, y esa salida temprana está ARRIBA
-- del cálculo, así que ni siquiera llega al raise. Verificado.
--
-- Los caminos de Aura (generar_clases_estudio, admin_recalcular_precios_
-- estudio, apply_reservation) son security definer, así que salen en la
-- primera línea por `current_user` y no ven este cambio.
--
-- PENDIENTE DEL LADO DART (no lo tapa esta migración)
-- `mis_clases_screen.dart` descarta el mensaje del servidor en el alta de
-- clase y de horario fijo, y muestra "No se pudo crear la clase. Intentá de
-- nuevo." — genérico, y encima invita a reintentar para siempre. El camino de
-- EDITAR clase sí lo muestra. Hasta que ese catch propague el mensaje, la
-- protección funciona pero el texto sólo llega por el camino de edición.
-- Mitigación operativa mientras tanto: configurar el precio del estudio ANTES
-- de darle el acceso.
-- ============================================================================

create or replace function public.clases_fija_precio()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  v_res json;
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  -- Workshops: el precio se carga en pesos y lo deriva Aura. No se toca.
  if coalesce(new.tipo, 'clase') = 'workshop' then
    return new;
  end if;

  -- En un UPDATE solo actuamos si cambió algo que afecta el precio. Sin esto
  -- recalcularíamos en cada reserva (que toca lugares_disponibles) al pedo.
  -- `tipo` entra en la lista para cerrar el bypass workshop -> clase.
  if tg_op = 'UPDATE'
     and new.creditos   is not distinct from old.creditos
     and new.fecha      is not distinct from old.fecha
     and new.estudio_id is not distinct from old.estudio_id
     and new.tipo       is not distinct from old.tipo then
    return new;
  end if;

  v_res := public.calcular_precio_clase(
    new.estudio_id,
    null,
    extract(isodow from new.fecha)::int,
    to_char(new.fecha, 'HH24:MI')
  );

  -- Estudio sin precio configurado: se rechaza. Antes se dejaba pasar y la
  -- clase se quedaba con el default escondido de 10 creditos.
  if not coalesce((v_res ->> 'ok')::boolean, false) then
    raise exception 'Falta configurar el precio de este estudio para poder cargar clases. Escribinos y lo activamos.';
  end if;

  new.creditos    := (v_res ->> 'creditos')::int;
  new.tipo_precio := v_res ->> 'tipo';

  return new;
end;
$function$;


create or replace function public.horarios_fijos_fija_precio()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  v_res json;
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  -- to_jsonb en vez de new.tipo: horarios_fijos puede no tener esa columna en
  -- todos los entornos y así el trigger no rompe si falta.
  if coalesce(to_jsonb(new) ->> 'tipo', 'clase') = 'workshop' then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and new.creditos    is not distinct from old.creditos
     and new.dia_semana  is not distinct from old.dia_semana
     and new.hora_inicio is not distinct from old.hora_inicio
     and new.estudio_id  is not distinct from old.estudio_id then
    return new;
  end if;

  v_res := public.calcular_precio_clase(
    new.estudio_id,
    null,
    new.dia_semana,
    to_char(new.hora_inicio, 'HH24:MI')
  );

  -- Mismo criterio que en clases: sin precio configurado no se carga grilla.
  if not coalesce((v_res ->> 'ok')::boolean, false) then
    raise exception 'Falta configurar el precio de este estudio para poder cargar clases. Escribinos y lo activamos.';
  end if;

  new.creditos := (v_res ->> 'creditos')::int;

  return new;
end;
$function$;


-- ── VERIFICACIÓN (correr aparte, no destructiva) ────────────────────────────
-- El estudio_id 999999 no existe, así que calcular_precio_clase devuelve
-- ok=false igual que un estudio sin precio cargado.
--
-- begin;
--   create temp table t (like public.clases including defaults);
--   grant all on t to authenticated;
--   create trigger tt before insert or update on t
--     for each row execute function public.clases_fija_precio();
--   set local role authenticated;
--   -- (a) debe FALLAR con el mensaje humano:
--   insert into t (id, estudio_id, nombre, fecha, tipo, creditos,
--                  lugares_total, lugares_disponibles)
--   values (1, 999999, 'x', '2026-09-02 19:00:00', 'clase', 10, 10, 10);
-- rollback;
