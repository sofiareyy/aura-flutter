-- AURA - Flujo de lista de espera con pre_confirmada (2026-06-16).
--
-- Idea: cuando hay un cupo (cancelacion o aumento por el estudio), en vez
-- de "abrir" el lugar para que cualquiera lo agarre, se lo asignamos al
-- siguiente de la lista_espera como reserva con estado 'pre_confirmada'
-- y expires_at = now() + 30 min. Si confirma antes de vencer, descuenta
-- creditos y pasa a 'confirmada'. Si no, se libera el lugar y pasa al
-- siguiente.
--
-- Schema:
--   reservas.expires_at timestamptz nullable -- solo se usa con
--     estado='pre_confirmada'. NULL si la reserva esta confirmada.
--
-- RPCs:
--   waitlist_promote_next(clase_id, count default 1)
--     - Promueve hasta `count` entries de lista_espera a pre_confirmadas.
--     - Decrementa lugares_disponibles por cada uno.
--     - Devuelve array de {usuario_id, reserva_id, codigo_qr, expires_at,
--       clase_nombre, estudio_nombre} para que el caller mande notifs.
--
--   confirm_pre_reserva(reserva_id, user_id, creditos)
--     - Valida estado='pre_confirmada' y no expirada.
--     - Descuenta creditos via consume_user_credits (con fallback a
--       update directo si la RPC no existe).
--     - Cambia estado a 'confirmada' y limpia expires_at.
--
--   release_pre_reserva(reserva_id)
--     - Elimina la reserva pre_confirmada.
--     - Restaura lugares_disponibles + 1.
--     - Promueve al siguiente de lista_espera (recursivo de 1).
--
--   cleanup_pre_reservas_expiradas(clase_id default null)
--     - Itera todas las pre_confirmadas con expires_at < now() y las
--       libera. Util como cron periodico o como pre-check antes de
--       cualquier operacion sobre la clase.


-- 1. Schema ---------------------------------------------------------------

alter table public.reservas
  add column if not exists expires_at timestamptz;

create index if not exists reservas_estado_expires_at_idx
  on public.reservas (estado, expires_at)
 where estado = 'pre_confirmada';


-- 2. RPC waitlist_promote_next -----------------------------------------

