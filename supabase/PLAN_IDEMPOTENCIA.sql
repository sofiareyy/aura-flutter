-- ============================================================================
-- AURA — Idempotencia de suscripciones (planes): process_approved_plan_payment
-- ============================================================================
-- Aplicado a mano vía la Management API el 2026-08-19. Documentado acá para el
-- repo (gemelo del RPC de packs `process_approved_pack_payment`, ver
-- supabase/migrations/20260724100000_gift_card_como_pack_pago.sql).
--
-- Problema que resuelve: el camino de PLANES en mp-webhook acreditaba inline con
-- grant_user_credits, sin lock ni marca de "ya procesado", con el status seteado
-- al final. Una reentrega del mismo webhook de Mercado Pago (comportamiento
-- normal) podía acreditar créditos DOS veces.
--
-- Fix: clonar el mecanismo de packs. Este RPC hace `for update` + chequea
-- `credits_granted_at`. La idempotencia se decide por la FILA del pago, cuya
-- identidad es `mp_payment_id` (índice único parcial ya existente en pagos):
--   - Reentrega del MISMO cobro  -> mismo mp_payment_id -> misma fila ->
--     credits_granted_at ya seteado -> already_processed -> NO acredita.
--   - Renovación mensual         -> mp_payment_id NUEVO -> fila NUEVA ->
--     credits_granted_at null    -> acredita normal.
--
-- El webhook (supabase/functions/mp-webhook/index.ts, rama `type === 'plan'`)
-- llama a este RPC en vez del bloque inline.
--
-- Verificado (2026-08-19, en rollback): pago inicial +N, reentrega +0
-- (already_processed), renovación +N -> saldo final = 2N, no 3N. Packs intacto.
-- ============================================================================

create or replace function public.process_approved_plan_payment(
  p_pago_id uuid, p_mp_payment_id text, p_plan_nombre text, p_expires_at text
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_pago public.pagos%rowtype;
begin
  select * into v_pago from public.pagos where id = p_pago_id for update;   -- LOCK de fila
  if not found then
    raise exception 'Pago no encontrado';
  end if;
  if v_pago.type <> 'plan' then
    raise exception 'El pago no es un plan';
  end if;
  if v_pago.credits_granted_at is not null then                            -- IDEMPOTENCIA
    return jsonb_build_object('status', 'approved', 'credited', true, 'already_processed', true);
  end if;

  perform public.grant_user_credits(
    p_user_id => v_pago.user_id, p_amount => v_pago.creditos,
    p_source => 'plan', p_expires_at => p_expires_at
  );

  update public.pagos
     set mp_payment_id = p_mp_payment_id, status = 'approved', credits_granted_at = now()
   where id = p_pago_id;

  update public.usuarios
     set plan = nullif(p_plan_nombre, ''), subscription_status = 'active',
         renewal_date = current_date + 30
   where id = v_pago.user_id;

  perform public.activar_referido_por_compra(v_pago.user_id);

  return jsonb_build_object('status', 'approved', 'credited', true, 'already_processed', false);
end;
$fn$;

revoke all on function public.process_approved_plan_payment(uuid, text, text, text) from public, anon;
grant execute on function public.process_approved_plan_payment(uuid, text, text, text) to service_role;
