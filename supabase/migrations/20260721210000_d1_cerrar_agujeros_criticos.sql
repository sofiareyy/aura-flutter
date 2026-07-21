-- ============================================================================
-- D1 — Cerrar los agujeros criticos de plata y permisos
-- ============================================================================
--
-- Confirmado en produccion:
--   * grant_user_credits y apply_reservation tienen EXECUTE para PUBLIC (y
--     por lo tanto para `anon`, cuya key esta en el bundle de la app), y no
--     validan auth.uid(). Cualquiera en internet podia acunarse creditos y
--     crear reservas sin descontarlos.
--   * La policy `usuarios_self_all` es cmd=ALL con `id = auth.uid()`, sin
--     restriccion de columnas: cualquiera se ponia rol='admin_estudio',
--     estudio_id=<ajeno> o creditos=999999.
--   * Las policies de `clases` incluyen `clases_*_own_studio`, basadas en
--     `usuarios.estudio_id` — que era auto-editable. Combinadas con lo
--     anterior, cualquier usuario podia borrar las clases de cualquier
--     estudio.
--   * `estudios` tiene DOS policies de UPDATE duplicadas, ninguna filtra rol:
--     una profe podia cambiar el CBU al que Aura liquida.
--
-- ESTRATEGIA
-- No se puede simplemente revocar: el cliente llama a esas funciones en el
-- camino de reserva y de cancelacion. Primero se crean RPC que validan
-- auth.uid() y encapsulan el flujo completo, y recien despues se cierran las
-- primitivas. Por eso este archivo y los cambios de Dart van juntos.
-- ============================================================================

-- ══════════════════════════════════════════════════════════════════════════
-- 1. Limpieza: overload sobrante de grant_user_credits
-- ══════════════════════════════════════════════════════════════════════════
-- El codigo llama con (p_user_id, p_amount, p_source, p_description,
-- p_expires_at) todos text -> resuelve a la firma (uuid,int,text,text,text).
-- La (uuid,int,text,date,jsonb) es un resto viejo que quedo vivo y puede
-- capturar llamadas por resolucion de overload.
drop function if exists public.grant_user_credits(uuid, integer, text, date, jsonb);


