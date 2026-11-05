-- Deshace FEAT_secuencia_bienvenida_2026-11-04.sql.
-- Para solo APAGARLA no hace falta esto: update public.secuencia_config set activa = false;
-- Ojo: borra el registro de qué mails se mandaron.
begin;
select cron.unschedule('secuencia-bienvenida');
drop view if exists metricas.secuencia_resumen;
drop function if exists public.secuencia_tick();
drop function if exists public.secuencia_tomar(uuid, smallint, text);
drop function if exists public.secuencia_a_enviar(int);
drop table if exists public.secuencia_mails;
drop table if exists public.secuencia_config;
commit;