create or replace function public.waitlist_promote_next(
  p_clase_id integer,
  p_count    integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_user_id        uuid;
  v_posicion       int;
  v_codigo_qr      text;
  v_expires_at     timestamptz;
  v_reserva        record;
  v_promoted       jsonb := '[]'::jsonb;
  v_clase_nombre   text;
  v_estudio_nombre text;
  v_lugares_disp   int;
  v_lugares_total  int;
  v_remaining      int := coalesce(p_count, 1);
begin
  if p_clase_id is null then
    return jsonb_build_object('ok', false, 'error', 'clase_id_requerido');
  end if;

  -- Lock la clase y traer info para los notifs.
  select c.lugares_disponibles, c.lugares_total, c.nombre, e.nombre
    into v_lugares_disp, v_lugares_total, v_clase_nombre, v_estudio_nombre
    from public.clases c
    left join public.estudios e on e.id = c.estudio_id
   where c.id = p_clase_id
     for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'clase_no_encontrada');
  end if;

  while v_remaining > 0 loop
    -- Cortar si la clase no tiene mas lugares disponibles que dar.
    if coalesce(v_lugares_disp, v_lugares_total, 0) <= 0 then
      exit;
    end if;

    -- Proximo en lista_espera (orden estricto por posicion).
    select usuario_id, posicion
      into v_user_id, v_posicion
      from public.lista_espera
     where clase_id = p_clase_id
     order by posicion asc
     limit 1
     for update skip locked;

    if v_user_id is null then
      exit;
    end if;

    -- Generar codigo_qr en el mismo formato que el Dart.
    v_codigo_qr := 'AURA-' ||
                   upper(substring(v_user_id::text from 1 for 8)) || '-' ||
                   p_clase_id::text || '-' ||
                   (extract(epoch from now()) * 1000)::bigint::text || '-' ||
                   lpad(floor(random() * 10000)::int::text, 4, '0');
    v_expires_at := now() + interval '30 minutes';

    -- Insert pre_confirmada (creditos_usados = 0 hasta que confirme).
    insert into public.reservas (
      usuario_id, clase_id, estado, creditos_usados, codigo_qr, expires_at
    ) values (
      v_user_id, p_clase_id, 'pre_confirmada', 0, v_codigo_qr, v_expires_at
    )
    returning * into v_reserva;

    -- Decrementar lugares_disponibles.
    update public.clases
       set lugares_disponibles =
             coalesce(lugares_disponibles, lugares_total, 0) - 1
     where id = p_clase_id;
    v_lugares_disp := coalesce(v_lugares_disp, v_lugares_total, 0) - 1;

    -- Sacar de lista_espera + reordenar posiciones.
    delete from public.lista_espera
     where clase_id = p_clase_id
       and usuario_id = v_user_id;
    update public.lista_espera
       set posicion = posicion - 1
     where clase_id = p_clase_id
       and posicion > v_posicion;

    v_promoted := v_promoted || jsonb_build_object(
      'usuario_id',     v_user_id,
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
end;
$$;


-- 3. RPC confirm_pre_reserva ------------------------------------------

create or replace function public.confirm_pre_reserva(
  p_reserva_id integer,
  p_user_id    uuid,
  p_creditos   integer
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_reserva       record;
  v_user_creditos int;
begin
  select * into v_reserva
    from public.reservas
   where id = p_reserva_id
     and usuario_id = p_user_id
   for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'reserva_no_encontrada');
  end if;

  if v_reserva.estado <> 'pre_confirmada' then
    return jsonb_build_object('ok', false, 'error', 'estado_invalido');
  end if;

  if v_reserva.expires_at is not null
     and v_reserva.expires_at < now() then
    return jsonb_build_object('ok', false, 'error', 'expirada');
  end if;

  if coalesce(p_creditos, 0) > 0 then
    select creditos into v_user_creditos
      from public.usuarios
     where id = p_user_id
     for update;

    if coalesce(v_user_creditos, 0) < p_creditos then
      return jsonb_build_object('ok', false, 'error', 'sin_creditos');
    end if;

    -- Preferir consume_user_credits (mantiene el ledger / FIFO). Si no
    -- existe esa funcion en prod, fallback a update directo.
    begin
      perform public.consume_user_credits(p_user_id, p_creditos);
    exception when undefined_function then
      update public.usuarios
         set creditos = creditos - p_creditos
       where id = p_user_id;
    end;
  end if;

  update public.reservas
     set estado          = 'confirmada',
         expires_at      = null,
         creditos_usados = coalesce(p_creditos, 0)
   where id = p_reserva_id
   returning * into v_reserva;

  return jsonb_build_object('ok', true, 'reserva', row_to_json(v_reserva));

exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;


-- 4. RPC release_pre_reserva ------------------------------------------

create or replace function public.release_pre_reserva(
  p_reserva_id integer
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_reserva        record;
  v_promote_result jsonb;
begin
  select * into v_reserva
    from public.reservas
   where id = p_reserva_id
   for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'reserva_no_encontrada');
  end if;

  if v_reserva.estado <> 'pre_confirmada' then
    return jsonb_build_object('ok', false, 'error', 'estado_invalido');
  end if;

  -- Eliminar la pre_confirmada (no marcamos cancelada porque nunca cobro
  -- creditos -- mantenemos el historial limpio).
  delete from public.reservas where id = p_reserva_id;

  -- Restaurar lugar.
  update public.clases
     set lugares_disponibles = coalesce(lugares_disponibles, 0) + 1
   where id = v_reserva.clase_id;

  -- Promover al siguiente de lista_espera.
  v_promote_result := public.waitlist_promote_next(v_reserva.clase_id, 1);

  return jsonb_build_object(
    'ok',        true,
    'clase_id',  v_reserva.clase_id,
    'promoted',  v_promote_result
  );

exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;


-- 5. RPC cleanup_pre_reservas_expiradas ---------------------------------

create or replace function public.cleanup_pre_reservas_expiradas(
  p_clase_id integer default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_count int := 0;
  v_id    int;
begin
  for v_id in
    select id
      from public.reservas
     where estado = 'pre_confirmada'
       and expires_at < now()
       and (p_clase_id is null or clase_id = p_clase_id)
  loop
    perform public.release_pre_reserva(v_id);
    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('ok', true, 'released', v_count);
end;
$$;


-- 6. Permisos -------------------------------------------------------

grant execute on function public.waitlist_promote_next(integer, integer)
  to authenticated, service_role;
grant execute on function public.confirm_pre_reserva(integer, uuid, integer)
  to authenticated, service_role;
grant execute on function public.release_pre_reserva(integer)
  to authenticated, service_role;
grant execute on function public.cleanup_pre_reservas_expiradas(integer)
  to authenticated, service_role;


-- 7. Refrescar PostgREST.

notify pgrst, 'reload schema';


-- 8. Diagnostico ----------------------------------------------------

select routine_name
  from information_schema.routines
 where routine_schema = 'public'
   and routine_name in (
     'waitlist_promote_next',
     'confirm_pre_reserva',
     'release_pre_reserva',
     'cleanup_pre_reservas_expiradas'
   )
 order by routine_name;

select column_name, data_type, is_nullable
  from information_schema.columns
 where table_schema = 'public'
   and table_name   = 'reservas'
   and column_name  = 'expires_at';
