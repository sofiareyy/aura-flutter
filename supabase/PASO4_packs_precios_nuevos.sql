-- ============================================================================
-- AURA — PASO 4: precios y vencimientos nuevos de los packs
-- ============================================================================
-- Esta tabla es la que MANDA: crear-checkout-pack lee el precio de acá e
-- ignora el que muestra la app. Hoy tiene los precios viejos, así que sin
-- este update la app diría $52.500 y Mercado Pago cobraría $50.000.
--
-- La columna que importa para el vencimiento es `vencimiento_dias`.
-- `vigencia_dias` no la lee nadie (quedó duplicada); la dejo en el mismo
-- valor para que no confunda más adelante.


update public.pricing_credit_packs
   set precio           = 22000,
       vencimiento_dias = 30,
       vigencia_dias    = 30,
       descripcion      = 'Ideal para conocer Aura',
       popular          = false,
       orden            = 1,
       activo           = true
 where id = 4;   -- Pack Prueba · 20 cr · $1.100/cr

update public.pricing_credit_packs
   set precio           = 52500,
       vencimiento_dias = 45,
       vigencia_dias    = 45,
       descripcion      = 'Para sumar clases al mes',
       popular          = true,   -- en la app lleva el badge "MÁS POPULAR"
       orden            = 2,
       activo           = true
 where id = 5;   -- Pack Esencial · 50 cr · $1.050/cr

update public.pricing_credit_packs
   set precio           = 100000,
       vencimiento_dias = 45,
       vigencia_dias    = 45,
       descripcion      = 'Para entrenar seguido y variar',
       popular          = false,  -- en la app lleva "MEJOR VALOR", no "MÁS POPULAR"
       orden            = 3,
       activo           = true
 where id = 6;   -- Pack Popular · 100 cr · $1.000/cr

update public.pricing_credit_packs
   set precio           = 190000,
       vencimiento_dias = 60,
       vigencia_dias    = 60,
       descripcion      = 'Máxima libertad para explorar',
       popular          = false,
       orden            = 4,
       activo           = true
 where id = 7;   -- Pack Full · 200 cr · $950/cr


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ Verificación — tiene que coincidir EXACTO con lo que muestra la app      │
-- └──────────────────────────────────────────────────────────────────────────┘
select orden,
       nombre,
       creditos,
       precio,
       round(precio::numeric / creditos, 0) as precio_por_credito,
       vencimiento_dias as vence_en_dias,
       descripcion
  from public.pricing_credit_packs
 where activo
 order by orden;

-- Tiene que dar:
--   1  Pack Prueba     20  $22.000   $1.100/cr  30 días
--   2  Pack Esencial   50  $52.500   $1.050/cr  45 días
--   3  Pack Popular   100  $100.000  $1.000/cr  45 días
--   4  Pack Full      200  $190.000    $950/cr  60 días


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ OPCIONAL — borrar las 3 filas de prueba viejas                           │
-- └──────────────────────────────────────────────────────────────────────────┘
-- 'Pilates', 'Yoga' y 'Cerámica con vino' son de cuando armabas la app.
-- Ya están en activo=false, así que el checkout no las mira. Borrarlas es
-- sólo prolijidad — no rompe el historial, porque `pagos.pack_nombre` guarda
-- el texto del pack, no una referencia a esta tabla.
--
-- Descomentá si querés limpiarlas:
--
-- delete from public.pricing_credit_packs where id in (1, 2, 3);
