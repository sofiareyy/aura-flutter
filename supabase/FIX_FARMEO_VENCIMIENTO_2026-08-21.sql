-- =====================================================================
-- FIX: farmeo del vencimiento por cancelación + créditos eternos
-- 2026-08-21. Aplicado vía Management API y verificado 12/12 con
-- rollback + efecto. Solo base: aplica a todos sin build.
-- =====================================================================
--
-- EL BUG PRINCIPAL — farmeo
-- `cancelar_mi_reserva` otorgaba un lote NUEVO con 60 días desde la
-- cancelación, sin mirar el vencimiento original. Reservar + cancelar era un
-- loop de dos toques que renovaba créditos indefinidamente.
-- MEDIDO antes del fix: 18 créditos que vencían mañana pasaban a vencer 58
-- días después. Sin tope de cancelaciones, con 584 clases disponibles fuera
-- de la ventana. 3 vueltas seguidas verificadas.
--
-- EL BUG DE ARRASTRE — créditos eternos
-- `reservar_clase`, cuando `apply_reservation` fallaba, compensaba con
-- grant_user_credits(..., null, ...). En el ledger, expires_at null significa
-- NO VENCE NUNCA. Nunca se había disparado (0 filas `rollback_reserva`), pero
-- estaba armado. Se resuelve con el mismo mecanismo.
--
-- POR QUÉ NO ALCANZABA EL PARCHE
-- Se evaluó devolver con min(expires_at) de los lotes vivos. Tiene su propio
-- agujero: si el lote corto vence ENTRE la reserva y la cancelación, sale del
-- min y la devolución hereda el largo (créditos que morían el 20 pasan al 30).
--
-- LA SOLUCIÓN
-- Congelar al reservar de qué lotes salieron los créditos y cuántos de cada
-- uno, y al cancelar devolverlos a esos mismos. No hay fecha que recalcular,
-- así que no importa qué pase en el medio.
--
-- DECISIONES DE NEGOCIO TOMADAS
--  1. Lote ya vencido al cancelar: se devuelve IGUAL. Como
--     refresh_user_credit_balance pone en 0 todo lote vencido, no se puede
--     restaurar en su fila: se crea una fila NUEVA con la fecha original (ya
--     pasada). Queda VISIBLE en el historial y nace muerta ⇒ no se farmea.
--  2. Reservas anteriores (creditos_lotes null): se usa el vencimiento MÁS
--     CORTO que le quede vivo al usuario. Son pocas (5 reservas).
--  3. Orden de consumo: FEFO (expires_at asc nulls last). Ya era así; se
--     preserva explícitamente en la versión detallada.
--
-- NO SE TOCÓ `estudio_cancelar_clase` (sigue dando 90 días nuevos): ahí
-- cancela el estudio y la usuaria es la perjudicada, así que darle tiempo
-- fresco es compensación, no un agujero. Y no lo puede provocar ella.
-- =====================================================================

-- PASO 1: la columna
alter table public.reservas add column if not exists creditos_lotes jsonb;
comment on column public.reservas.creditos_lotes is
  'De que lotes de creditos_movimientos salieron los creditos de esta reserva y cuantos de cada uno: [{"id":123,"taken":10},...]. Se llena al reservar y se usa al cancelar para devolver a los MISMOS lotes, sin renovar vencimientos. NULL en reservas anteriores al 2026-08-21.';

-- PASO 2: consumo que informa que lotes toco. FEFO: expires_at asc nulls last.
create or replace function public.consume_user_credits_detallado(
  p_user_id uuid, p_amount integer
) returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_needed int := p_amount; v_row record; v_take int; v_avail int;
  v_lotes jsonb := '[]'::jsonb;
begin
  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object('ok', false, 'error', 'monto_invalido');
  end if;
  perform public.refresh_user_credit_balance(p_user_id);
  select coalesce(sum(amount_remaining),0) into v_avail
    from public.creditos_movimientos
   where user_id = p_user_id and amount_remaining > 0
     and (expires_at is null or expires_at >= current_date);
  if v_avail < p_amount then
    return jsonb_build_object('ok', false, 'error', 'sin_creditos');
  end if;
  for v_row in
    select id, amount_remaining from public.creditos_movimientos
     where user_id = p_user_id and amount_remaining > 0
       and (expires_at is null or expires_at >= current_date)
     order by expires_at asc nulls last, created_at asc, id asc   -- FEFO
  loop
    exit when v_needed <= 0;
    v_take := least(v_row.amount_remaining, v_needed);
    update public.creditos_movimientos
       set amount_remaining = amount_remaining - v_take
     where id = v_row.id;
    v_lotes := v_lotes || jsonb_build_object('id', v_row.id, 'taken', v_take);
    v_needed := v_needed - v_take;
  end loop;
  perform public.refresh_user_credit_balance(p_user_id);
  return jsonb_build_object('ok', true, 'lotes', v_lotes);