-- ══════════════════════════════════════════════════════════════════════════
-- 2. RPC: reservar una clase (reemplaza consume + apply desde el cliente)
-- ══════════════════════════════════════════════════════════════════════════
-- Ademas de validar el caller, corrige un agujero de plata: los creditos
-- SALEN DE LA CLASE, no de un parametro del cliente. Antes el cliente
-- mandaba `p_creditos_usados` y nada lo revalidaba.
create or replace function public.reservar_clase(p_clase_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
    v_consumido := public.consume_user_credits(v_uid, v_creditos);
    if not coalesce(v_consumido, false) then
      return jsonb_build_object('ok', false, 'error', 'sin_creditos');
    end if;
  end if;

  v_codigo_qr := encode(
    digest(v_uid::text || '-' || p_clase_id::text || '-' || v_ahora::text,
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
    if v_creditos > 0 then
      perform public.grant_user_credits(
        v_uid, v_creditos, 'rollback_reserva', null,
        'Devolucion por reserva fallida'
      );
    end if;
    return v_res;
  end if;

  return v_res;
end;
$$;

revoke execute on function public.reservar_clase(bigint) from public;
grant execute on function public.reservar_clase(bigint) to authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 3. RPC: cancelar MI reserva
-- ══════════════════════════════════════════════════════════════════════════
-- Corrige tres cosas que el flujo del cliente tenia mal:
--   a) No validaba quien cancelaba -> cualquiera cancelaba reservas ajenas.
--   b) No chequeaba el estado antes de devolver -> dos taps devolvian dos
--      veces los creditos.
--   c) No restauraba `lugares_disponibles` -> el cupo se perdia para siempre
--      si no habia lista de espera.
-- Ademas la ventana de cancelacion pasa a validarse server-side; antes la
-- guarda vivia solo en la UI.
create or replace function public.cancelar_mi_reserva(p_codigo_qr text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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

  if v_creditos > 0 then
    perform public.grant_user_credits(
      v_uid,
      v_creditos,
      'devolucion_cancelacion',
      (v_ahora + interval '60 days')::text,
      'Devolución — ' || v_nombre
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'creditos_devueltos', v_creditos,
    'clase_id', v_reserva.clase_id
  );
end;
$$;

revoke execute on function public.cancelar_mi_reserva(text) from public;
grant execute on function public.cancelar_mi_reserva(text) to authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 4. RPC: el estudio cancela una clase entera
-- ══════════════════════════════════════════════════════════════════════════
-- Antes era un loop en el cliente, no transaccional: si fallaba a la mitad,
-- unos usuarios quedaban con creditos devueltos y la reserva sin cancelar, y
-- reintentar devolvia dos veces.
create or replace function public.estudio_cancelar_clase(p_clase_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
        v_r.creditos_usados,
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
$$;

revoke execute on function public.estudio_cancelar_clase(bigint) from public;
grant execute on function public.estudio_cancelar_clase(bigint) to authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 5. CERRAR las primitivas
-- ══════════════════════════════════════════════════════════════════════════
-- Los RPC de arriba son `security definer`, corren como su owner, asi que
-- siguen pudiendo llamarlas. El cliente ya no.
revoke execute on function
  public.grant_user_credits(uuid, integer, text, text, text)
  from public, anon, authenticated;

revoke execute on function
  public.apply_reservation(uuid, integer, text, integer)
  from public, anon, authenticated;

revoke execute on function
  public.consume_user_credits(uuid, integer)
  from public, anon, authenticated;

-- El backoffice ajusta creditos por admin_adjust_user_credits, que sí valida
-- is_admin(); no necesita grant_user_credits directo.


-- ══════════════════════════════════════════════════════════════════════════
-- 6. Bloquear la auto-escalada en `usuarios`
-- ══════════════════════════════════════════════════════════════════════════
-- La policy es cmd=ALL con `id = auth.uid()`, sin restriccion de columnas.
-- Restringir por columna no se puede en una policy, asi que va por trigger:
-- rol, estudio_id, creditos y las columnas de empresa solo las cambian
-- funciones `security definer` (que corren como owner, no como el usuario).
create or replace function public.usuarios_bloquear_columnas_sensibles()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Los `security definer` corren con el rol del owner (postgres/supabase
  -- admin) y el service_role tampoco pasa por aca: solo frenamos al usuario
  -- final escribiendo su propia fila.
  if current_setting('role', true) not in ('authenticated', 'anon') then
    return new;
  end if;

  if new.rol is distinct from old.rol then
    raise exception 'No se puede cambiar el rol desde el cliente';
  end if;

  if new.estudio_id is distinct from old.estudio_id then
    raise exception 'No se puede cambiar el estudio desde el cliente';
  end if;

  if new.creditos is distinct from old.creditos then
    raise exception 'Los creditos se ajustan solo por el ledger';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_usuarios_columnas_sensibles on public.usuarios;
create trigger trg_usuarios_columnas_sensibles
  before update on public.usuarios
  for each row execute function public.usuarios_bloquear_columnas_sensibles();


-- ══════════════════════════════════════════════════════════════════════════
-- 7. Policies de `clases`: sacar las basadas en usuarios.estudio_id
-- ══════════════════════════════════════════════════════════════════════════
-- `clases_*_own_studio` confiaban en `usuarios.estudio_id`, que era
-- auto-editable: cualquiera se ponia el estudio ajeno y borraba sus clases.
-- Con el trigger del punto 6 ya no se puede, pero igual las sacamos: el
-- criterio correcto es `estudio_admins` + rol.
drop policy if exists clases_select_own_studio on public.clases;
drop policy if exists clases_insert_own_studio on public.clases;
drop policy if exists clases_update_own_studio on public.clases;
drop policy if exists clases_delete_own_studio on public.clases;

-- Lectura publica: es un marketplace, las clases se ven sin login.
drop policy if exists "todos pueden ver clases" on public.clases;

-- Escritura: solo admin del estudio. La profe queda afuera.
drop policy if exists "estudio inserta sus clases" on public.clases;
create policy "estudio inserta sus clases"
  on public.clases for insert
  to authenticated
  with check (
    exists (
      select 1 from public.estudio_admins ea
       where ea.estudio_id = clases.estudio_id
         and ea.usuario_id = auth.uid()
         and ea.rol in ('estudio', 'admin_estudio')
    )
  );

drop policy if exists "estudio actualiza sus clases" on public.clases;
create policy "estudio actualiza sus clases"
  on public.clases for update
  to authenticated
  using (
    exists (
      select 1 from public.estudio_admins ea
       where ea.estudio_id = clases.estudio_id
         and ea.usuario_id = auth.uid()
         and ea.rol in ('estudio', 'admin_estudio')
    )
  );

drop policy if exists "estudio elimina sus clases" on public.clases;
create policy "estudio elimina sus clases"
  on public.clases for delete
  to authenticated
  using (
    exists (
      select 1 from public.estudio_admins ea
       where ea.estudio_id = clases.estudio_id
         and ea.usuario_id = auth.uid()
         and ea.rol in ('estudio', 'admin_estudio')
    )
  );


-- ══════════════════════════════════════════════════════════════════════════
-- 8. Policies de `estudios`: sacar la duplicada y filtrar rol
-- ══════════════════════════════════════════════════════════════════════════
drop policy if exists "estudio admin actualiza estudio" on public.estudios;
drop policy if exists "Lectura publica estudios" on public.estudios;

drop policy if exists estudio_admin_actualiza_su_estudio on public.estudios;
create policy estudio_admin_actualiza_su_estudio
  on public.estudios for update
  to authenticated
  using (
    exists (
      select 1 from public.estudio_admins ea
       where ea.estudio_id = estudios.id
         and ea.usuario_id = auth.uid()
         and ea.rol in ('estudio', 'admin_estudio')
    )
  )
  with check (
    exists (
      select 1 from public.estudio_admins ea
       where ea.estudio_id = estudios.id
         and ea.usuario_id = auth.uid()
         and ea.rol in ('estudio', 'admin_estudio')
    )
  );

-- El estudio no toca su propia comision ni el pricing que define Aura.
-- El CBU sí lo edita (es su cuenta), pero solo un admin, no una profe.
create or replace function public.estudios_bloquear_columnas_aura()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('role', true) not in ('authenticated', 'anon') then
    return new;
  end if;

  if new.comision_aura is distinct from old.comision_aura
     or new.comision_workshop is distinct from old.comision_workshop
     or new.valor_credito is distinct from old.valor_credito
     or new.creditos_min is distinct from old.creditos_min
     or new.creditos_max is distinct from old.creditos_max
     or new.tipo_precio is distinct from old.tipo_precio
     or new.fecha_inicio_cobro is distinct from old.fecha_inicio_cobro then
    raise exception 'Comisiones y precios los define Aura desde el backoffice';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_estudios_columnas_aura on public.estudios;
create trigger trg_estudios_columnas_aura
  before update on public.estudios
  for each row execute function public.estudios_bloquear_columnas_aura();


-- ── VERIFICACION (correr aparte) ───────────────────────────────────────────
-- Ninguna de estas debe listar anon ni authenticated:
-- select p.oid::regprocedure::text, p.proacl
--   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--  where n.nspname='public'
--    and p.proname in ('grant_user_credits','apply_reservation',
--                      'consume_user_credits');
--
-- Estas tres SI deben tener authenticated:
-- select p.oid::regprocedure::text, p.proacl
--   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--  where n.nspname='public'
--    and p.proname in ('reservar_clase','cancelar_mi_reserva',
--                      'estudio_cancelar_clase');
--
-- select tablename, policyname, cmd from pg_policies
--  where schemaname='public' and tablename in ('clases','estudios')
--  order by tablename, cmd;
