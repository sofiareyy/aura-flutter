-- ═══════════════════════════════════════════════════════════════════════════
-- FIX · "Cancelar clase" cancela la CLASE, no solo sus reservas
-- 2026-08-25 · reportado por la usuaria revisando el build: "toco cancelar
--              y no desaparece de Clases cargadas"
--
-- QUE PASABA
-- `estudio_cancelar_clase` devolvia los creditos, pasaba las reservas a
-- `cancelada_por_estudio` y avisaba a las alumnas -- pero `clases` no tenia
-- ninguna columna de estado y la funcion no tocaba la fila. La clase seguia
-- publicada en Explorar y RESERVABLE, y el panel la mostraba identica.
--
-- QUE HACE ESTO (opcion B, decidida por la usuaria; la A era borrarla, pero
-- `reservas.clase_id` es CASCADE y se perdia la historia de la alumna)
--   * `clases.cancelada boolean not null default false`
--   * `estudio_cancelar_clase` la marca, vacia su lista de espera y es
--     idempotente ('ya_cancelada')
--   * `reservar_clase` y `confirm_pre_reserva` la rechazan ('clase_cancelada')
--   * `_waitlist_promote_interno` no promueve sobre ella
--   * el generador NO cambia: la clase cancelada ocupa su minuto (segundo
--     chequeo por fecha), asi que no la recrea encima
--   * el candado de borrado no cambia: sus reservas quedan en
--     `cancelada_por_estudio`, que no esta protegido, asi que se puede borrar
--     despues si el estudio quiere
--
-- Lo visual (etiqueta CANCELADA en el panel, ocultarla en Explorar) es Dart y
-- va en el mismo build. Hasta entonces la clase sigue apareciendo en las
-- listas pero ya no se puede reservar.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.clases add column if not exists cancelada boolean not null default false;

CREATE OR REPLACE FUNCTION public.estudio_cancelar_clase(p_clase_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid       uuid := auth.uid();
  v_clase     record;
  v_r         record;
  v_afectados int := 0;
  v_creditos  int := 0;
  v_ahora     timestamp := (
    now() at time zone 'America/Argentina/Buenos_Aires'
  );
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'no_auth');
  end if;

  select * into v_clase from public.clases where id = p_clase_id;
  if v_clase is null then
    return jsonb_build_object('ok', false, 'error', 'clase_no_encontrada');
  end if;
  -- 2026-08-25: idempotente. Cancelar dos veces no vuelve a devolver nada.
  if v_clase.cancelada then
    return jsonb_build_object('ok', false, 'error', 'ya_cancelada');
  end if;

  -- Solo admin del estudio. Una profe no cancela clases.
  if not exists (
    select 1 from public.estudio_admins ea
     where ea.estudio_id = v_clase.estudio_id
       and ea.usuario_id = v_uid
       and ea.rol in ('estudio', 'admin_estudio')
  ) then
    return jsonb_build_object('ok', false, 'error', 'sin_permisos');
  end if;

  for v_r in
    select * from public.reservas
     where clase_id = p_clase_id
       and estado in ('confirmada', 'presente', 'pre_confirmada')
     for update
  loop
    if coalesce(v_r.creditos_usados, 0) > 0 then
      perform public.grant_user_credits(
        v_r.usuario_id,
        v_r.creditos_usados::int,   -- 2026-08-24: la columna es bigint y
                                    -- grant_user_credits toma integer (42883)
        'devolucion_clase_cancelada',
        (v_ahora + interval '90 days')::text,
        'Devolución por clase cancelada: ' || coalesce(v_clase.nombre, 'clase')
      );
      v_creditos := v_creditos + v_r.creditos_usados;
    end if;

    update public.reservas
       set estado = 'cancelada_por_estudio'
     where id = v_r.id;

    -- 2026-08-24: la campanita la crea la FUNCION, no el cliente.
    -- `reservas_service.dart:593` insertaba este aviso en notificaciones_usuario
    -- para OTRO usuario, y RLS lo negaba con 42501 (esa tabla solo tiene
    -- policies de SELECT y UPDATE, ninguna de INSERT). El error quedaba tragado
    -- por su `catch (_) {}`: a la alumna le devolvian los creditos y nunca se
    -- enteraba de que le habian cancelado la clase. Ninguna funcion de la base
    -- creaba este aviso — verificado: las unicas que escriben en esa tabla son
    -- _notify_profes_nueva_reserva_interno, _waitlist_promote_interno y
    -- enviar_aviso_estudio, y ninguna usa el tipo 'clase_cancelada'.
    -- Aca es SECURITY DEFINER, asi que saltea RLS. Mismo patron que el aviso a
    -- la profe. En bloque propio: si el aviso falla, la DEVOLUCION no se cae.
    begin
      insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
      values (
        v_r.usuario_id,
        '❌ Clase cancelada',
        'Se canceló "' || coalesce(v_clase.nombre, 'una clase') || '".' ||
          case when coalesce(v_r.creditos_usados, 0) > 0
               then ' Te devolvimos tus créditos.'
               else '' end,
        'clase_cancelada',
        false
      );
    exception when others then
      null;
    end;

    v_afectados := v_afectados + 1;
  end loop;

  -- 2026-08-25: la CLASE queda cancelada. Antes esta funcion devolvia los
  -- creditos y cancelaba las reservas pero no tocaba la fila de la clase: la
  -- clase seguia publicada y RESERVABLE, y el panel la mostraba igual
  -- (reportado por la usuaria el 25/8 revisando el build). Con la marca,
  -- `reservar_clase` y `confirm_pre_reserva` la rechazan, la lista de espera
  -- no promueve sobre ella, y el generador no la recrea (ocupa su minuto).
  update public.clases set cancelada = true where id = p_clase_id;

  -- Nadie mas puede entrar: la lista de espera de esa clase se vacia.
  delete from public.lista_espera where clase_id = p_clase_id;

  return jsonb_build_object(
    'ok', true,
    'reservas_canceladas', v_afectados,
    'creditos_devueltos', v_creditos
  );
