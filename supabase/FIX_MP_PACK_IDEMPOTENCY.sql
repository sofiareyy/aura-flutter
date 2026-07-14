-- AURA - Procesamiento atomico e idempotente de pagos de packs.
--
-- `pagos.status = 'approved'` significa que los creditos ya fueron
-- acreditados. La fila se bloquea para serializar webhook y confirmacion
-- manual. Si grant_user_credits falla, toda la transaccion se revierte y el
-- pago no queda aprobado.

alter table public.pagos
  add column if not exists credits_granted_at timestamptz;

create or replace function public.process_approved_pack_payment(
  p_pago_id       uuid,
  p_mp_payment_id text,
  p_expires_at    text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_pago public.pagos%rowtype;
  v_conflicting_pago_id uuid;
begin
  select *
    into v_pago
    from public.pagos
   where id = p_pago_id
   for update;

  if not found then
    raise exception 'Pago no encontrado';
  end if;

  if v_pago.type <> 'pack' then
    raise exception 'El pago no corresponde a un pack';
  end if;

  if v_pago.credits_granted_at is not null then
    return jsonb_build_object(
      'status', 'approved',
      'credited', true,
      'already_processed', true
    );
  end if;

  -- Una fila historica approved sin esta marca es ambigua: puede haber sido
  -- acreditada por el flujo anterior o ajustada manualmente. No arriesgamos
  -- una segunda acreditacion automatica.
  if v_pago.status = 'approved' then
    raise exception 'Pago aprobado sin marca de acreditacion; requiere revision manual';
  end if;

  if p_mp_payment_id is null or btrim(p_mp_payment_id) = '' then
    raise exception 'Falta mp_payment_id';
  end if;

  select id
    into v_conflicting_pago_id
    from public.pagos
   where mp_payment_id = p_mp_payment_id
     and id <> p_pago_id
   limit 1;

  if v_conflicting_pago_id is not null then
    raise exception 'mp_payment_id ya vinculado a otro pago';
  end if;

  perform public.grant_user_credits(
    p_user_id    => v_pago.user_id,
    p_amount     => v_pago.creditos,
    p_source     => 'pack',
    p_expires_at => p_expires_at
  );

  update public.pagos
     set mp_payment_id = p_mp_payment_id,
         status = 'approved',
         credits_granted_at = now()
   where id = p_pago_id;

  return jsonb_build_object(
    'status', 'approved',
    'credited', true,
    'already_processed', false
  );
end;
$$;

revoke all on function public.process_approved_pack_payment(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.process_approved_pack_payment(uuid, text, text)
  to service_role;
