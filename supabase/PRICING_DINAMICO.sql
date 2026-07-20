-- AURA - Pricing dinamico por horario (2026-05-12)
--
-- Cada estudio configura:
--   - precio_min[categoria], precio_max[categoria]: rangos en creditos
--   - horarios_config: zonas pico/valle (dia + hora_inicio + hora_fin)
--
-- Cuando se crea una clase en un (dia, hora):
--   - si cae en pico → creditos = precio_max[categoria]
--   - si cae en valle → creditos = precio_min[categoria]
--   - si no → creditos = round((min+max)/2)
--
-- Se guarda en clases.tipo_precio: 'pico' | 'valle' | 'normal'.


-- 1. COLUMNAS NUEVAS -----------------------------------------------------

alter table public.estudios
  add column if not exists horarios_config jsonb not null
    default '{"pico":[],"valle":[]}'::jsonb,
  add column if not exists precio_min jsonb not null default '{}'::jsonb,
  add column if not exists precio_max jsonb not null default '{}'::jsonb;

alter table public.clases
  add column if not exists tipo_precio text not null default 'normal'
    check (tipo_precio in ('pico', 'valle', 'normal'));


-- 2. FUNCION DE CALCULO --------------------------------------------------

create or replace function public.calcular_precio_clase(
  p_estudio_id int,
  p_categoria  text,
  p_dia        int,
  p_hora       text
) returns json
language plpgsql
stable
set search_path = public
as $$
declare
  v_config    jsonb;
  v_min_arr   jsonb;
  v_max_arr   jsonb;
  v_cat       text := lower(coalesce(p_categoria, ''));
  v_min       int;
  v_max       int;
  v_es_pico   boolean := false;
  v_es_valle  boolean := false;
  v_rango     jsonb;
  v_tipo      text;
  v_creditos  int;
begin
  select horarios_config, precio_min, precio_max
    into v_config, v_min_arr, v_max_arr
    from public.estudios
   where id = p_estudio_id;

  v_min := nullif(v_min_arr->>v_cat, '')::int;
  v_max := nullif(v_max_arr->>v_cat, '')::int;

  -- Sin rango configurado → default 10
  if v_min is null and v_max is null then
    return json_build_object('creditos', 10, 'tipo', 'normal');
  end if;
  v_min := coalesce(v_min, v_max);
  v_max := coalesce(v_max, v_min);

  -- Pico?
  for v_rango in
    select * from jsonb_array_elements(coalesce(v_config->'pico', '[]'::jsonb))
  loop
    if (v_rango->>'dia')::int = p_dia
       and p_hora >= (v_rango->>'hora_inicio')
       and p_hora <  (v_rango->>'hora_fin') then
      v_es_pico := true;
      exit;
    end if;
  end loop;

  -- Valle (solo si no es pico)
  if not v_es_pico then
    for v_rango in
      select * from jsonb_array_elements(coalesce(v_config->'valle', '[]'::jsonb))
    loop
      if (v_rango->>'dia')::int = p_dia
         and p_hora >= (v_rango->>'hora_inicio')
         and p_hora <  (v_rango->>'hora_fin') then
        v_es_valle := true;
        exit;
      end if;
    end loop;
  end if;

  if v_es_pico then
    v_tipo := 'pico';
    v_creditos := v_max;
  elsif v_es_valle then
    v_tipo := 'valle';
    v_creditos := v_min;
  else
    v_tipo := 'normal';
    v_creditos := ((v_min + v_max) / 2)::int;
  end if;

  return json_build_object('creditos', v_creditos, 'tipo', v_tipo);
end;
$$;

grant execute on function public.calcular_precio_clase(int, text, int, text)
  to authenticated;


-- 3. RECALCULAR clases existentes ----------------------------------------
-- Util cuando el estudio actualiza su config y queremos ajustar los
-- precios de las clases FUTURAS (no tocamos las pasadas).

