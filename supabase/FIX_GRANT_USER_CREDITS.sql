-- AURA - Crear public.grant_user_credits (2026-06-12).
--
-- BUG: al aplicar un codigo de referido la RPC apply_referral_code falla
-- con "function grant_user_credits does not exist". apply_referral_code
-- esta definida en EJECUTAR_EN_SUPABASE.sql y hace `perform
-- grant_user_credits(...)`, pero la funcion grant_user_credits nunca se
-- creo en el SQL versionado (suponemos que se hizo a mano en producccion
-- y se perdio). Multiples llamadores tambien la usan:
--
--   * supabase/functions/mp-webhook/index.ts  (acreditacion pack/plan)
--   * supabase/functions/confirmar-pago-manual/index.ts
--   * lib/services/usuarios_service.dart  (agregarCreditos)
--   * lib/services/reservas_service.dart  (devolucion por cancelacion)
--   * EJECUTAR_EN_SUPABASE.sql              (apply_referral_code)
--
-- La firma debe cubrir todas las llamadas existentes:
--   (p_user_id uuid, p_amount int, p_source text, p_expires_at text,
--    p_description text). Los ultimos tres con default para no romper
--   los callers que solo pasan user_id y amount.
--
-- Implementacion: la misma logica que admin_adjust_user_credits (que ya
-- esta en FIX_ADMIN_ADJUST_CREDITS_LEDGER.sql) para el caso delta > 0:
--   1) insert en creditos_movimientos (source, amount_total/remaining,
--      expires_at, meta con description)
--   2) refresh_user_credit_balance para recalcular usuarios.creditos y
--      usuarios.creditos_vencimiento desde el ledger.


-- 1. Diagnostico previo (lo que pediste) -------------------------------

select routine_name
  from information_schema.routines
 where routine_schema = 'public'
   and routine_name ilike '%credit%';


-- 2. Drop firma legacy conflictiva ------------------------------------
--
-- En la DB de produccion habia ya una funcion grant_user_credits con
-- firma (uuid, integer, text, date, jsonb) — p_expires_at date y
-- p_meta jsonb. Esa vieja firma:
--   * apply_referral_code la llamaba con v_expiry::text -> mismatch
--     date vs text, PostgreSQL devolvia "function does not exist".
--   * Si convivia con la nueva text-text-text, los callers con menos
--     params (ej. agregarCreditos: 3 params) caian en
--     "function call is ambiguous".
--
-- Verificado con grep en lib y supabase: nadie usa p_meta, asi que
-- borrarla no rompe nada. Idempotente.

drop function if exists public.grant_user_credits(uuid, integer, text, date, jsonb);


-- 3. Crear / reemplazar la funcion ------------------------------------

create or replace function public.grant_user_credits(
  p_user_id     uuid,
  p_amount      integer,
  p_source      text    default 'manual',
  p_expires_at  text    default null,
  p_description text    default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_expires_at timestamptz := null;
  v_meta       jsonb       := '{}'::jsonb;
begin
  if p_user_id is null then
    raise exception 'grant_user_credits: p_user_id es null';
  end if;

  if p_amount is null or p_amount <= 0 then
    -- No-op: no acreditamos 0 ni negativo, pero no fallamos para que
    -- el flujo del caller no se rompa.
    return;
  end if;

  if p_expires_at is not null and p_expires_at <> '' then
    v_expires_at := p_expires_at::timestamptz;
  end if;

  if p_description is not null and p_description <> '' then
    v_meta := jsonb_build_object('description', p_description);
  end if;

  insert into public.creditos_movimientos (
    user_id,
    source,
    amount_total,
    amount_remaining,
    expires_at,
    meta
  ) values (
    p_user_id,
    coalesce(nullif(p_source, ''), 'manual'),
    p_amount,
    p_amount,
    v_expires_at,
    v_meta
  );

  -- Recalcula el saldo cacheado en usuarios.creditos / creditos_vencimiento.
  perform public.refresh_user_credit_balance(p_user_id);
end;
$$;


-- 3. Permitir invocacion desde sesiones autenticadas ------------------

grant execute on function public.grant_user_credits(
  uuid, integer, text, text, text
) to authenticated;

grant execute on function public.grant_user_credits(
  uuid, integer, text, text, text
) to service_role;


-- 4. Diagnostico post (verificar que la firma quedo registrada) -------

select routine_name, data_type
  from information_schema.routines
 where routine_schema = 'public'
   and routine_name = 'grant_user_credits';

select parameter_name, data_type, parameter_default, ordinal_position
  from information_schema.parameters
 where specific_schema = 'public'
   and specific_name like 'grant_user_credits%'
 order by ordinal_position;


-- 5. Smoke test del flujo de referidos -------------------------------
-- Reemplazar 'CODIGO_DEL_REFERIDOR' por un codigo real y el uuid del
-- usuario nuevo para probar end-to-end.
-- select public.apply_referral_code(
--   '00000000-0000-0000-0000-000000000000'::uuid,
--   'CODIGO_DEL_REFERIDOR'
-- );
