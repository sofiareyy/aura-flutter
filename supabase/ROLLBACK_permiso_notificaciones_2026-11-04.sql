-- Vuelve atrás FEAT_permiso_notificaciones_2026-11-04.sql (pedir OK a Sofía: borra cosas).
drop view if exists metricas.permiso_push_estudios;
drop function if exists public.informar_permiso_notificaciones(text, text);
alter table public.dispositivos
  drop column if exists permiso_notificaciones,
  drop column if exists permiso_at;
