-- Deshace FEAT_atribucion_meta_2026-10-29.sql. OJO: borra los clics guardados.
-- Si la web nueva sigue publicada, la app llama a guardar_fbc y falla en
-- silencio (no rompe nada), así que el orden no importa.
drop function if exists public.guardar_fbc(text);
drop table if exists public.atribucion_meta;
