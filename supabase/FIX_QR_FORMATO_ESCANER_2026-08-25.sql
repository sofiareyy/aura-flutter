-- ═══════════════════════════════════════════════════════════════════════════
-- FIX · el escaner del estudio rechazaba TODOS los QR reales
-- 2026-08-25 · reportado por Citra Barre (reserva 45DB492F6964)
--
-- EL BUG
-- El escaner valida el FORMATO del codigo antes de consultar la base
-- (asistencia_screen.dart:400, "QR strict" del 12/6):
--     ^AURA-[A-Z0-9]{8}-\d+-\d+-\d{4}$
-- Hasta el 21/7 el codigo lo generaba el cliente con ese formato. Ese dia se
-- mudo a la base (897c6cc, D1) para que el cliente no pudiera elegirlo, y
-- empezo a salir como 12 hex sueltos ("45DB492F6964"). Nadie actualizo el
-- regex, asi que desde entonces el escaner corta con "Este no es un QR de
-- Aura" y NUNCA llega a buscar la reserva.
--
-- Medido en toda la base:
--   AURA-... (pasa el escaner):  3 reservas, todas de junio, todas canceladas
--   12 hex   (lo rechaza):       2 reservas, del 19/8 y el 24/8
-- O sea: el escaner no pudo leer ninguna reserva real desde julio.
--
-- `_waitlist_promote_interno` SIEMPRE genero el formato correcto: esto alinea
-- `reservar_clase` con el. Es el unico lugar que quedaba desalineado.
--
-- Se arregla en la BASE y no en el regex del Dart a proposito: asi funciona
-- en las apps YA INSTALADAS, sin esperar un build.
--
-- ⚠️ EFECTO EN EL CODIGO VISIBLE (va a Tanda C, no rompe nada):
-- `reserva_confirmada_screen.dart:433` muestra `#BK-${codigoQr.split('-').last}`.
-- Con 12 hex sin guiones eso daba el codigo entero (#BK-45DB492F6964); con el
-- formato nuevo `.last` son los 4 digitos al azar (#BK-1234). Sigue sirviendo
-- para referenciar, pero es mas debil. Arreglo de una linea en el build:
-- usar el bloque hex, `split('-')[1]`.
--
-- Las 2 reservas viejas con 12 hex no se migran: una esta `completada` y la
-- otra `presente`, ninguna necesita escanearse. Cambiarles el codigo
-- invalidaria el QR que la alumna ya tiene guardado.
-- ═══════════════════════════════════════════════════════════════════════════

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
  -- 2026-08-25: el codigo TIENE que salir en el formato que el escaner del
  -- estudio valida ANTES de buscar nada (asistencia_screen.dart:400):
  --     ^AURA-[A-Z0-9]{8}-\d+-\d+-\d{4}$
  -- Hasta el 21/7 lo generaba el cliente con ese formato; ese dia el codigo
  -- se mudo a la base (commit 897c6cc, D1) y empezo a salir como 12 hex
  -- sueltos. Desde entonces el escaner rechaza TODA reserva real con
  -- "Este no es un QR de Aura" sin llegar a consultar la base.
  -- `_waitlist_promote_interno` nunca dejo de usar el formato correcto: esto
  -- lo alinea con el.
  -- El primer bloque sigue siendo el digest (no el uuid de la alumna, que es
  -- lo que usa waitlist): mantiene el codigo impredecible. La unicidad la dan
  -- el timestamp en ms y los 4 digitos al azar, ademas del indice unico.
  v_codigo_qr := 'AURA-' ||
                 upper(substring(
                   encode(
                     extensions.digest(
                       v_uid::text || '-' || p_clase_id::text || '-' || v_ahora::text,
                       'sha256'),
                     'hex')
                   from 1 for 8)) || '-' ||
                 p_clase_id::text || '-' ||
                 (extract(epoch from clock_timestamp()) * 1000)::bigint::text || '-' ||
                 lpad(floor(random() * 10000)::int::text, 4, '0');

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
