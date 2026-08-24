-- ============================================================================
-- AURA — Reparación de la tanda de guards del 20/8 (validada solo del lado
--        del exploit, nunca del uso legítimo)
-- ============================================================================
-- Aplicado a mano vía la Management API el 2026-08-24. Sin Dart ⇒ sin build.
--
-- CONTEXTO. `FIX_GUARDS_CUERPO.sql` (commit f4ba3dd, 20/8) agregó guards de
-- cuerpo a 5 funciones. `AUDITORIA_SEGURIDAD_2026-08-20.md` verificó de cada
-- una que el exploit quedara cerrado, pero NO que el usuario legítimo siguiera
-- pudiendo llamarla. Dos de las cinco quedaron rotas en producción, y la
-- verificación no lo vio porque se probó con test@aura.com, que es superadmin
-- y satisface `is_admin()`.
--
-- Lo que se arregla acá:
--   1. GUARD 4 — admin_list_studio_categories: rompía el panel de TODOS los
--      estudios (P0001 "No autorizado" al abrir o cargar clases).
--   2. estudio_cancelar_clase: error de tipos bigint→integer (42883). Roto
--      para todos, superadmin incluido. NO viene de la tanda del 20/8, pero
--      tapaba al punto 3.
--   3. GUARD 5 — refresh_user_credit_balance: volteaba la devolución de
--      créditos cuando el estudio cancelaba una clase.
--   4. GUARD 1 — notify_profes_nueva_reserva: la profe nunca se enteraba de
--      las reservas que entraban por lista de espera (el aviso no estaba
--      cableado; el guard además lo habría bloqueado).
--
-- MÉTODO: partiendo de `pg_get_functiondef` completo de cada función, con
-- reemplazos puntuales sobre el texto vivo (nunca retipeando cuerpos), y
-- preservando firma, RETURNS, volatilidad, SECURITY DEFINER y search_path.
-- Verificación de LAS DOS PUNTAS midiendo efecto — saldos, filas y estados
-- antes/después — nunca ausencia de error. Todas las pruebas en transacciones
-- con rollback; se confirmó que quedaron 0 filas de prueba.
--
-- CRITERIO DEL PUNTO 3, por qué así y no aflojando el guard:
-- `refresh_user_credit_balance` es una RPC pública, expuesta por PostgREST. Si
-- se le agregaba `or es_miembro_de_estudio(...)`, cualquier estudio podría
-- recalcular el saldo de cualquier usuaria llamándola directo. En vez de eso
-- el recálculo se mueve a `_refresh_user_credit_balance_interno`, sin guard
-- pero REVOCADA de anon/authenticated: solo la alcanzan los primitivos de
-- créditos, que son SECURITY DEFINER y ya validaron permisos por su cuenta
-- (estudio_cancelar_clase, por ejemplo, chequea estudio_admins antes). La RPC
-- pública conserva el guard del 20/8 intacto. Mismo patrón para el punto 4.
--
-- ============================================================================
-- BLOQUE A — GUARD 4: el panel del estudio vuelve a leer las categorías
-- ============================================================================
-- Antes: `if not public.is_admin() then raise exception 'No autorizado';`
-- El candado no protegía nada: `study_categories` ya tiene RLS SELECT
-- `using (true)`, la lista siempre fue pública. Queda solo el corte a anon.
-- Dos puntas medidas: anon/sin sesión → rechazado; las 15 cuentas de estudio
-- reales → 13 categorías cada una (antes: 15 de 15 rechazadas).

