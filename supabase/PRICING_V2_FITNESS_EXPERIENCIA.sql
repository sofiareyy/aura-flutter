-- AURA - Pricing v2: dos tipos de estudio (fitness / experiencia)
-- (2026-05-14)
--
-- Fitness:
--   - horarios_pico: array de horas tipo ["18:00","19:00","20:00"]
--   - precio_config: {"pilates": {"normal": 12, "pico": 16}, ...}
--   - clase en hora pico -> tipo 'pico', precio pico de la categoria
--   - clase fuera -> tipo 'normal', precio normal de la categoria
--
-- Experiencia:
--   - precio_config: {"ceramica": 50, "spa": 80, ...}
--   - clase -> tipo 'experiencia', precio fijo de la categoria


-- 1. COLUMNAS NUEVAS -----------------------------------------------------

alter table public.estudios
  add column if not exists tipo_estudio text not null default 'fitness',
  add column if not exists horarios_pico jsonb not null default '[]'::jsonb,
  add column if not exists precio_config jsonb not null default '{}'::jsonb;

-- Constraint (puede fallar si ya existe; ignorar)
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'estudios_tipo_estudio_check'
  ) then
    alter table public.estudios
      add constraint estudios_tipo_estudio_check
        check (tipo_estudio in ('fitness', 'experiencia'));
  end if;
end $$;

-- Agregar 'experiencia' al check de clases.tipo_precio
do $$
begin
  alter table public.clases
    drop constraint if exists clases_tipo_precio_check;
  alter table public.clases
    add constraint clases_tipo_precio_check
      check (tipo_precio in ('pico', 'valle', 'normal', 'experiencia'));
end $$;


-- 2. FUNCION DE PRECIO (reemplaza la logica de v1, misma firma) ----------

create or replace function public.calcular_precio_clase(
  p_estudio_id int,
  p_categoria  text,
  p_dia        int,    -- v2 ignora dia (queda por compat de firma)
  p_hora       text
) returns json
language plpgsql
stable
set search_path = public
as $$
declare
  v_tipo       text;
  v_horas_pico jsonb;
  v_config     jsonb;
  v_cat        text := lower(coalesce(p_categoria, ''));
  v_creditos   int;
  v_tipo_p     text;
  v_hora_norm  text;
begin
  select tipo_estudio, horarios_pico, precio_config
    into v_tipo, v_horas_pico, v_config
    from public.estudios
   where id = p_estudio_id;

  if v_tipo is null then
    return json_build_object('creditos', 10, 'tipo', 'normal');
  end if;

  if v_tipo = 'experiencia' then
    v_creditos := coalesce(nullif(v_config ->> v_cat, '')::int, 40);
    return json_build_object('creditos', v_creditos, 'tipo', 'experiencia');
  end if;

  -- fitness: normalizar hora a 'HH:00'
  v_hora_norm := lpad(split_part(coalesce(p_hora, '08:00'), ':', 1), 2, '0') || ':00';

  if v_horas_pico ? v_hora_norm then
    v_creditos := coalesce(nullif(v_config -> v_cat ->> 'pico', '')::int, 18);
    v_tipo_p := 'pico';
  else
    v_creditos := coalesce(nullif(v_config -> v_cat ->> 'normal', '')::int, 12);
    v_tipo_p := 'normal';
  end if;

  return json_build_object('creditos', v_creditos, 'tipo', v_tipo_p);
end;
$$;

grant execute on function public.calcular_precio_clase(int, text, int, text) to authenticated;


-- 3. Verificacion --------------------------------------------------------

select column_name, data_type
  from information_schema.columns
 where table_schema='public' and table_name='estudios'
   and column_name in ('tipo_estudio','horarios_pico','precio_config')
 order by column_name;
