-- AURA - Actualizar precios fijos de packs (2026-04-28)
-- Multipliers actualizados:
--   Pack Prueba    : 1.00 -> 1.10  -> $22.000  (20 cr x 1000 x 1.10)
--   Pack Esencial  : 0.95 -> 1.00  -> $50.000  (50 cr x 1000 x 1.00)
--   Pack Popular   : 0.90 -> 0.95  -> $95.000  (100 cr x 1000 x 0.95)
--   Pack Full      : 0.85 -> 0.90  -> $180.000 (200 cr x 1000 x 0.90)


-- 1. Actualizar la funcion recalc_pack_prices con los multipliers nuevos.
--    A partir de ahora cada vez que cambies valor_credito_ars
--    los precios se calcularan con esta nueva base.

create or replace function public.recalc_pack_prices()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_valor numeric;
begin
  select valor::numeric
    into v_valor
    from public.configuracion_global
   where clave = 'valor_credito_ars';

  if v_valor is null or v_valor <= 0 then
    return;
  end if;

  update public.pricing_credit_packs
     set precio = round(20 * v_valor * 1.10)::bigint
   where creditos = 20;

  update public.pricing_credit_packs
     set precio = round(50 * v_valor * 1.00)::bigint
   where creditos = 50;

  update public.pricing_credit_packs
     set precio = round(100 * v_valor * 0.95)::bigint
   where creditos = 100;

  update public.pricing_credit_packs
     set precio = round(200 * v_valor * 0.90)::bigint
   where creditos = 200;
end;
$$;


-- 2. Aplicar los nuevos precios YA con el valor_credito_ars actual.

select public.recalc_pack_prices();


-- 3. Verificacion (correr aparte para chequear)
-- select nombre, creditos, precio from public.pricing_credit_packs order by creditos;
-- Esperado:
--   Pack Prueba    20  cr   22000
--   Pack Esencial  50  cr   50000
--   Pack Popular   100 cr   95000
--   Pack Full      200 cr  180000
