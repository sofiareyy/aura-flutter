-- AURA - Agregar columna galeria_urls a la tabla estudios (2026-05-07).
--
-- La app va a permitir al estudio subir varias fotos del local (no de las
-- clases) para que el usuario vea como es el lugar. Hoy solo existe
-- foto_url (una sola); galeria_urls es el complemento.


alter table public.estudios
  add column if not exists galeria_urls text[] not null default '{}'::text[];


-- Verificacion rapida
select column_name, data_type, column_default, is_nullable
  from information_schema.columns
 where table_schema = 'public'
   and table_name   = 'estudios'
   and column_name  = 'galeria_urls';
