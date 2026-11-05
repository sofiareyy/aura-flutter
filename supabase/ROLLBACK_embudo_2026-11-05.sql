-- Deshace FEAT_embudo_2026-11-05.sql. Ojo: borra los pasos anotados y los datos de GA de los pagos.
begin;
drop view if exists metricas.embudo;
drop function if exists public.soy_cuenta_interna();
drop function if exists public.registrar_paso_embudo(text, text);
drop table if exists public.embudo_pasos;
alter table public.pagos
  drop column if exists ga_client_id,
  drop column if exists ga_session_id,
  drop column if exists atribucion,
  drop column if exists ga_compra_at;
commit;
