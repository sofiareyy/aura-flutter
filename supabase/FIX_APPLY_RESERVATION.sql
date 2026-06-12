-- AURA - RPC apply_reservation atomica (2026-06-12).
--
-- Bug que resuelve: race condition en el ultimo lugar. El flujo viejo era
-- en 3 pasos separados desde el cliente:
--   1) SELECT clases.lugares_disponibles
--   2) INSERT en reservas
--   3) RPC decrementar_lugares
-- Dos usuarios que tocaban "reservar" exactamente a la vez veian
-- lugares=1, ambos pasaban el guard, ambos insertaban una reserva, y la
-- clase quedaba over-bookeada.
--
-- Esta RPC hace todo dentro de una sola funcion plpgsql, agarrando un
-- SELECT ... FOR UPDATE sobre la fila de clases que serializa cualquier
-- concurrencia. Si el primer caller decrementa de 1 a 0, el segundo caller
-- queda bloqueado hasta que el primero termine y ve lugares=0 -> error
-- 'sin_lugares' -> ninguna reserva insertada.
--
-- El descuento de creditos se sigue manejando desde el cliente (con
-- rollback en Dart si la RPC devuelve error). Asi evitamos duplicar la
-- logica del ledger (consume_user_credits, refresh_user_credit_balance,
-- expires_at FIFO) dentro de esta funcion.


create or replace function public.apply_reservation(
  p_user_id          uuid,
  p_clase_id         integer,
  p_codigo_qr        text,
  p_creditos_usados  integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_lugares_disp int;
  v_clase_estado text;
  v_reserva      record;
begin
  if p_user_id is null or p_clase_id is null then
    return jsonb_build_object('ok', false, 'error', 'parametros_invalidos');
  end if;

  if p_codigo_qr is null or length(trim(p_codigo_qr)) = 0 then
    return jsonb_build_object('ok', false, 'error', 'codigo_qr_invalido');
  end if;

  -- 1) Lock la fila de clases. Cualquier otra session que llame esta
  --    funcion para la misma clase queda esperando hasta que terminemos
  --    nuestra transaccion. Eso garantiza el check+decrement atomico.
  select lugares_disponibles, estado
    into v_lugares_disp, v_clase_estado
    from public.clases
   where id = p_clase_id
   for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'clase_no_encontrada');
  end if;

  if v_clase_estado = 'cancelada' then
    return jsonb_build_object('ok', false, 'error', 'clase_cancelada');
  end if;

  -- 2) Check lugares. Si quedan 0 cortamos sin tocar nada.
  if coalesce(v_lugares_disp, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error', 'sin_lugares');
  end if;

  -- 3) Insert reserva. Atomicamente dentro del lock.
  insert into public.reservas (
    usuario_id,
    clase_id,
    estado,
    creditos_usados,
    codigo_qr
  ) values (
    p_user_id,
    p_clase_id,
    'confirmada',
    coalesce(p_creditos_usados, 0),
    p_codigo_qr
  )
  returning * into v_reserva;

  -- 4) Decrementar lugares.
  update public.clases
     set lugares_disponibles = lugares_disponibles - 1
   where id = p_clase_id;

  return jsonb_build_object(
    'ok', true,
    'reserva', row_to_json(v_reserva)
  );

exception when unique_violation then
  -- codigo_qr ya existe (improbable: 4-digit random + ts) -> el cliente
  -- regenera con otro random y reintenta.
  return jsonb_build_object('ok', false, 'error', 'codigo_qr_duplicado');
when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;


-- Permisos
grant execute on function public.apply_reservation(
  uuid, integer, text, integer
) to authenticated;
grant execute on function public.apply_reservation(
  uuid, integer, text, integer
) to service_role;


-- Verificacion
select routine_name, data_type
  from information_schema.routines
 where routine_schema = 'public'
   and routine_name = 'apply_reservation';

select parameter_name, data_type, parameter_default, ordinal_position
  from information_schema.parameters
 where specific_schema = 'public'
   and specific_name like 'apply_reservation%'
 order by ordinal_position;


-- Smoke test (descomentar y reemplazar con datos reales para probar):
-- select public.apply_reservation(
--   '00000000-0000-0000-0000-000000000000'::uuid,  -- p_user_id
--   305,                                            -- p_clase_id
--   'AURA-TEST1234-305-' || extract(epoch from now())::bigint || '-9999',
--   12                                              -- p_creditos_usados
-- );