end;
$function$
;

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
  -- 2026-08-25: una clase cancelada por el estudio no se reserva.
  if v_clase.cancelada then
    return jsonb_build_object('ok', false, 'error', 'clase_cancelada');
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
  -- 2026-08-25: una clase cancelada por el estudio no se confirma.
  if v_clase.cancelada then
    return jsonb_build_object('ok', false, 'error', 'clase_cancelada');
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

CREATE OR REPLACE FUNCTION public._waitlist_promote_interno(p_clase_id integer, p_count integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_wl_id          bigint;
  v_wl_usuario     text;          -- lista_espera.usuario_id es TEXT, no uuid
  v_codigo_qr      text;
  v_expires_at     timestamptz;
  v_reserva        record;
  v_promoted       jsonb := '[]'::jsonb;
  v_clase_nombre   text;
  v_estudio_nombre text;
  v_estudio_id     bigint;
  v_lugares_disp   int;
  v_lugares_total  int;
  v_remaining      int := coalesce(p_count, 1);
begin
  if p_clase_id is null then
    return jsonb_build_object('ok', false, 'error', 'clase_id_requerido');
  end if;

  -- BUG 1 ARREGLADO: el lock va sobre `clases` SOLA. Antes era
  -- `from clases c left join estudios e ... for update`, y Postgres tira
  -- "FOR UPDATE cannot be applied to the nullable side of an outer join".
  -- Ese error saltaba primero y hacía fallar toda la función.
  select c.lugares_disponibles, c.lugares_total, c.nombre, c.estudio_id
    into v_lugares_disp, v_lugares_total, v_clase_nombre, v_estudio_id
    from public.clases c
   where c.id = p_clase_id
     for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'clase_no_encontrada');
  end if;
  -- 2026-08-25: sobre una clase cancelada no se promueve a nadie.
  if exists (select 1 from public.clases where id = p_clase_id and cancelada) then
    return jsonb_build_object('ok', true, 'promoted', '[]'::jsonb, 'skipped', 'clase_cancelada');
  end if;

  -- El nombre del estudio, en un select aparte y SIN lock.
  select e.nombre into v_estudio_nombre
    from public.estudios e
   where e.id = v_estudio_id;

  while v_remaining > 0 loop
    if coalesce(v_lugares_disp, v_lugares_total, 0) <= 0 then
      exit;
    end if;

    -- BUG 2 ARREGLADO: el orden es por `created_at` (orden de llegada).
    -- `lista_espera` NUNCA tuvo columna `posicion`; el `order by posicion`
    -- anterior fallaba. `id` desempata para que el orden sea determinista.
    select le.id, le.usuario_id
      into v_wl_id, v_wl_usuario
      from public.lista_espera le
     where le.clase_id = p_clase_id
     order by le.created_at asc, le.id asc
     limit 1
     for update skip locked;

    if v_wl_id is null then
      exit;
    end if;

    v_codigo_qr := 'AURA-' ||
                   upper(substring(v_wl_usuario from 1 for 8)) || '-' ||
                   p_clase_id::text || '-' ||
                   (extract(epoch from now()) * 1000)::bigint::text || '-' ||
                   lpad(floor(random() * 10000)::int::text, 4, '0');
    v_expires_at := now() + interval '30 minutes';

    insert into public.reservas (
      usuario_id, clase_id, estado, creditos_usados, codigo_qr, expires_at
    ) values (
      v_wl_usuario::uuid, p_clase_id, 'pre_confirmada', 0, v_codigo_qr, v_expires_at
    )
    returning * into v_reserva;

    update public.clases
       set lugares_disponibles = coalesce(lugares_disponibles, lugares_total, 0) - 1
     where id = p_clase_id;
    v_lugares_disp := coalesce(v_lugares_disp, v_lugares_total, 0) - 1;

    -- BUGS 3 y 4 ARREGLADOS: se borra por `id`. Antes borraba por
    -- (clase_id, usuario_id) comparando TEXT = UUID -> no existe ese operador.
    -- Y se fue el `update lista_espera set posicion = posicion - 1`, que
    -- renumeraba una columna inexistente.
    delete from public.lista_espera where id = v_wl_id;

    -- A5: la campanita la crea la FUNCIÓN, no el cliente.
    -- El cliente insertaba en notificaciones_usuario con el usuario_id de OTRO
    -- y RLS lo denegaba (esa tabla solo tiene policies de SELECT y UPDATE);
    -- el error quedaba tragado por su try/catch. Resultado: el promovido no se
    -- enteraba de nada, teniendo 30 minutos para confirmar.
    -- Acá es security definer, así que saltea RLS (mismo patrón que
    -- notify_profes_nueva_reserva).
    -- OJO: esto es la campanita IN-APP. NO es un push al celular: eso necesita
    -- FCM/APNs, que el proyecto no tiene montado. El promovido lo ve al abrir.
    insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo)
    values (
      v_wl_usuario::uuid,
      '¡Se liberó un lugar! ⚡',
      'Tenés 30 minutos para confirmar tu lugar en ' ||
        coalesce(v_clase_nombre, 'una clase') || ' de ' ||
        coalesce(v_estudio_nombre, 'el estudio') || '.',
      'pre_confirmada'
    );

    -- 2026-08-24: la profe tambien se entera de las reservas que entran por
    -- lista de espera. Antes esto no existia: la promocion avisaba SOLO a la
    -- alumna promovida. Va contra el interno porque aca auth.uid() es quien
    -- cancelo (u otro estudio), no el promovido, y el guard publico daria 0.
    -- En su propio bloque: si el aviso falla, la promocion NO se cae.
    begin
      perform public._notify_profes_nueva_reserva_interno(
        p_clase_id, v_wl_usuario::uuid);
    exception when others then
      null;
    end;

    v_promoted := v_promoted || jsonb_build_object(
      'usuario_id',     v_wl_usuario,
      'reserva_id',     v_reserva.id,
      'codigo_qr',      v_codigo_qr,
      'expires_at',     v_expires_at,
      'clase_nombre',   v_clase_nombre,
      'estudio_nombre', v_estudio_nombre
    );

    v_remaining := v_remaining - 1;
  end loop;

  return jsonb_build_object('ok', true, 'promoted', v_promoted);

exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end
$function$
;

notify pgrst, 'reload schema';
