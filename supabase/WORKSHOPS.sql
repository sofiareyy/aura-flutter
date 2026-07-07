-- Workshops / Eventos: tipo de clase + organizadores. 2026-07-07.
--
-- Una "clase" puede ser tipo 'clase' (normal) o 'workshop' (evento especial).
-- Diferencias del workshop (aplicadas en app/liquidación, no en el esquema):
--   * precio libre en créditos (lo define el estudio, sin rango de pricing v3)
--   * comisión de Aura 15% (en vez del comision_aura del estudio, ~30%)
--   * organizadores: lista de {nombre, instagram}
--   * duración flexible

alter table public.clases
  add column if not exists tipo text not null default 'clase';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'clases_tipo_check'
  ) then
    alter table public.clases
      add constraint clases_tipo_check check (tipo in ('clase', 'workshop'));
  end if;
end $$;

alter table public.clases
  add column if not exists organizadores jsonb not null default '[]'::jsonb;

comment on column public.clases.tipo is
  'clase (normal) | workshop (evento: precio libre, comisión 15%, organizadores)';
comment on column public.clases.organizadores is
  'Array de {nombre, instagram} para workshops. Vacío en clases normales.';
