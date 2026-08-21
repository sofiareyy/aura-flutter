-- =====================================================================
-- FIX de 2 agujeros de seguridad — 2026-08-21
-- Encontrados MIDIENDO contra la base (no estaban en ningún pendiente).
-- Ambos aplicados vía Management API y verificados con rollback + efecto.
-- Solo base, sin Dart => sin build.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 🔴 1. process_approved_plan_payment — acuñación de créditos (PLATA)
-- ---------------------------------------------------------------------
-- Bug: tenía grant EXECUTE a `authenticated`. Una usuaria logueada podía
-- llamarla sobre un pago propio pending/rejected/cancelled y acreditarse
-- los créditos (no valida `status`, solo `type` + `credits_granted_at`).
-- CONFIRMADO explotable: pago rejected de 30 créditos → saldo 0→30,
-- pago rejected→approved, plan seteado. 6 pagos de plan sin acreditar
-- (=300 créditos) eran reclamables.
--
-- Fix: quitar el grant a authenticated y dejarla SOLO service_role, igual
-- que su gemela `process_approved_pack_payment` (que ya estaba bien).
-- El único llamador legítimo es la edge `mp-webhook` (index.ts:429), que
-- corre como service_role (index.ts:20) y solo invoca con status approved
-- (index.ts:407). Revocar authenticated NO rompe la acreditación real.
-- Se revoca de public/anon también (defensa; PUBLIC ya no tenía grant).
--
-- Verificado post-fix (medido, con rollback):
--   ACL final: postgres | service_role  (== gemela de packs), auth=false
--   atacante (authenticated, pago rejected) → permission denied, saldo 0→0
--   service_role sobre pago aprobado → sigue acreditando, saldo 0→50

revoke execute on function public.process_approved_plan_payment(
  p_pago_id uuid, p_mp_payment_id text, p_plan_nombre text, p_expires_at text
) from public, anon, authenticated;

-- Reversión (si hiciera falta):
-- grant execute on function public.process_approved_plan_payment(
--   p_pago_id uuid, p_mp_payment_id text, p_plan_nombre text, p_expires_at text
-- ) to authenticated;

-- ---------------------------------------------------------------------
-- 🔴 2. apply_referral_code — sabotaje de referidos (INTEGRIDAD)
-- ---------------------------------------------------------------------
-- Bug: recibía p_user_id como parámetro y NUNCA lo comparaba con auth.uid().
-- Una usuaria logueada podía pasar el uid de OTRA y: quemarle su
-- codigo_referido_usado (no puede usar código nunca más) y agotarle los 2
-- cupos a cualquier referrer con víctimas que no aceptaron.
-- CONFIRMADO explotable: víctima codigo null→02D2335496, referrer 1→2 cupos.
--
-- Fix: agregar el guard de su gemela `ensure_referral_code`
-- (auth.uid() = p_user_id), manteniendo el estilo propio (devuelve jsonb,
-- no raise, para no romper el contrato con el cliente referidos_service.dart).
-- ÚNICA línea del cuerpo que cambia:
--   ANTES:  if p_user_id is null then
--   AHORA:  if p_user_id is null or auth.uid() is null or auth.uid() is distinct from p_user_id then
--
-- Verificado post-fix (medido, con rollback):
--   legítima (usuaria sobre su propio uid, código válido) → ok:true, vincula
--   atacante (uid de otra) → {ok:false, error:no_auth}, víctima intacta,
--                            cupos del referrer 1→1, vínculos víctima 0→0
--   sin sesión → {ok:false, error:no_auth}

CREATE OR REPLACE FUNCTION public.apply_referral_code(p_user_id uuid, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_referrer_id  uuid;
  v_already_used text;
  v_count        int;
  v_code_upper   text := upper(trim(coalesce(p_code, '')));
begin
  if p_user_id is null or auth.uid() is null or auth.uid() is distinct from p_user_id then
    return jsonb_build_object('ok', false, 'error', 'no_auth');
  end if;
  if v_code_upper = '' then
    return jsonb_build_object('ok', false, 'error', 'IngresÃ¡ un cÃ³digo.');
  end if;

  select codigo_referido_usado into v_already_used
    from public.usuarios where id = p_user_id;

  if v_already_used is not null and v_already_used <> '' then
    return jsonb_build_object('ok', false,
      'error', 'Ya usaste un cÃ³digo de referido anteriormente.');
  end if;

  select id into v_referrer_id
    from public.usuarios
   where upper(codigo_referido) = v_code_upper
   limit 1;

  if v_referrer_id is null then
    return jsonb_build_object('ok', false, 'error', 'CÃ³digo de referido invÃ¡lido.');
  end if;
  if v_referrer_id = p_user_id then
    return jsonb_build_object('ok', false,
      'error', 'No podÃ©s usar tu propio cÃ³digo.');
  end if;

  -- Tope de 2 por referrer: cuenta vÃ­nculos existentes (pendientes +
  -- activados). AsÃ­ un tercero no puede ni vincularse.
  select count(*) into v_count
    from public.referrals where referrer_user_id = v_referrer_id;
  if v_count >= 2 then
    return jsonb_build_object('ok', false,
      'error', 'Este cÃ³digo ya alcanzÃ³ el lÃ­mite de invitaciones.');
  end if;

  -- VÃ­nculo PENDIENTE. Los crÃ©ditos se acreditan con la primera compra.
  insert into public.referrals (referrer_user_id, referred_user_id, referral_code, activado_at)
  values (v_referrer_id, p_user_id, v_code_upper, null)
  on conflict on constraint referrals_referrer_referred_unique do nothing;

  update public.usuarios
     set codigo_referido_usado = v_code_upper
   where id = p_user_id;

  return jsonb_build_object(
    'ok', true,
    'pendiente', true,
    'mensaje', 'CÃ³digo aplicado. Vas a recibir tus crÃ©ditos con tu primera compra.'
  );
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$function$

-- (fin)