end $fn$;

-- PASO 3a: reservar_clase
CREATE OR REPLACE FUNCTION public.reservar_clase(p_clase_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid          uuid := auth.uid();
  v_clase        record;
  v_estudio      record;
  v_creditos     int;
  v_cierre       int;
  v_ahora        timestamp := (
    now() at time zone 'America/Argentina/Buenos_Aires'
  );
  v_codigo_qr    text;
  v_res          jsonb;
  v_consumido    boolean;
  v_det          jsonb;
  v_lotes        jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'no_auth');
  end if;

  select * into v_clase from public.clases where id = p_clase_id;
  if v_clase is null then
    return jsonb_build_object('ok', false, 'error', 'clase_no_encontrada');
  end if;

  -- Ya tiene una reserva activa en esta clase.
  if exists (
    select 1 from public.reservas
     where clase_id = p_clase_id
       and usuario_id = v_uid
       and estado in ('confirmada', 'presente', 'pre_confirmada')
  ) then
    return jsonb_build_object('ok', false, 'error', 'ya_reservada');
  end if;

  select * into v_estudio from public.estudios where id = v_clase.estudio_id;

  -- Ventana de reserva: cascada clase -> estudio -> 0.
  v_cierre := coalesce(
    v_clase.reserva_cierre_minutos,
    v_estudio.reserva_cierre_minutos,
    0
  );
  if v_clase.fecha is not null
     and v_clase.fecha - make_interval(mins => v_cierre) <= v_ahora then
    return jsonb_build_object('ok', false, 'error', 'reserva_cerrada');
  end if;

  if coalesce(v_clase.lugares_disponibles, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error', 'sin_lugares');
  end if;

  -- El precio sale de la clase. Nunca del cliente.
  v_creditos := coalesce(v_clase.creditos, 0);

  -- Reserva gratuita: estudio en modo 'gestion' y el mail del usuario esta
  -- en su padron de alumnos directos. Antes esto lo decidia el cliente
  -- (reservaEsGratuita) y se mandaba `creditos_usados = 0`, asi que
  -- cualquiera podia declararse alumno directo y reservar gratis.
  if coalesce(v_estudio.modo, 'marketplace') = 'gestion' then
    if exists (
      select 1
        from public.estudio_alumnos ea
        join auth.users au on au.id = v_uid
       where ea.estudio_id = v_clase.estudio_id
         and lower(trim(ea.email)) = lower(trim(au.email))
         and ea.activo = true
    ) then
      v_creditos := 0;
    end if;
  end if;

  if v_creditos > 0 then
    -- Version DETALLADA: registra de que lotes salieron los creditos, para
    -- poder devolverlos a esos mismos al cancelar (sin renovar vencimientos).
    v_det := public.consume_user_credits_detallado(v_uid, v_creditos);
    if not coalesce((v_det->>'ok')::boolean, false) then
      return jsonb_build_object('ok', false, 'error', 'sin_creditos');
    end if;
    v_lotes := v_det->'lotes';
  end if;

  -- pgcrypto vive en el schema `extensions` y esta funcion corre con
  -- search_path=public, asi que digest() hay que calificarlo o tira
  -- 42883 "function digest(text, unknown) does not exist".
  v_codigo_qr := encode(
    extensions.digest(
      v_uid::text || '-' || p_clase_id::text || '-' || v_ahora::text,
      'sha256'),
    'hex'
  );
  v_codigo_qr := upper(substring(v_codigo_qr from 1 for 12));

  v_res := public.apply_reservation(
    v_uid, p_clase_id::integer, v_codigo_qr, v_creditos
  );

  -- Si apply_reservation fallo, devolvemos lo consumido. Al estar todo en
  -- la misma transaccion, esto no puede quedar a medias.
  if not coalesce((v_res->>'ok')::boolean, false) then
    -- Rollback EXACTO: cada lote recupera lo suyo, con su vencimiento original.
    -- Antes se compensaba con grant_user_credits(..., null, ...), que creaba
    -- creditos que NO VENCIAN NUNCA.
    if v_lotes is not null and jsonb_array_length(v_lotes) > 0 then
      update public.creditos_movimientos m
         set amount_remaining = m.amount_remaining + (l->>'taken')::int
        from jsonb_array_elements(v_lotes) l
       where m.id = (l->>'id')::bigint;
      perform public.refresh_user_credit_balance(v_uid);
    end if;
    return v_res;
  end if;

  -- Guardar de que lotes salieron, para la devolucion exacta al cancelar.
  if v_lotes is not null and jsonb_array_length(v_lotes) > 0 then
    update public.reservas set creditos_lotes = v_lotes
     where id = (v_res->'reserva'->>'id')::bigint;
  end if;

  return v_res;
end;
$function$
;

-- PASO 3b: confirm_pre_reserva
CREATE OR REPLACE FUNCTION public.confirm_pre_reserva(p_reserva_id integer, p_user_id uuid, p_creditos integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid       uuid := auth.uid();
  v_reserva   record;
  v_clase     record;
  v_estudio   record;
  v_creditos  int;
  v_consumido boolean;
  v_det       jsonb;
  v_lotes     jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'no_auth');
  end if;

  select * into v_reserva
    from public.reservas
   where id = p_reserva_id
     and usuario_id = v_uid
   for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'reserva_no_encontrada');
  end if;
  if v_reserva.estado <> 'pre_confirmada' then
    return jsonb_build_object('ok', false, 'error', 'estado_invalido');
  end if;
  if v_reserva.expires_at is not null and v_reserva.expires_at < now() then
    return jsonb_build_object('ok', false, 'error', 'expirada');
  end if;

  select * into v_clase from public.clases where id = v_reserva.clase_id;
  if v_clase is null then
    return jsonb_build_object('ok', false, 'error', 'clase_no_encontrada');
  end if;
  v_creditos := coalesce(v_clase.creditos, 0);

  select * into v_estudio from public.estudios where id = v_clase.estudio_id;
  if coalesce(v_estudio.modo, 'marketplace') = 'gestion' then
    if exists (
      select 1
        from public.estudio_alumnos ea
        join auth.users au on au.id = v_uid
       where ea.estudio_id = v_clase.estudio_id
         and lower(trim(ea.email)) = lower(trim(au.email))
         and ea.activo = true
    ) then
      v_creditos := 0;
    end if;
  end if;

  if v_creditos > 0 then
    v_det := public.consume_user_credits_detallado(v_uid, v_creditos);
    if not coalesce((v_det->>'ok')::boolean, false) then
      return jsonb_build_object('ok', false, 'error', 'sin_creditos');
    end if;
    v_lotes := v_det->'lotes';
  end if;

  update public.reservas
     set estado          = 'confirmada',
         expires_at      = null,
         creditos_usados = v_creditos,
         creditos_lotes  = v_lotes
   where id = p_reserva_id
   returning * into v_reserva;

  return jsonb_build_object('ok', true, 'reserva', row_to_json(v_reserva));

exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$function$
;

-- PASO 4: cancelar_mi_reserva
CREATE OR REPLACE FUNCTION public.cancelar_mi_reserva(p_codigo_qr text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid       uuid := auth.uid();
  v_reserva   record;
  v_clase     record;
  v_estudio   record;
  v_cierre    int;
  v_ahora     timestamp := (
    now() at time zone 'America/Argentina/Buenos_Aires'
  );
  v_creditos  int := 0;
  v_nombre    text;
  v_lote      record;
  v_exp       date;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'no_auth');
  end if;

  -- FOR UPDATE: serializa dos cancelaciones simultaneas de la misma reserva.
  select * into v_reserva
    from public.reservas
   where codigo_qr = p_codigo_qr
   for update;

  if v_reserva is null then
    return jsonb_build_object('ok', false, 'error', 'no_encontrada');
  end if;

  if v_reserva.usuario_id <> v_uid then
    return jsonb_build_object('ok', false, 'error', 'no_es_tuya');
  end if;

  -- Idempotencia: si ya no esta confirmada, no se devuelve nada de nuevo.
  if v_reserva.estado <> 'confirmada' then
    return jsonb_build_object(
      'ok', false,
      'error', 'estado_invalido',
      'estado', v_reserva.estado
    );
  end if;

  select * into v_clase from public.clases where id = v_reserva.clase_id;
  select * into v_estudio from public.estudios where id = v_clase.estudio_id;

  -- Ventana de cancelacion: cascada clase -> estudio -> 720 (12 hs).
  v_cierre := coalesce(
    v_clase.cancelacion_cierre_minutos,
    v_estudio.cancelacion_cierre_minutos,
    720
  );
  if v_clase.fecha is not null
     and v_clase.fecha - make_interval(mins => v_cierre) <= v_ahora then
    return jsonb_build_object(
      'ok', false,
      'error', 'fuera_de_ventana',
      'cierre_minutos', v_cierre
    );
  end if;

  v_creditos := coalesce(v_reserva.creditos_usados, 0);
  v_nombre := coalesce(v_clase.nombre, 'clase cancelada');

  update public.reservas
     set estado = 'cancelada'
   where id = v_reserva.id;

  -- Restaurar el cupo. Nunca por encima del total.
  update public.clases
     set lugares_disponibles = least(
           coalesce(lugares_disponibles, 0) + 1,
           coalesce(lugares_total, coalesce(lugares_disponibles, 0) + 1)
         )
   where id = v_reserva.clase_id;

  -- DEVOLUCION EXACTA. Antes se otorgaba un lote NUEVO con 60 dias desde la
  -- cancelacion, lo que permitia farmear: reservar + cancelar renovaba el
  -- vencimiento indefinidamente.
  if v_reserva.creditos_lotes is not null
     and jsonb_array_length(v_reserva.creditos_lotes) > 0 then

    -- Lotes VIVOS: se restauran en su propia fila, con su vencimiento original.
    update public.creditos_movimientos m
       set amount_remaining = m.amount_remaining + (l->>'taken')::int
      from jsonb_array_elements(v_reserva.creditos_lotes) l
     where m.id = (l->>'id')::bigint
       and (m.expires_at is null or m.expires_at >= current_date);

    -- Lotes VENCIDOS (decision A1): no se pueden restaurar en su fila porque
    -- refresh_user_credit_balance pone en 0 todo lote vencido. Se crea una fila
    -- nueva con la fecha ORIGINAL (ya pasada): queda VISIBLE en el historial y
    -- nace muerta, asi que no se farmea.
    for v_lote in
      select (l->>'id')::bigint as id, (l->>'taken')::int as taken
        from jsonb_array_elements(v_reserva.creditos_lotes) l
    loop
      select expires_at into v_exp
        from public.creditos_movimientos where id = v_lote.id;
      if v_exp is not null and v_exp < current_date then
        perform public.grant_user_credits(
          v_uid, v_lote.taken, 'devolucion_cancelacion',
          v_exp::text, 'Devolución (vencida) — ' || v_nombre);
      end if;
    end loop;

    perform public.refresh_user_credit_balance(v_uid);

  elsif v_creditos > 0 then
    -- Reserva ANTERIOR al registro de lotes (creditos_lotes null): se usa el
    -- vencimiento MAS CORTO que le quede vivo al usuario. Si no le queda
    -- ninguno, nace vencida (misma politica que A1).
    select min(expires_at) into v_exp
      from public.creditos_movimientos
     where user_id = v_uid and expires_at is not null
       and expires_at >= current_date;
    perform public.grant_user_credits(
      v_uid, v_creditos, 'devolucion_cancelacion',
      coalesce(v_exp, v_ahora::date)::text, 'Devolución — ' || v_nombre);
  end if;

  return jsonb_build_object(
    'ok', true,
    'creditos_devueltos', v_creditos,
    'clase_id', v_reserva.clase_id
  );
