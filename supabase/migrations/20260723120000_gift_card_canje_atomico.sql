-- ============================================================================
-- Gift card: canje atómico por RPC (arregla el canje roto por D1)
-- ============================================================================
--
-- El canje escribía usuarios.creditos directo. El trigger de D1 lo bloquea,
-- así que HOY el canje está roto: en el registro cae en un catch silencioso y
-- el usuario no recibe nada ni se marca el regalo. Además tenía:
--   - PISA vs SUMA (registro pisaba el saldo; cuenta existente sumaba)
--   - doble canje posible (select usado=false + update en 2 statements)
--
-- Se reemplaza por un RPC que:
--   - hace compare-and-set atómico sobre `usado` (un solo UPDATE ... WHERE
--     usado=false RETURNING) → no se puede canjear dos veces
--   - acredita con grant_user_credits (source 'regalo') → suma al ledger,
--     pasa el trigger de D1
--   - NO dispara referido (no llama activar_referido_por_compra)
-- ============================================================================

create or replace function public.canjear_regalo(p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_email  text;
  v_regalo record;
  v_code   text := upper(trim(coalesce(p_codigo, '')));
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'no_auth');
  end if;
  if v_code = '' then
    return jsonb_build_object('ok', false, 'error', 'Ingresá un código.');
  end if;

  select email into v_email from auth.users where id = v_uid;

  -- Compare-and-set: marca usado sólo si estaba sin usar. Si dos canjes
  -- corren a la vez, uno solo obtiene la fila (RETURNING), el otro no.
  update public.regalos
     set usado = true
   where upper(codigo) = v_code
     and usado = false
  returning * into v_regalo;

  if not found then
    -- O no existe, o ya fue canjeado.
    if exists (select 1 from public.regalos where upper(codigo) = v_code) then
      return jsonb_build_object('ok', false, 'error', 'Este regalo ya fue canjeado.');
    end if;
    return jsonb_build_object('ok', false, 'error', 'Código de regalo inválido.');
  end if;

  perform public.grant_user_credits(
    p_user_id => v_uid,
    p_amount  => v_regalo.creditos,
    p_source  => 'regalo',
    p_expires_at => (current_date + interval '60 days')::text,
    p_description => 'Gift card canjeada'
  );

  return jsonb_build_object('ok', true, 'creditos', v_regalo.creditos);
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;

revoke execute on function public.canjear_regalo(text) from public, anon;
grant execute on function public.canjear_regalo(text) to authenticated;
