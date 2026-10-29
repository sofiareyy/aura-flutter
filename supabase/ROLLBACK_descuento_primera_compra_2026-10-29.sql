-- Deshace FEAT_descuento_primera_compra_2026-10-29.sql.
--
-- Para APAGAR el descuento no hace falta esto: alcanza con
--   update public.configuracion_global set valor = '0'
--    where clave = 'descuento_primera_compra_pct';
--
-- Esto saca todo. Las columnas de `pagos` NO se borran: guardan qué descuento
-- llevó cada pago ya cobrado, y eso es contabilidad.
-- Si el checkout nuevo sigue deployado, antes hay que volver a deployar la
-- versión anterior de crear-checkout-pack (o apagar el porcentaje): sin
-- descuento_primera_compra() el checkout falla.

drop function if exists public.mi_descuento_primera_compra();
drop function if exists public.descuento_primera_compra(uuid);
drop trigger if exists trg_pagos_huella_comprador on public.pagos;
drop function if exists public.pagos_registra_huella_comprador();
drop table if exists public.compradores_huella;
drop function if exists public._huella_email(text);
delete from public.configuracion_global where clave = 'descuento_primera_compra_pct';
