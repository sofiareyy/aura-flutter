-- AURA - Pricing v3: precio por ESTUDIO (no por categoria) (2026-06-04)
--
-- Cada estudio negocia UN solo rango de precio:
--   precio_config = {"min": 10, "max": 18, "pico_multiplier": 1.0}
--
-- Y clasifica bloques horarios por dia de la semana como pico o valle:
--   horarios_config = {
--     "pico":  [{"dia": 1, "rango": "tarde_noche"}],
--     "valle": [{"dia": 2, "rango": "mediodia"}]
--   }
--   dia: isodow (1 = lunes ... 7 = domingo)
--   rango (bloques): madrugada 0-6, manana_temprano 6-9, manana 9-12,
--                    mediodia 12-15, tarde 15-18, tarde_noche 18-21, noche 21-24
--
-- fitness:
--   - clase en pico  -> creditos = round(max * pico_multiplier), tipo 'pico'
--   - clase en valle -> creditos = round(min * 0.9),             tipo 'valle'
--   - clase normal   -> creditos = round(min),                   tipo 'normal'
-- experiencia:
--   - precio fijo (= min), tipo 'experiencia'
--
-- aplicar_pricing_a_clases_futuras y generar_clases_estudio NO cambian:
-- siguen invocando calcular_precio_clase con la misma firma.


-- 1. COLUMNAS ------------------------------------------------------------

alter table public.estudios
  add column if not exists tipo_estudio text not null default 'fitness',
  add column if not exists precio_config jsonb not null default '{}'::jsonb,
  add column if not exists horarios_config jsonb not null
    default '{"pico":[],"valle":[]}'::jsonb;

-- tipo_precio de clases admite pico/valle/normal/experiencia
do $$
begin
  alter table public.clases
    drop constraint if exists clases_tipo_precio_check;
  alter table public.clases
    add constraint clases_tipo_precio_check
      check (tipo_precio in ('pico', 'valle', 'normal', 'experiencia'));
end $$;


-- 2. FUNCION DE PRECIO (reemplaza v2, misma firma) -----------------------

create or replace function public.calcular_precio_clase(
  p_estudio_id int,
  p_categoria  text,    -- ignorado en v3 (precio por estudio); compat de firma
  p_dia        int,     -- isodow: 1 = lunes ... 7 = domingo
  p_hora       text     -- 'HH:MM' 24h
) returns json
language plpgsql
stable
set search_path = public
as $$
declare
  v_tipo      text;
  v_config    jsonb;
  v_horarios  jsonb;
  v_min       numeric;
  v_max       numeric;
  v_mult      numeric;
  v_hh        int;
  v_rango     text;
  v_es_pico   boolean := false;
  v_es_valle  boolean := false;
  v_elem      jsonb;
  v_creditos  int;
  v_tipo_p    text;
begin
  select tipo_estudio, precio_config, horarios_config
    into v_tipo, v_config, v_horarios
    from public.estudios
   where id = p_estudio_id;

  if v_tipo is null then
    return json_build_object('creditos', 10, 'tipo', 'normal');
  end if;

  v_min  := coalesce(nullif(v_config ->> 'min', '')::numeric, 10);
  v_max  := coalesce(nullif(v_config ->> 'max', '')::numeric, v_min);
  v_mult := coalesce(nullif(v_config ->> 'pico_multiplier', '')::numeric, 1.0);

  -- experiencia: precio fijo (= min)
  if v_tipo = 'experiencia' then
    return json_build_object('creditos', round(v_min)::int, 'tipo', 'experiencia');
  end if;

  -- fitness: bloque horario en el que cae la hora de inicio
  v_hh := coalesce(nullif(split_part(coalesce(p_hora, '08:00'), ':', 1), '')::int, 8);
  v_rango := case
    when v_hh < 6  then 'madrugada'
    when v_hh < 9  then 'manana_temprano'
    when v_hh < 12 then 'manana'
    when v_hh < 15 then 'mediodia'
    when v_hh < 18 then 'tarde'
    when v_hh < 21 then 'tarde_noche'
    else                'noche'
  end;

  -- pico?
  for v_elem in
    select * from jsonb_array_elements(coalesce(v_horarios -> 'pico', '[]'::jsonb))
  loop
    if (v_elem ->> 'dia')::int = p_dia and (v_elem ->> 'rango') = v_rango then
      v_es_pico := true;
      exit;
    end if;
  end loop;

  -- valle? (solo si no es pico)
  if not v_es_pico then
    for v_elem in
      select * from jsonb_array_elements(coalesce(v_horarios -> 'valle', '[]'::jsonb))
    loop
      if (v_elem ->> 'dia')::int = p_dia and (v_elem ->> 'rango') = v_rango then
        v_es_valle := true;
        exit;
      end if;
    end loop;
  end if;

  if v_es_pico then
    v_creditos := round(v_max * v_mult)::int;
    v_tipo_p   := 'pico';
  elsif v_es_valle then
    v_creditos := round(v_min * 0.9)::int;   -- incentivo -10% en valle
    v_tipo_p   := 'valle';
  else
    v_creditos := round(v_min)::int;
    v_tipo_p   := 'normal';
  end if;

  return json_build_object('creditos', v_creditos, 'tipo', v_tipo_p);
end;
$$;

grant execute on function public.calcular_precio_clase(int, text, int, text) to authenticated;


-- 3. (OPCIONAL) Migrar configs viejas al nuevo formato -------------------
-- Las clases ya creadas conservan sus creditos. Para reconvertir un estudio
-- al nuevo esquema, seteá precio_config/horarios_config desde el backoffice
-- y al guardar se llama aplicar_pricing_a_clases_futuras automaticamente.


-- 4. VERIFICACION --------------------------------------------------------

select column_name, data_type
  from information_schema.columns
 where table_schema = 'public' and table_name = 'estudios'
   and column_name in ('tipo_estudio', 'precio_config', 'horarios_config')
 order by column_name;

-- Ejemplo: estudio fitness, lunes 20:00 (tarde_noche) -> deberia dar pico
-- select public.calcular_precio_clase(<id>, null, 1, '20:00');
