-- ============================================================================
-- AURA — Las devoluciones vuelven al lote original, con su vencimiento
-- ============================================================================
--
-- PROBLEMA
-- Cada devolución creaba un lote NUEVO con una fecha inventada, distinta en
-- cada camino:
--
--   rollback_reserva            null  → los créditos NUNCA vencían
--   devolucion_cancelacion      60 días
--   devolucion_clase_cancelada  90 días
--   eliminacion_cuenta          60 días
--
-- Ninguna respeta lo que la persona compró. Con Pack Prueba (30 días):
-- reservar y cancelar devolvía los créditos con 60 días. Repitiéndolo se
-- estiraban indefinidamente.
--
-- ARREGLO
-- Devolver los créditos AL LOTE DEL QUE SALIERON, con su vencimiento
-- original. Se vuelve exactamente al estado anterior a la reserva: ni se
-- gana ni se pierde.
--
-- POR QUÉ SE ENGANCHA EN grant_user_credits
-- Los 5 caminos de devolución la llaman (3 en SQL, 2 en delete-account, que
-- es TypeScript). Derivar acá los arregla a todos de una, sin reescribir
-- reservar_clase / cancelar_mi_reserva / estudio_cancelar_clase —tres
-- funciones largas donde un typo deja a la gente sin poder reservar— ni
-- redeployar la edge function.
--
-- Contrapartida, explícita: para los sources de devolución, el p_expires_at
-- que se le pasa deja de ser una orden y pasa a ser un PLAZO DE RESPALDO,
-- usado sólo si el lote original ya venció.


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 1. La función nueva                                                      │
-- └──────────────────────────────────────────────────────────────────────────┘

create or replace function public.restore_user_credits(
  p_user_id             uuid,
  p_amount              integer,
  p_source              text default 'devolucion',
  p_fallback_expires_at text default null,
  p_description         text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_pendiente  integer;
  v_row        record;
  v_devolver   integer;
  v_expires_at timestamptz;
  v_meta       jsonb := '{}'::jsonb;
begin
  if p_user_id is null then
    raise exception 'restore_user_credits: p_user_id es null';
  end if;
  if p_amount is null or p_amount <= 0 then
    return;
  end if;

  v_pendiente := p_amount;

  -- Rellenar los lotes vigentes que fueron consumidos, empezando por el que
  -- vence antes. Es el orden inverso exacto al de consume_user_credits
  -- (expires_at asc nulls last), así que deshace lo que se gastó.
  --
  -- El least() contra amount_total impide que un lote quede con más créditos
  -- de los que se acreditaron en su momento.
  for v_row in
    select id, amount_total, amount_remaining
      from public.creditos_movimientos
     where user_id = p_user_id
       and amount_remaining < amount_total
       and (expires_at is null or expires_at >= current_date)
     order by expires_at asc nulls last, created_at asc, id asc
     for update
  loop
    exit when v_pendiente <= 0;

    v_devolver := least(v_row.amount_total - v_row.amount_remaining, v_pendiente);

    update public.creditos_movimientos
       set amount_remaining = amount_remaining + v_devolver
     where id = v_row.id;

    v_pendiente := v_pendiente - v_devolver;
  end loop;

  -- Lo que no entró en ningún lote original es porque esos lotes ya
  -- vencieron. Ahí sí corresponde un lote nuevo: la persona reservó cuando
  -- sus créditos estaban vivos, no sería justo que pierda por cancelar.
  --
  -- Si no se pasó plazo de respaldo se usan 60 días. Nunca null: un crédito
  -- que no vence nunca es justamente lo que este arreglo viene a eliminar.
  if v_pendiente > 0 then
    if p_fallback_expires_at is not null and p_fallback_expires_at <> '' then
      v_expires_at := p_fallback_expires_at::timestamptz;
    else
      v_expires_at := (current_date + 60)::timestamptz;
    end if;

    if p_description is not null and p_description <> '' then
      v_meta := jsonb_build_object('description', p_description);
    end if;
    v_meta := v_meta || jsonb_build_object('lote_original_vencido', true);

    insert into public.creditos_movimientos (
      user_id, source, amount_total, amount_remaining, expires_at, meta
    ) values (
      p_user_id,
      coalesce(nullif(p_source, ''), 'devolucion'),
      v_pendiente, v_pendiente, v_expires_at, v_meta
    );
  end if;

  perform public.refresh_user_credit_balance(p_user_id);
end;
$function$;

-- Mismos permisos que grant_user_credits y consume_user_credits (D1 revocó
-- PUBLIC; sólo postgres como dueño y service_role).
revoke all on function public.restore_user_credits(uuid, integer, text, text, text) from public;
revoke all on function public.restore_user_credits(uuid, integer, text, text, text) from anon, authenticated;
grant execute on function public.restore_user_credits(uuid, integer, text, text, text) to service_role;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 2. grant_user_credits deriva cuando el source es una devolución          │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Idéntica a la actual salvo el bloque nuevo del principio.

create or replace function public.grant_user_credits(
  p_user_id     uuid,
  p_amount      integer,
  p_source      text default 'manual'::text,
  p_expires_at  text default null::text,
  p_description text default null::text
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_expires_at timestamptz := null;
  v_meta       jsonb       := '{}'::jsonb;
  v_source     text        := coalesce(nullif(p_source, ''), 'manual');
begin
  if p_user_id is null then
    raise exception 'grant_user_credits: p_user_id es null';
  end if;
  if p_amount is null or p_amount <= 0 then
    return;
  end if;

  -- Devoluciones: no se crea un lote nuevo, se rellenan los originales para
  -- que conserven su vencimiento. Ver restore_user_credits.
  -- Acá p_expires_at es plazo de respaldo, no una orden.
  if v_source in (
       'rollback_reserva',
       'devolucion_cancelacion',
       'devolucion_clase_cancelada',
       'eliminacion_cuenta'
     ) then
    perform public.restore_user_credits(
      p_user_id, p_amount, v_source, p_expires_at, p_description
    );
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
    v_source,
    p_amount, p_amount, v_expires_at, v_meta
  );

  perform public.refresh_user_credit_balance(p_user_id);
end;
$function$;

revoke all on function public.grant_user_credits(uuid, integer, text, text, text) from public;
revoke all on function public.grant_user_credits(uuid, integer, text, text, text) from anon, authenticated;
grant execute on function public.grant_user_credits(uuid, integer, text, text, text) to service_role;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 3. Verificación — correr DESPUÉS, es solo lectura                        │
-- └──────────────────────────────────────────────────────────────────────────┘
--
-- 3A. Que las dos funciones queden con los permisos correctos:
--
-- select p.proname, p.prosecdef as security_definer,
--        array_to_string(p.proacl, ' | ') as permisos
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'public'
--    and p.proname in ('grant_user_credits','restore_user_credits',
--                      'consume_user_credits')
--  order by p.proname;
--
-- Las tres tienen que decir: postgres=X/postgres | service_role=X/postgres
--
--
-- 3B. Que ningún saldo se haya movido con esta migración (no toca datos):
--
-- select u.email, u.creditos as saldo,
--        coalesce(sum(m.amount_remaining) filter (
--          where m.expires_at is null or m.expires_at >= current_date), 0) as ledger
--   from public.usuarios u
--   left join public.creditos_movimientos m on m.user_id = u.id
--  group by u.id, u.email, u.creditos
-- having u.creditos <> 0
--  order by u.email;
