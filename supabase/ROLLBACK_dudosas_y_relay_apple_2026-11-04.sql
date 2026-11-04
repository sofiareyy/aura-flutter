-- Vuelve atrás FEAT_dudosas_y_relay_apple_2026-11-04.sql
drop view if exists metricas.regalo_resumen_sin_dudosas;
-- regalo_resumen y regalo_detalle: volver a correr la sección de métricas de
-- FEAT_baja_mails_y_regalo_2026-11-03.sql (hay que dropear las vistas antes,
-- porque se sacan columnas).
drop table if exists public.cuentas_dudosas;
insert into public.mail_bajas (email, origen) values
  ('csghfh6vh8@privaterelay.appleid.com','rebote_apple'),
  ('myykz5h576@privaterelay.appleid.com','rebote_apple'),
  ('bv5d8ykbb7@privaterelay.appleid.com','rebote_apple'),
  ('hbz57r266c@privaterelay.appleid.com','rebote_apple')
on conflict (email) do nothing;
