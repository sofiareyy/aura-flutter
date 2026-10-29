-- Deshace FEAT_meta_capi_envios_2026-10-29.sql.
--
-- ORDEN: primero volver a deployar mp-webhook SIN `plataforma` en el select
-- (el commit c45a491 es la versión que corría el 29/10 a las 02:09). Si se
-- borra la columna con el webhook nuevo corriendo, deja de acreditar.

select cron.unschedule('meta-capi-reintentos');
drop index if exists public.meta_capi_eventos_por_mandar;
alter table public.pagos drop column if exists plataforma;
alter table public.meta_capi_eventos drop column if exists payload;