end;
$function$
;

-- =====================================================================
-- VERIFICACIÓN — 12 pruebas, con ROLLBACK, midiendo efecto
-- =====================================================================
-- Corrida del 2026-08-21 (post-aplicación, contra producción): 12/12.
--
--   1 lote que vence mañana: reservar+cancelar -> sigue venciendo mañana
--   2 loop de 3 vueltas                        -> el vencimiento NO se mueve
--   3 CASO 20->30 (el que rompía el parche):
--     lote corto vence ENTRE reserva y cancelación
--                                              -> hereda la fecha VENCIDA,
--                                                 no la del lote largo
--   4 consumo de 18 sobre lotes de 10 y 50     -> vuelven 10 y 50, exacto
--   5 devolución legítima                      -> el saldo vuelve a 40
--   6 reserva vieja sin creditos_lotes         -> usa el más corto (+7 días)
--   7 fuera de ventana                         -> fuera_de_ventana, nada devuelto
--   8 FEFO                                     -> consume primero el que vence antes
--   9 rollback_reserva: créditos eternos       -> 0 (antes creaba 1)
--  10 rollback_reserva: lote original          -> restaurado a 40 de 40
--  11 rollback_reserva: filas nuevas           -> 1 (solo el original)
--  12 rollback_reserva: el error al cliente    -> llega el código original
--
-- Las 1 y 3 demuestran que el agujero se cerró; la 5 garantiza que no se
-- rompió la devolución real al cerrarlo. Sin correr la suite ANTES del cambio
-- (donde 1 y 3 fallan), un "no ganó días" también sería el resultado de un
-- harness roto.
--
-- El suite completo está en el historial de la sesión; el fixture clave es el
-- de la prueba 3: crear un lote corto y uno largo, reservar (FEFO toma del
-- corto), forzar `update creditos_movimientos set expires_at = current_date-1`
-- sobre el corto, y recién ahí cancelar.
--
-- Reversión (NO recomendada: restaura los dos bugs):
--   en cancelar_mi_reserva, volver a grant_user_credits(..., v_ahora + 60 days)
--   en reservar_clase, volver a grant_user_credits(..., 'rollback_reserva', null)
--   drop function public.consume_user_credits_detallado(uuid, integer);
--   alter table public.reservas drop column creditos_lotes;

-- (fin)
