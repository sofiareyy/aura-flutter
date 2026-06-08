-- AURA - Fix: ajuste de créditos del backoffice no se reflejaba al usuario
--
-- PROBLEMA:
--   El saldo real del usuario se calcula con refresh_user_credit_balance(),
--   que SUMA creditos_movimientos.amount_remaining y SOBRESCRIBE usuarios.creditos.
--   La versión vieja de admin_adjust_user_credits hacía un UPDATE directo sobre
--   usuarios.creditos SIN crear movimiento en el ledger. Por eso, apenas el usuario
--   abría la app (getUsuario -> refresh_user_credit_balance), el ajuste manual se
--   perdía (el balance se recalculaba desde el ledger, que no tenía ese movimiento).
--
-- FIX:
--   admin_adjust_user_credits ahora opera sobre el ledger:
--     - delta > 0: inserta un movimiento (source 'manual'), igual que grant_user_credits.
--     - delta < 0: consume amount_remaining del ledger (FIFO por vencimiento).
--   Luego llama a refresh_user_credit_balance, que deja usuarios.creditos consistente.
--   Misma firma (uuid, integer) -> no hay que tocar el código Flutter.

create or replace function public.admin_adjust_user_credits(
  p_user_id uuid,
  p_delta   integer
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_email  text;
  v_needed integer;
  v_row    record;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  if p_delta > 0 then
    -- Acreditar: nuevo movimiento en el ledger (sin vencimiento).
    insert into public.creditos_movimientos (
      user_id, source, amount_total, amount_remaining, expires_at, meta
    ) values (
      p_user_id, 'manual', p_delta, p_delta, null, '{}'::jsonb
    );

  elsif p_delta < 0 then
    -- Descontar: consumir del ledger, priorizando lo que vence antes.
    v_needed := -p_delta;
    for v_row in
      select id, amount_remaining
        from public.creditos_movimientos
       where user_id = p_user_id
         and amount_remaining > 0
       order by expires_at nulls last, id
    loop
      exit when v_needed <= 0;
      if v_row.amount_remaining <= v_needed then
        v_needed := v_needed - v_row.amount_remaining;
        update public.creditos_movimientos
           set amount_remaining = 0
         where id = v_row.id;
      else
        update public.creditos_movimientos
           set amount_remaining = amount_remaining - v_needed
         where id = v_row.id;
        v_needed := 0;
      end if;
    end loop;
  end if;

  -- Recalcula usuarios.creditos y creditos_vencimiento desde el ledger.
  perform public.refresh_user_credit_balance(p_user_id);

  select email into v_email from public.usuarios where id = p_user_id;
  perform public.log_admin_action(
    'Ajustar créditos usuario',
    coalesce(v_email, p_user_id::text) || ' / delta ' || p_delta,
    'usuarios'
  );
end;
$function$;
