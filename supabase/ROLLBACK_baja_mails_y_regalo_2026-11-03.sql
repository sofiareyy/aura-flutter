-- Deshace FEAT_baja_mails_y_regalo_2026-11-03.sql.
-- OJO: NO devuelve créditos ya regalados (eso sería sacarle créditos a alguien
-- que ya recibió el mail). Si hiciera falta, es otra decisión.
-- Borra el registro del sorteo y las bajas: exportarlos antes si importan.

select cron.unschedule('regalo-recordatorios')
 where exists (select 1 from cron.job where jobname = 'regalo-recordatorios');

drop view if exists metricas.regalo_resumen;
drop view if exists metricas.regalo_detalle;
drop schema if exists metricas;

drop function if exists public.regalo_recordatorios();
drop function if exists public.regalo_otorgar(text, int, int);
drop function if exists public._regalo_disparar_mails(text);
drop function if exists public.regalo_sortear(text, int, int);
drop function if exists public._compro_alguna_vez(uuid);
drop function if exists public.mail_dado_de_baja(text);

drop table if exists public.regalo_campana;
drop table if exists public.mail_bajas;
