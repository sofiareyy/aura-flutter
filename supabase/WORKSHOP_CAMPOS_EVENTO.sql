-- AURA - Campos extra para workshops/eventos (2026-07-09).
--
-- FIX 8: al crear un workshop el estudio puede cargar una descripción larga
-- del evento y una dirección propia (puede diferir de la del estudio). "Qué
-- incluye" reutiliza la columna existente `clases.incluye`. No se agrega link
-- externo a propósito.

alter table public.clases
  add column if not exists descripcion text;

alter table public.clases
  add column if not exists direccion text;

comment on column public.clases.descripcion is
  'Descripción larga del evento/workshop. Vacío en clases normales.';
comment on column public.clases.direccion is
  'Dirección propia del workshop (puede diferir de la del estudio).';
