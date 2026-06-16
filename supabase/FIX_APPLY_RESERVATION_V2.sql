-- AURA - apply_reservation V2 (2026-06-16, hotfix mismo dia)
--
-- HOTFIX 2026-06-16: la primera version de la V2 referenciaba
-- clases.estado pero esa columna NO existe en produccion. Causaba el
-- "error generico" al reservar (la RPC tiraba 'column "estado" does
-- not exist' y caia en el exception handler). Sacado el lookup y el
-- check de estado. Si una clase fue cancelada en el panel del estudio
-- el flujo actual la elimina via eliminarClaseRow o le pone
-- lugares_disponibles=0; en ambos casos la RPC corta correctamente.
--
-- Fixes sobre la V1 (FIX_APPLY_RESERVATION.sql):
--
-- 1) Manejo robusto de NULL en clases.lugares_disponibles. La V1 hacia
--    `coalesce(v_lugares_disp, 0) <= 0` -> si la columna estaba NULL
--    (clases creadas a mano o por una version vieja de
--    generar_clases_estudio que no la seteaba), siempre cortaba con
--    'sin_lugares' aunque hubiera lugares reales segun lugares_total.
--    Ahora hace coalesce con lugares_total como fallback, igual que el
--    pre-check de Dart.
--
-- 2) Distinguir unique_violation entre:
--      - codigo_qr (re-generar y reintentar es lo correcto)
--      - reservas_usuario_clase_unique (si existe en prod): el usuario
--        ya tiene una reserva activa para esta clase -> error mas claro.
--    Tambien chequeamos explicitamente al principio para no descontar
--    creditos en vano cuando ya existe la reserva.
--
-- 3) NOTIFY pgrst, 'reload schema' al final para que PostgREST refresque
--    el schema cache. Sin esto, una funcion recien creada puede dar
--    "function not found" al primer request.
--
-- Tambien actualiza el UPDATE para defenderse del NULL: si lugares_disp
-- esta en NULL pero lugares_total > 0, lo setea a lugares_total - 1 (el
-- valor coherente para "primera reserva sobre clase sin contador").


-- 1. Drop la V1 explicitamente. Idempotente si no existe.

drop function if exists public.apply_reservation(uuid, integer, text, integer);


-- 2. Recrear con los fixes.

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
  v_lugares_disp   int;
  v_lugares_total  int;
  v_existe_reserva boolean;
  v_reserva        record;
begin
  if p_user_id is null or p_clase_id is null then
    return jsonb_build_object('ok', false, 'error', 'parametros_invalidos');
  end if;

  if p_codigo_qr is null or length(trim(p_codigo_qr)) = 0 then
    return jsonb_build_object('ok', false, 'error', 'codigo_qr_invalido');
  end if;

  -- 1) Lock de la fila de clases (serializa concurrencia).
  -- NOTA: la tabla public.clases en produccion NO tiene columna `estado`.
  -- El borrado de una clase cancelada se hace via DELETE desde el panel
  -- del estudio (eliminarClaseRow), no por update de estado. Por eso aca
  -- no chequeamos ningun campo "cancelada".
  select lugares_disponibles, lugares_total
    into v_lugares_disp, v_lugares_total
    from public.clases
   where id = p_clase_id
   for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'clase_no_encontrada');
  end if;

  -- 2) Pre-check: el usuario ya tiene reserva activa en esta clase?
  select exists (
    select 1
      from public.reservas
     where clase_id = p_clase_id
       and usuario_id = p_user_id
       and estado not in ('cancelada', 'cancelada_por_estudio')
  ) into v_existe_reserva;

  if v_existe_reserva then
    return jsonb_build_object('ok', false, 'error', 'ya_reservaste');
  end if;

  -- 3) Check lugares. NULL en lugares_disp -> fallback a lugares_total.
  --    Si total es NULL o 0, cortamos con sin_lugares (clase sin cupos).
  if coalesce(v_lugares_disp, v_lugares_total, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error', 'sin_lugares');
  end if;

  -- 4) Insert reserva.
  insert into public.reservas (
    usuario_id, clase_id, estado, creditos_usados, codigo_qr
  ) values (
    p_user_id, p_clase_id, 'confirmada',
    coalesce(p_creditos_usados, 0), p_codigo_qr
  )
  returning * into v_reserva;

  -- 5) Decrementar lugares. Si estaba en NULL, lo sembramos desde
  --    lugares_total - 1 (coherente con "esta es la primera reserva").
  update public.clases
     set lugares_disponibles =
           coalesce(lugares_disponibles, lugares_total, 0) - 1
   where id = p_clase_id;

  return jsonb_build_object(
    'ok', true,
    'reserva', row_to_json(v_reserva)
  );

exception when unique_violation then
  -- Distinguir: si el conflicto es por codigo_qr el cliente puede
  -- regenerar y reintentar. Si es por la constraint (clase_id,
  -- usuario_id) -- nombre tipico reservas_usuario_clase_unique o
  -- similar -- el usuario ya tiene reserva.
  if sqlerrm ilike '%codigo_qr%' then
    return jsonb_build_object('ok', false, 'error', 'codigo_qr_duplicado');
  end if;
  return jsonb_build_object('ok', false, 'error', 'ya_reservaste');

when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;


-- 3. Permisos.
grant execute on function public.apply_reservation(
  uuid, integer, text, integer
) to authenticated;
grant execute on function public.apply_reservation(
  uuid, integer, text, integer
) to service_role;


-- 4. Refrescar schema cache de PostgREST.
notify pgrst, 'reload schema';


-- 5. Diagnostico ---------------------------------------------------------

-- 5a. Confirmar que apply_reservation existe con la firma correcta.
select routine_name, data_type
  from information_schema.routines
 where routine_schema = 'public'
   and routine_name = 'apply_reservation';

select parameter_name, data_type, parameter_default, ordinal_position
  from information_schema.parameters
 where specific_schema = 'public'
   and specific_name like 'apply_reservation%'
 order by ordinal_position;

-- 5b. Clases proximas de Hot Clic. Sin clases.estado porque no existe.
select id, nombre, fecha, lugares_total, lugares_disponibles,
       horario_fijo_id
  from public.clases
 where estudio_id = (select id from public.estudios where nombre = 'Hot Clic')
   and fecha >= now()
 order by fecha asc
 limit 10;

-- 5c. Constraints sobre reservas (para saber si hay unique por
--     clase_id+usuario_id en prod).
select conname, contype, pg_get_constraintdef(oid) as definition
  from pg_constraint
 where conrelid = 'public.reservas'::regclass
 order by conname;
