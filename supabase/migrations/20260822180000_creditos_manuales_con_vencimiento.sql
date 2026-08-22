-- ============================================================================
-- AURA — Los creditos manuales del backoffice ya no son eternos
-- ============================================================================
-- (2026-08-22) Tanda A, item 1. Hallazgo de la auditoria del PASO 0.
--
-- EL AGUJERO
-- `admin_adjust_user_credits` era la UNICA funcion de la base que escribia en
-- `creditos_movimientos` sin pasar por `grant_user_credits`, y lo hacia con
-- `expires_at = null` hardcodeado. O sea: cada credito regalado a mano desde
-- el backoffice NO VENCIA NUNCA.
--
-- Es la misma familia que el farmeo del vencimiento arreglado el 21/8: aquel
-- cerro el camino de la cancelacion, y esta puerta lateral quedo abierta.
--
-- Efecto de segundo orden: en el camino negativo el `order by expires_at nulls
-- last` hacia que los eternos se consumieran ULTIMOS. No solo no vencian:
-- eran los mas dificiles de gastar.
--
-- EL ARREGLO
-- Parametro `p_dias` con DEFAULT 90 (la ventana que ya usa la casa para
-- creditos de buena fe: estudio_cancelar_clase devuelve a 90, delete-account
-- a 60 y 90). DROP + CREATE en vez de CREATE OR REPLACE, porque cambia la
-- firma y un replace habria dejado DOS sobrecargas conviviendo.
--
-- Compatible hacia atras: `admin_service.dart:123` llama con 2 parametros y
-- el default cubre el tercero. Verificado por PostgREST: la llamada de 2
-- params devuelve 'No autorizado' (P0001), no PGRST202 'function not found'.
-- No necesita build.
--
-- De paso: el texto del log decia 'Ajustar crÃ©ditos usuario', doble-codificado
-- en UTF-8 en la propia definicion. Corregido.
--
-- LOS 29 CREDITOS ETERNOS QUE YA EXISTIAN
-- Eran 5 movimientos, todos `source = 'manual'`, todos previos al fix:
--   id 12 · julietarey2002 · 20 creditos · CLIENTA REAL (2 compras aprobadas)
--   id 4  · test@aura.com  ·  4 creditos · cuenta de prueba
--   id 6  · tutiacotilla   ·  5 creditos · cuenta de prueba
--   id 5, 15 · ya gastados, sin saldo
--
-- Decision de la usuaria: a Julieta NO se le saca nada. Se le pone vencimiento
-- a 90 dias (20/11), que es POSTERIOR a su vencimiento visible actual (12/9,
-- de sus creditos comprados). Como `usuarios.creditos_vencimiento` muestra el
-- MINIMO de los vencimientos futuros, en la app no ve ningun cambio: sigue
-- viendo 40 creditos venciendo el 12/9. Se ordena el dato sin perjudicarla.
--
-- Las dos de prueba se vencen. La fila queda en el ledger como historial y
-- `refresh_user_credit_balance` las pone en 0: es el camino nativo del
-- sistema, no un borrado a mano.
--
-- VERIFICADO DESPUES DE APLICAR
--   * 0 creditos eternos en TODA la base (antes 5 movimientos, 29 creditos)
--   * julietarey2002: saldo 40, vence 12/9 — identico a antes
--   * test@aura.com: 27 -> 23   ·   tutiacotilla: 5 -> 0
--   * una sola firma de la funcion, sin sobrecargas
--   * un credito manual de prueba nace con fecha a 90 dias (con rollback)
--
-- PENDIENTE RELACIONADO (no lo hace esta migracion)
-- Nada IMPIDE que vuelvan a aparecer. `grant_user_credits` sigue aceptando
-- vencimiento nulo si alguien se lo pasa. Ahora que la tabla no tiene ni un
-- null, se podria poner `expires_at NOT NULL` y cerrar la puerta para
-- siempre, igual que el CHECK de sanidad hizo con los creditos absurdos.
-- ============================================================================

drop function if exists public.admin_adjust_user_credits(uuid, integer);

create or replace function public.admin_adjust_user_credits(
  p_user_id uuid,
  p_delta   integer,
  p_dias    integer default 90
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
  v_vence  date;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  if coalesce(p_dias, 0) <= 0 then
    raise exception 'El vencimiento tiene que ser de al menos 1 dia (recibido %)', p_dias;
  end if;

  v_vence := current_date + p_dias;

  if p_delta > 0 then
    -- Acreditar: nuevo movimiento en el ledger CON vencimiento.
    -- Antes esto iba con expires_at = null y los creditos regalados a mano no
    -- vencian NUNCA. Era la unica funcion que escribia en
    -- creditos_movimientos sin pasar por grant_user_credits, y asi se
    -- salteaba la politica de vencimientos de todo el resto del sistema.
    insert into public.creditos_movimientos (
      user_id, source, amount_total, amount_remaining, expires_at, meta
    ) values (
      p_user_id, 'manual', p_delta, p_delta, v_vence, '{}'::jsonb
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
    coalesce(v_email, p_user_id::text) || ' / delta ' || p_delta ||
      case when p_delta > 0 then ' / vence ' || v_vence else '' end,
    'usuarios'
  );
end;
$function$;

-- ── Los 29 creditos eternos que ya existian ──────────────────────────────
-- Julieta: clienta real. NO se le saca nada, solo se le pone horizonte.
-- 90 dias (20/11) es POSTERIOR a su vencimiento visible actual (12/9, de sus
-- creditos comprados), asi que en la app no ve ningun cambio hoy.
update public.creditos_movimientos
   set expires_at = current_date + 90
 where id = 12;

-- Cuentas de prueba con saldo: se vencen. La fila queda en el ledger como
-- historial; refresh_user_credit_balance las pone en 0. Es el camino nativo
-- del sistema, no un borrado a mano.
update public.creditos_movimientos
   set expires_at = current_date - 1
 where id in (4, 6);

-- Movimientos ya gastados (amount_remaining = 0). No cambia ningun saldo;
-- se les pone fecha para que no quede NINGUN credito sin vencimiento y el
-- invariante "expires_at is not null" se pueda chequear de aca en mas.
update public.creditos_movimientos
   set expires_at = created_at + interval '90 days'
 where id in (5, 15);

select public.refresh_user_credit_balance(user_id)
  from public.creditos_movimientos where id in (4, 6, 12);