create or replace function public.aplicar_pricing_a_clases_futuras(
  p_estudio_id int
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_clase     record;
  v_hora_text text;
  v_dia       int;
  v_resultado json;
  v_actualizadas int := 0;
begin
  for v_clase in
    select c.id, c.fecha, c.estudio_id, e.categoria as estudio_cat
      from public.clases c
      join public.estudios e on e.id = c.estudio_id
     where c.estudio_id = p_estudio_id
       and c.fecha >= now()
  loop
    v_hora_text := to_char(v_clase.fecha, 'HH24:MI');
    v_dia := extract(isodow from v_clase.fecha)::int;
    v_resultado := public.calcular_precio_clase(
      v_clase.estudio_id,
      v_clase.estudio_cat,
      v_dia,
      v_hora_text
    );
    update public.clases
       set creditos = (v_resultado->>'creditos')::int,
           tipo_precio = v_resultado->>'tipo'
     where id = v_clase.id;
    v_actualizadas := v_actualizadas + 1;
  end loop;
  return v_actualizadas;
end;
$$;

grant execute on function public.aplicar_pricing_a_clases_futuras(int)
  to authenticated;


-- 4. Actualizar generar_clases_estudio para usar pricing dinamico --------

create or replace function public.generar_clases_estudio(
  p_estudio_id int,
  p_weeks      int default 13
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_creadas      int := 0;
  v_omitidas     int := 0;
  v_h            record;
  v_estudio_cat  text;
  v_week_offset  int;
  v_now          timestamp := timezone('America/Argentina/Buenos_Aires', now())::timestamp;
  v_week_start   date;
  v_fecha        timestamp;
  v_hora         int;
  v_minuto       int;
  v_hora_text    text;
  v_existente_id int;
  v_resultado    json;
  v_creditos     int;
  v_tipo         text;
begin
  v_week_start := v_now::date - ((extract(isodow from v_now)::int) - 1);

  select categoria into v_estudio_cat from public.estudios where id = p_estudio_id;

  for v_h in
    select * from public.horarios_fijos
     where estudio_id = p_estudio_id
       and coalesce(activo, true) = true
  loop
    if v_h.dia_semana is null or v_h.dia_semana < 1 or v_h.dia_semana > 7 then
      v_omitidas := v_omitidas + 1;
      continue;
    end if;
    if v_h.nombre is null or trim(v_h.nombre) = '' then
      v_omitidas := v_omitidas + 1;
      continue;
    end if;

    v_hora   := coalesce(extract(hour   from v_h.hora_inicio)::int, 8);
    v_minuto := coalesce(extract(minute from v_h.hora_inicio)::int, 0);
    v_hora_text := lpad(v_hora::text, 2, '0') || ':' || lpad(v_minuto::text, 2, '0');

    -- Calcular pricing una vez por horario (no cambia entre semanas)
    v_resultado := public.calcular_precio_clase(
      p_estudio_id,
      coalesce(v_h.categoria, v_estudio_cat),
      v_h.dia_semana,
      v_hora_text
    );
    v_creditos := (v_resultado->>'creditos')::int;
    v_tipo := v_resultado->>'tipo';

    for v_week_offset in 0..(p_weeks - 1) loop
      v_fecha := (v_week_start + (v_week_offset * 7 + (v_h.dia_semana - 1)))::timestamp
                 + make_interval(hours => v_hora, mins => v_minuto);

      select id into v_existente_id
        from public.clases
       where estudio_id = p_estudio_id
         and horario_fijo_id = v_h.id
         and fecha between v_fecha - interval '1 hour' and v_fecha + interval '1 hour'
       limit 1;

      if v_existente_id is not null then
        v_omitidas := v_omitidas + 1;
        continue;
      end if;

      insert into public.clases (
        estudio_id, horario_fijo_id, nombre, instructor, instructor_descripcion,
        incluye, imagen_url, imagen_ajuste, galeria_urls, fecha, duracion_min,
        lugares_total, lugares_disponibles, creditos, reserva_cierre_minutos,
        cancelacion_cierre_minutos, categoria, sala, tipo_precio
      ) values (
        p_estudio_id, v_h.id, v_h.nombre, v_h.instructor, v_h.instructor_descripcion,
        v_h.incluye, v_h.imagen_url, v_h.imagen_ajuste, v_h.galeria_urls, v_fecha,
        coalesce(v_h.duracion_min, 60),
        coalesce(v_h.lugares_total, 12),
        coalesce(v_h.lugares_total, 12),
        v_creditos,
        -- Sin coalesce a 0: null = "no configurado" y la clase hereda el
        -- default del estudio. El coalesce(...,0) anterior escribia 0, que
        -- significa "sin ventana" y pisaba el default (bug de las 12 hs).
        v_h.reserva_cierre_minutos,
        v_h.cancelacion_cierre_minutos,
        v_h.categoria, v_h.sala, v_tipo
      );
      v_creadas := v_creadas + 1;
    end loop;
  end loop;

  return json_build_object('creadas', v_creadas, 'omitidas', v_omitidas);
end;
$$;

grant execute on function public.generar_clases_estudio(int, int)
  to authenticated;


-- VERIFICACION

select column_name, data_type
  from information_schema.columns
 where table_schema='public' and table_name='estudios'
   and column_name in ('horarios_config','precio_min','precio_max')
 order by column_name;

select proname
  from pg_proc
 where proname in (
   'calcular_precio_clase',
   'aplicar_pricing_a_clases_futuras',
   'generar_clases_estudio'
 );
