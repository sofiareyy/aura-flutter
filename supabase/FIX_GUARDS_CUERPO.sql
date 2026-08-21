-- ============================================================================
-- AURA — Guards de cuerpo de las 🟡 (la capa que faltaba)
-- ============================================================================
-- Aplicado a mano vía la Management API el 2026-08-20.
-- La tanda anterior (FIX_AMARILLAS_AUDITORIA.sql) cortó a `anon` por grants.
-- Esta cierra el riesgo residual: una usuaria AUTENTICADA abusando.
--
-- Método, después de casi perder un default en admin_upsert_pricing_pack:
-- de a una, con pg_get_functiondef completo a la vista, preservando firma,
-- defaults, RETURNS, SECURITY DEFINER y search_path; solo se agrega el guard.
-- Verificación de las dos puntas MIDIENDO EFECTO (filas/saldos antes y
-- después), nunca ausencia de error.
-- Sin Dart ⇒ sin build ni deploy.
-- ============================================================================

-- GUARD 1/5: notify_profes_nueva_reserva
-- Antes: cualquiera podía disparar avisos a las profes de CUALQUIER clase, y
-- suplantar a otro usuario como "reservante" en el texto del mensaje (spam).
-- Ahora: solo por tu propia reserva, y solo si realmente tenés una en esa clase.
-- Devuelve 0 (no raise) para no romper el flujo de reservar del cliente, que la
-- llama fire-and-forget justo después de reservar_clase.
-- Firma, cuerpo y search_path idénticos al original; solo se agrega el guard.
create or replace function public.notify_profes_nueva_reserva(
  p_clase_id integer,
  p_reservante_id uuid)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid        uuid := auth.uid();
  v_nombre     text;
  v_fecha      timestamp;
  v_estudio_id int;
  v_instructor text;
  v_reservante text;
  v_count      int := 0;
begin
  -- Solo por TU propia reserva...
  if v_uid is null or v_uid is distinct from p_reservante_id then
    return 0;
  end if;
  -- ...y solo si efectivamente reservaste esa clase.
  if not exists (
    select 1 from public.reservas r
     where r.clase_id = p_clase_id
       and r.usuario_id = v_uid
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
end;
$function$;

-- ── GUARD 2/5: ensure_referral_code ────────────────────────────────────────
-- Antes: cualquiera podía generarle el código de referido a otro usuario.
-- Ahora: solo el propio. Raise (no null) porque referidos_service.dart:9 la
-- envuelve en try/catch y tiene fallback.
-- NOTA: la original NO tiene `SET search_path`. Se preserva tal cual para que
-- este cambio sea solo el guard; queda anotado como hardening aparte.
create or replace function public.ensure_referral_code(p_user_id uuid)
returns text
language plpgsql
security definer
as $function$
  declare
    v_code text;
  begin
    if auth.uid() is null or auth.uid() is distinct from p_user_id then
      raise exception 'No autorizado';
    end if;

    select codigo_referido into v_code
      from usuarios
     where id = p_user_id;

    if v_code is null or v_code = '' then
      v_code :=
  upper(substring(replace(p_user_id::text, '-', ''),
  1, 6)
                || to_char(floor(random() *
  9999)::int, 'FM0000'));
      update usuarios set codigo_referido = v_code
  where id = p_user_id;
    end if;

    return v_code;
  end;
  $function$;


-- ── GUARD 3/5: avisos_generales_restantes ──────────────────────────────────
-- Antes: cualquiera consultaba la cuota mensual de avisos de cualquier estudio.
-- Ahora: solo el estudio dueño o un admin de Aura.
-- Llamador legítimo: aviso_alumnos_service.dart:65 (panel de estudio).
create or replace function public.avisos_generales_restantes(p_estudio_id integer)
returns json
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_max   int;
  v_usados int;
  v_inicio timestamptz := date_trunc(
    'month',
    (now() at time zone 'America/Argentina/Buenos_Aires')
  ) at time zone 'America/Argentina/Buenos_Aires';
begin
  if not (public.is_admin() or public.es_miembro_de_estudio(p_estudio_id::bigint)) then
    raise exception 'No autorizado';
  end if;

  select coalesce(nullif(valor, '')::int, 3)
    into v_max
    from public.configuracion_global
   where clave = 'avisos_generales_max_mes';

  v_max := coalesce(v_max, 3);

  select count(*)
    into v_usados
    from public.avisos_envios
   where estudio_id = p_estudio_id
     and tipo = 'aviso_general'
     and created_at >= v_inicio;

  return json_build_object(
    'max', v_max,
    'usados', v_usados,
    'restantes', greatest(v_max - v_usados, 0),
    -- Primer dia del mes siguiente, para el mensaje de bloqueo.
    'reinicia', to_char(
      (date_trunc('month', (now() at time zone 'America/Argentina/Buenos_Aires'))
        + interval '1 month')::date,
      'DD/MM/YYYY'
    )
  );
end;
$function$;


-- ── GUARD 4/5: admin_list_studio_categories ────────────────────────────────
-- Se llamaba admin_* y no validaba nada. Llamador: admin_service.dart:397 y :452.
-- Pasa de LANGUAGE sql a plpgsql para poder hacer el raise (en SQL plano no se
-- puede). El RETURNS TABLE queda IDÉNTICO.
-- OJO con la trampa de admin_list_studios: `return query` en plpgsql es
-- ESTRICTO con los tipos. Casts explícitos para no repetir el 42804.
create or replace function public.admin_list_studio_categories()
returns table(id bigint, nombre text, activa boolean, en_uso bigint)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_admin() then
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

-- ── GUARD 5/5: refresh_user_credit_balance ─────────────────────────────────
-- Antes: cualquiera (anon incluido) recalculaba el saldo de cualquier usuario.
-- No mintea (solo recalcula desde el ledger), pero no debe ser publica.
--
-- EL GUARD VA AL REVES a proposito: bloquea SOLO si HAY sesion y el uid no
-- coincide. Si auth.uid() es NULL, DEJA PASAR.
--
--   Si exigieramos `auth.uid() is not null` romperiamos LA ACREDITACION DE
--   PAGOS: el webhook de Mercado Pago llega como service_role SIN uid, y
--   grant_user_credits llama a esta funcion por dentro para refrescar el saldo.
--
-- Los 4 caminos:
--   1) uid NULL          -> contexto de servicio (webhook MP, crons)     PASA
--   2) uid = p_user_id   -> la usuaria refresca su propio saldo          PASA
--   3) is_admin()        -> backoffice (admin_adjust_user_credits)       PASA
--   4) uid <> p_user_id  -> sesion activa tocando saldo AJENO         BLOQUEA
--
-- anon ya no tiene EXECUTE (revocado antes), asi que "sin uid" solo puede
-- venir de service_role o de una llamada interna.
--
-- Firma, RETURNS, SECURITY DEFINER, search_path y cuerpo: identicos al original.
create or replace function public.refresh_user_credit_balance(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid     uuid := auth.uid();
  v_balance integer := 0;
  v_next_exp date;
begin
  if v_uid is not null
     and v_uid is distinct from p_user_id
     and not public.is_admin() then
    raise exception 'No autorizado';
  end if;

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
end;
$function$;
