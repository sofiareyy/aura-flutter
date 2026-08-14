-- AURA — Planes de suscripción configurados en la base (2026-08-13). Solo LEE.
--
-- La app los pide con PricingService.getPlanes(), que consulta esta tabla
-- filtrando activo = true y ordenando por `orden`. Si la consulta falla o
-- devuelve vacío, cae a la lista hardcodeada de AppConstants.planes.

-- 1) Los planes tal cual están, incluidos los inactivos.
select orden,
       nombre,
       creditos,
       precio,
       activo,
       destacado,
       descripcion,
       ahorro
  from public.pricing_planes
 order by orden nulls last, nombre;

-- 2) Lo que realmente ve el usuario hoy (mismo filtro que la app).
select orden, nombre, creditos, precio, descripcion
  from public.pricing_planes
 where activo = true
 order by orden;

-- 3) Precio por crédito de cada plan, para comparar entre sí.
select nombre,
       creditos,
       precio,
       round(precio::numeric / nullif(creditos, 0), 2) as precio_por_credito
  from public.pricing_planes
 where activo = true
 order by orden;
