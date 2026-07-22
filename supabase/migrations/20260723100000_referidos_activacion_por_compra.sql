-- ============================================================================
-- Referidos: la activación (premios) pasa a dispararse con la PRIMERA COMPRA
-- real del referido (pack o plan), no al ingresar el código.
-- ============================================================================
--
-- Antes: apply_referral_code acreditaba 15+20 en el acto, sin exigir compra
-- de ninguna de las partes. Un usuario gratis aplicaba un código y ambos
-- cobraban.
--
-- Ahora, dos pasos:
--   1. apply_referral_code SOLO vincula (referrals con activado_at NULL). No
--      acredita. Valida el tope de 2 acá para no dejar vincular un tercero.
--   2. activar_referido_por_compra(user) acredita 15 al referido y 20 al
--      referrer y marca activado_at. Se llama desde los dos únicos puntos por
--      los que pasa una compra real y NO las acreditaciones gratis:
--        - packs: dentro de process_approved_pack_payment
--        - planes: en mp-webhook, tras marcar el plan activo
--   Nunca lo dispara registro, bienvenida, referral, corporativo ni gift.
-- ============================================================================

-- Estado del vínculo: NULL = pendiente (código aplicado, sin compra todavía).
alter table public.referrals
  add column if not exists activado_at timestamptz;


-- ── Paso 1: apply_referral_code solo vincula ───────────────────────────────
create or replace function public.apply_referral_code(
  p_user_id uuid,
  p_code    text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_referrer_id  uuid;
  v_already_used text;
  v_count        int;
  v_code_upper   text := upper(trim(coalesce(p_code, '')));
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'error', 'no_auth');
  end if;
  if v_code_upper = '' then
    return jsonb_build_object('ok', false, 'error', 'Ingresá un código.');
  end if;

  select codigo_referido_usado into v_already_used
    from public.usuarios where id = p_user_id;

  if v_already_used is not null and v_already_used <> '' then
    return jsonb_build_object('ok', false,
      'error', 'Ya usaste un código de referido anteriormente.');
  end if;

  select id into v_referrer_id
    from public.usuarios
   where upper(codigo_referido) = v_code_upper
   limit 1;

  if v_referrer_id is null then
    return jsonb_build_object('ok', false, 'error', 'Código de referido inválido.');
  end if;
  if v_referrer_id = p_user_id then
    return jsonb_build_object('ok', false,
      'error', 'No podés usar tu propio código.');
  end if;

  -- Tope de 2 por referrer: cuenta vínculos existentes (pendientes +
  -- activados). Así un tercero no puede ni vincularse.
  select count(*) into v_count
    from public.referrals where referrer_user_id = v_referrer_id;
  if v_count >= 2 then
    return jsonb_build_object('ok', false,
      'error', 'Este código ya alcanzó el límite de invitaciones.');
  end if;

  -- Vínculo PENDIENTE. Los créditos se acreditan con la primera compra.
  insert into public.referrals (referrer_user_id, referred_user_id, referral_code, activado_at)
  values (v_referrer_id, p_user_id, v_code_upper, null)
  on conflict on constraint referrals_referrer_referred_unique do nothing;

  update public.usuarios
     set codigo_referido_usado = v_code_upper
   where id = p_user_id;

  return jsonb_build_object(
    'ok', true,
    'pendiente', true,
    'mensaje', 'Código aplicado. Vas a recibir tus créditos con tu primera compra.'
  );
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;

revoke execute on function public.apply_referral_code(uuid, text) from public, anon;
grant execute on function public.apply_referral_code(uuid, text) to authenticated;


-- ── Paso 2: activación al comprar ──────────────────────────────────────────
-- Idempotente: si no hay vínculo pendiente para el usuario, no hace nada.
-- security definer + revoke de authenticated: solo la llaman las funciones de
-- pago (que corren como owner/service_role), nunca el cliente.
create or replace function public.activar_referido_por_compra(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref         record;
  v_expiry      date := current_date + interval '30 days';
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'error', 'no_user');
  end if;

  -- Vínculo pendiente del comprador (es el referido). FOR UPDATE serializa
  -- dos compras casi simultáneas.
  select * into v_ref
    from public.referrals
   where referred_user_id = p_user_id
     and activado_at is null
   for update
   limit 1;

  if not found then
    return jsonb_build_object('ok', true, 'activado', false, 'motivo', 'sin_pendiente');
  end if;

  update public.referrals
     set activado_at = now()
   where referrer_user_id = v_ref.referrer_user_id
     and referred_user_id = v_ref.referred_user_id;

  -- 15 al referido (el comprador), 20 al referrer.
  perform public.grant_user_credits(
    p_user_id => p_user_id, p_amount => 15,
    p_source => 'referral', p_expires_at => v_expiry::text
  );
  perform public.grant_user_credits(
    p_user_id => v_ref.referrer_user_id, p_amount => 20,
    p_source => 'referral', p_expires_at => v_expiry::text
  );

  return jsonb_build_object('ok', true, 'activado', true);
exception when others then
  -- No romper la compra por un fallo de referido.
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;

revoke execute on function public.activar_referido_por_compra(uuid)
  from public, anon, authenticated;
grant execute on function public.activar_referido_por_compra(uuid) to service_role;


-- ── Enganche PACK: dentro de process_approved_pack_payment ─────────────────
-- Idéntica a FIX_MP_PACK_IDEMPOTENCY salvo la llamada al final. Ya es
-- idempotente (for update + credits_granted_at), así que el referido se
-- activa una sola vez por comprador.
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
  select * into v_pago from public.pagos where id = p_pago_id for update;

  if not found then
    raise exception 'Pago no encontrado';
  end if;
  if v_pago.type <> 'pack' then
    raise exception 'El pago no corresponde a un pack';
  end if;
  if v_pago.credits_granted_at is not null then
    return jsonb_build_object('status', 'approved', 'credited', true, 'already_processed', true);
  end if;
  if v_pago.status = 'approved' then
    raise exception 'Pago aprobado sin marca de acreditacion; requiere revision manual';
  end if;
  if p_mp_payment_id is null or btrim(p_mp_payment_id) = '' then
    raise exception 'Falta mp_payment_id';
  end if;

  select id into v_conflicting_pago_id
    from public.pagos
   where mp_payment_id = p_mp_payment_id and id <> p_pago_id
   limit 1;
  if v_conflicting_pago_id is not null then
    raise exception 'mp_payment_id ya vinculado a otro pago';
  end if;

  perform public.grant_user_credits(
    p_user_id => v_pago.user_id, p_amount => v_pago.creditos,
    p_source => 'pack', p_expires_at => p_expires_at
  );

  update public.pagos
     set mp_payment_id = p_mp_payment_id, status = 'approved', credits_granted_at = now()
   where id = p_pago_id;

  -- Primera compra real → activa el referido pendiente si lo hay.
  perform public.activar_referido_por_compra(v_pago.user_id);

  return jsonb_build_object('status', 'approved', 'credited', true, 'already_processed', false);
end;
$$;

revoke all on function public.process_approved_pack_payment(uuid, text, text)
  from public, anon;
grant execute on function public.process_approved_pack_payment(uuid, text, text)
  to service_role;