CREATE OR REPLACE FUNCTION public.admin_list_studio_categories()
 RETURNS TABLE(id bigint, nombre text, activa boolean, en_uso bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- 2026-08-24: el guard era `if not public.is_admin()`, agregado el 20/8 en
  -- FIX_GUARDS_CUERPO.sql (GUARD 4/5). Cerraba un exploit inexistente y rompia
  -- el panel del estudio: mis_clases_screen.dart llama esta RPC para llenar el
  -- selector de categorias, asi que TODO estudio no-superadmin veia
  -- "No autorizado" (P0001) al abrir o cargar clases. `study_categories` ya
  -- tiene RLS SELECT `using (true)`, o sea que la lista es publica de todos
  -- modos y el candado no protegia nada. Queda solo el corte a `anon`.
  -- `auth.uid()` va calificado: el esquema `auth` NO esta en el search_path.
  if auth.uid() is null then
    raise exception 'No autorizado';
  end if;

  return query
  select
    sc.id::bigint,
    sc.nombre::text,
    sc.activa::boolean,
    -- Cuantos estudios la tienen asignada: sirve para avisar antes de borrar.
    (select count(*)::bigint
       from public.estudios e
      where sc.nombre = any(e.categorias)) as en_uso
  from public.study_categories sc
  order by sc.activa desc, sc.nombre;
end;
$function$;

-- ============================================================================
-- BLOQUE B — puntos 2 y 3: la devolución de créditos del estudio
-- ============================================================================
-- Dos puntas medidas:
--   legítima  → el estudio cancela: ok, 1 reserva cancelada, 10 créditos
--               devueltos, saldo de la alumna 0→10, reserva en
--               'cancelada_por_estudio', 1 lote en creditos_movimientos.
--               (antes: 42883, nadie cobraba nada)
--   cerrada   → usuaria B pide el saldo de A → P0001 No autorizado;
--               el interno desde PostgREST → 42501 permission denied;
--               B sobre su propio saldo → pasa;
--               cancelar_mi_reserva de la propia alumna → ok, 10 devueltos.


create or replace function public._refresh_user_credit_balance_interno(p_user_id uuid)
returns integer language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_balance integer := 0;
  v_next_exp date;
begin
  update public.creditos_movimientos
     set amount_remaining = 0
   where user_id = p_user_id
     and expires_at is not null
     and expires_at < current_date
     and amount_remaining > 0;

  select
    coalesce(sum(amount_remaining), 0),
    min(expires_at) filter (
      where amount_remaining > 0
        and expires_at is not null
        and expires_at >= current_date
    )
  into v_balance, v_next_exp
  from public.creditos_movimientos
  where user_id = p_user_id
    and amount_remaining > 0;

  update public.usuarios
     set creditos = v_balance,
         creditos_vencimiento = v_next_exp
   where id = p_user_id;

  return v_balance;
end $fn$;
revoke all on function public._refresh_user_credit_balance_interno(uuid) from public, anon, authenticated;


create or replace function public.refresh_user_credit_balance(p_user_id uuid)
returns integer language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_uid uuid := auth.uid();
begin
  -- Guard del 2026-08-20 (GUARD 5/5), intacto: nadie toca un saldo ajeno desde
  -- afuera. Sin sesion (webhook MP / cron) pasa a proposito.
  if v_uid is not null
     and v_uid is distinct from p_user_id
     and not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  -- 2026-08-24: el recalculo se mudo a _refresh_user_credit_balance_interno.
  -- Los primitivos de creditos (grant/consume) llaman al interno: son
  -- SECURITY DEFINER que YA validaron permisos por su cuenta, y pasar por este
  -- guard rompia la devolucion cuando el estudio cancelaba una clase.
  return public._refresh_user_credit_balance_interno(p_user_id);
end $fn$;

CREATE OR REPLACE FUNCTION public.grant_user_credits(p_user_id uuid, p_amount integer, p_source text DEFAULT 'manual'::text, p_expires_at text DEFAULT NULL::text, p_description text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  declare
    v_expires_at timestamptz := null;
    v_meta       jsonb       := '{}'::jsonb;
  begin
    if p_user_id is null then
      raise exception 'grant_user_credits: p_user_id es null';
    end if;
    if p_amount is null or p_amount <= 0 then
      return;
    end if;
    if p_expires_at is not null and p_expires_at <> '' then
      v_expires_at := p_expires_at::timestamptz;
    end if;
    if p_description is not null and p_description <> '' then
      v_meta := jsonb_build_object('description', p_description);
    end if;
  
    insert into public.creditos_movimientos (
      user_id, source, amount_total, amount_remaining, expires_at, meta
    ) values (
      p_user_id,
      coalesce(nullif(p_source, ''), 'manual'),
      p_amount, p_amount, v_expires_at, v_meta
    );

    perform public._refresh_user_credit_balance_interno(p_user_id);
  end;
  $function$;

CREATE OR REPLACE FUNCTION public.consume_user_credits(p_user_id uuid, p_amount integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_needed integer;
  v_row record;
  v_available integer;
  v_take integer;
begin
  if p_amount is null or p_amount <= 0 then
    return false;
  end if;

  perform public._refresh_user_credit_balance_interno(p_user_id);

  select coalesce(sum(amount_remaining), 0)
    into v_available
  from public.creditos_movimientos
  where user_id = p_user_id
    and amount_remaining > 0
    and (expires_at is null or expires_at >= current_date);

  if v_available < p_amount then
    return false;
  end if;

  v_needed := p_amount;

  for v_row in
    select id, amount_remaining
    from public.creditos_movimientos
    where user_id = p_user_id
      and amount_remaining > 0
      and (expires_at is null or expires_at >= current_date)
    order by expires_at asc nulls last, created_at asc, id asc
  loop
    exit when v_needed <= 0;

    v_take := least(v_row.amount_remaining, v_needed);

    update public.creditos_movimientos
       set amount_remaining = amount_remaining - v_take
     where id = v_row.id;

    v_needed := v_needed - v_take;
  end loop;

  perform public._refresh_user_credit_balance_interno(p_user_id);
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION public.consume_user_credits_detallado(p_user_id uuid, p_amount integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_needed int := p_amount; v_row record; v_take int; v_avail int;
  v_lotes jsonb := '[]'::jsonb;
begin
  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object('ok', false, 'error', 'monto_invalido');
  end if;
  perform public._refresh_user_credit_balance_interno(p_user_id);
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
  perform public._refresh_user_credit_balance_interno(p_user_id);
  return jsonb_build_object('ok', true, 'lotes', v_lotes);
end $function$;

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

    v_afectados := v_afectados + 1;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'reservas_canceladas', v_afectados,
    'creditos_devueltos', v_creditos
  );
end;
$function$;


-- ============================================================================
-- BLOQUE C — punto 4: la profe se entera de la lista de espera
-- ============================================================================
-- `_waitlist_promote_interno` avisaba SOLO a la alumna promovida. El aviso a
-- la profe no estaba cableado (la función solo la nombraba en un comentario).
-- Va contra el interno porque en ese momento auth.uid() es quien canceló, no
-- el promovido, y el guard público habría devuelto 0. En bloque propio: si el
-- aviso falla, la promoción no se cae.
-- Dos puntas medidas:
--   legítima  → promoción por lista de espera: aviso_a_la_profe 0→1,
--               aviso_a_la_promovida sigue en 1;
--               reserva directa → sigue avisando 1.
--   cerrada   → B diciendo ser A en notify_profes_nueva_reserva → 0 avisos.


create or replace function public._notify_profes_nueva_reserva_interno(
  p_clase_id integer, p_reservante_id uuid)
returns integer language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_nombre     text;
  v_fecha      timestamp;
  v_estudio_id int;
  v_instructor text;
  v_reservante text;
  v_count      int := 0;
begin
  -- Sin guard de identidad: lo llaman funciones SECURITY DEFINER que ya
  -- validaron permisos. La verificacion de que la reserva EXISTE se conserva,
  -- ahora contra p_reservante_id (antes iba contra auth.uid()).
  if p_reservante_id is null then
    return 0;
  end if;

  if not exists (
    select 1 from public.reservas r
     where r.clase_id = p_clase_id
       and r.usuario_id = p_reservante_id
  ) then
    return 0;
  end if;

  select c.nombre, c.fecha::timestamp, c.estudio_id, c.instructor
    into v_nombre, v_fecha, v_estudio_id, v_instructor
    from public.clases c
   where c.id = p_clase_id;

  if not found or coalesce(trim(v_instructor), '') = '' then
    return 0;
  end if;

  select coalesce(nullif(trim(nombre), ''), 'Alguien')
    into v_reservante
    from public.usuarios
   where id = p_reservante_id;

  insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
  select u.id,
         'Nueva reserva 🧡',
         coalesce(v_reservante, 'Alguien') || ' se anotó en tu clase de ' ||
           coalesce(v_nombre, 'una clase') || ' el ' ||
           to_char(v_fecha, 'DD/MM') || ' a las ' || to_char(v_fecha, 'HH24:MI'),
         'reserva_profe',
         false
    from public.usuarios u
    join public.estudio_admins ea on ea.usuario_id = u.id
   where ea.estudio_id = v_estudio_id
     and ea.rol = 'profe'
     and lower(trim(u.nombre)) = lower(trim(v_instructor))
     and coalesce(u.notifs_reservas_profe, true) = true;

  get diagnostics v_count = row_count;
  return v_count;
end $fn$;
revoke all on function public._notify_profes_nueva_reserva_interno(integer, uuid) from public, anon, authenticated;


create or replace function public.notify_profes_nueva_reserva(
  p_clase_id integer, p_reservante_id uuid)
returns integer language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_uid uuid := auth.uid();
begin
  -- Guard del 2026-08-20 (GUARD 1/5), intacto: solo por TU propia reserva.
  -- Devuelve 0 en vez de raise para no romper el flujo de reservar del cliente.
  if v_uid is null or v_uid is distinct from p_reservante_id then
    return 0;
  end if;
  return public._notify_profes_nueva_reserva_interno(p_clase_id, p_reservante_id);
end $fn$;

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
$function$;

