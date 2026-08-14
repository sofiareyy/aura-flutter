-- ============================================================================
-- AURA — PASO 3: qué hay en pricing_credit_packs
-- ============================================================================
-- SOLO LECTURA. No cambia nada.
--
-- crear-checkout-pack lee esta tabla y, si encuentra el pack, usa el precio
-- y el vencimiento de acá IGNORANDO lo que muestra la app. Si tiene valores
-- viejos, la app diría $52.500 y Mercado Pago cobraría otra cosa.

-- Columnas de la tabla (no está en las migraciones, la creaste a mano):
select column_name,
       data_type,
       is_nullable,
       column_default
  from information_schema.columns
 where table_schema = 'public'
   and table_name   = 'pricing_credit_packs'
 order by ordinal_position;


-- Contenido actual, con el precio por crédito para comparar:
select *,
       case when creditos > 0
            then round(precio::numeric / creditos, 0)
       end as precio_por_credito
  from public.pricing_credit_packs
 order by creditos;


-- Lo que TIENE que quedar cuando lo actualicemos:
--
--   Pack Prueba     20 cr   $22.000   $1.100/cr   30 días
--   Pack Esencial   50 cr   $52.500   $1.050/cr   45 días
--   Pack Popular   100 cr  $100.000   $1.000/cr   45 días
--   Pack Full      200 cr  $190.000     $950/cr   60 días
