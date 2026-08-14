-- ============================================================================
-- Gift cards que se PAGAN (reusan el flujo de packs de Mercado Pago)
-- ============================================================================
--
-- Antes: regalar una gift card era un INSERT directo y GRATIS en `regalos`
-- (sin pago). Cualquiera podía regalar créditos que nadie pagaba, y el mail al
-- destinatario ni siquiera existía.
--
-- Ahora: comprar una gift card = comprar un pack, pero con destinatario. Mismo
-- checkout, mismos tokens, mismo webhook. La única diferencia está DESPUÉS de
-- aprobarse el pago: en vez de acreditar créditos al comprador, se crea el
-- `regalo` con su código y el webhook manda el mail al destinatario.
--
-- El discriminador es `pagos.type = 'gift'` (no se reusa 'pack'). Los datos del
-- destinatario viajan en el propio `pago` (gift_email, gift_mensaje).
--
-- Idempotencia: igual que los packs, `credits_granted_at` marca "ya procesado".
-- Un mismo pago NO puede generar dos regalos ni dos mails: solo la primera
-- llamada al RPC crea el regalo y devuelve el código para mailear; las
-- siguientes devuelven already_processed=true sin código.
--
-- El regalo NO dispara referido (a diferencia de un pack real).
-- ============================================================================

-- ── 1. Columnas del destinatario en `pagos` ────────────────────────────────
alter table public.pagos
  add column if not exists gift_email   text,
  add column if not exists gift_mensaje text;


-- ── 2. process_approved_pack_payment: bifurca pack vs gift ──────────────────
-- Misma firma e idempotencia que la versión de packs. Cuando type='gift':
--   - crea el regalo (remitente = comprador, destinatario = gift_email)
--   - marca el pago procesado (mismo credits_granted_at)
--   - NO acredita al comprador, NO dispara referido
--   - devuelve el código + datos para que el webhook mande el mail
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
  v_codigo            text;
  v_remitente_nombre  text;
begin
  select * into v_pago from public.pagos where id = p_pago_id for update;

  if not found then
    raise exception 'Pago no encontrado';
  end if;
  if v_pago.type not in ('pack', 'gift') then
    raise exception 'El pago no corresponde a un pack ni a una gift card';
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

  -- ── Rama GIFT ────────────────────────────────────────────────────────────
  if v_pago.type = 'gift' then
    if v_pago.gift_email is null or btrim(v_pago.gift_email) = '' then
      raise exception 'Gift card sin email de destinatario';
    end if;

    -- Código único legible. La columna `regalos.codigo` tiene default, pero lo
    -- generamos explícito para devolverlo y mailearlo.
    v_codigo := 'GIFT-' || upper(substring(replace(gen_random_uuid()::text, '-', ''), 1, 8));

    insert into public.regalos (remitente_id, destinatario_email, creditos, codigo, usado, mensaje)
    values (
      v_pago.user_id,
      lower(btrim(v_pago.gift_email)),
      v_pago.creditos,
      v_codigo,
      false,
      nullif(btrim(coalesce(v_pago.gift_mensaje, '')), '')
    );

    -- Marca el pago procesado (misma idempotencia que un pack).
    update public.pagos
       set mp_payment_id = p_mp_payment_id, status = 'approved', credits_granted_at = now()
     where id = p_pago_id;

    select nombre into v_remitente_nombre from public.usuarios where id = v_pago.user_id;

    -- Devuelve lo necesario para que el webhook mande el mail (solo esta vez).
    return jsonb_build_object(
      'status', 'approved',
      'credited', true,
      'already_processed', false,
      'is_gift', true,
      'gift_codigo', v_codigo,
      'gift_email', lower(btrim(v_pago.gift_email)),
      'gift_mensaje', nullif(btrim(coalesce(v_pago.gift_mensaje, '')), ''),
      'gift_creditos', v_pago.creditos,
      'remitente_nombre', coalesce(v_remitente_nombre, '')
    );
  end if;

  -- ── Rama PACK (comportamiento original) ──────────────────────────────────
  perform public.grant_user_credits(
    p_user_id => v_pago.user_id, p_amount => v_pago.creditos,
    p_source => 'pack', p_expires_at => p_expires_at
  );

  update public.pagos
     set mp_payment_id = p_mp_payment_id, status = 'approved', credits_granted_at = now()
   where id = p_pago_id;

  -- Primera compra real → activa el referido pendiente si lo hay.
  perform public.activar_referido_por_compra(v_pago.user_id);

  return jsonb_build_object('status', 'approved', 'credited', true, 'already_processed', false, 'is_gift', false);
end;
$$;

revoke all on function public.process_approved_pack_payment(uuid, text, text)
  from public, anon;
grant execute on function public.process_approved_pack_payment(uuid, text, text)
  to service_role;
