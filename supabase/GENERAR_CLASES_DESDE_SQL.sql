-- AURA - Función server-side para generar clases concretas desde
-- horarios_fijos. Espejo del loop que hace Flutter en
-- generarProximasSemanasDesdeHorarios. (2026-05-12)
--
-- Util como workaround cuando el cliente no corrio la auto-gen (build
-- vieja en TestFlight, o error silencioso). Se puede llamar desde el
-- SQL Editor o desde la app via rpc.


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
  v_week_offset  int;
  v_now          timestamp := timezone('America/Argentina/Buenos_Aires', now())::timestamp;
  v_week_start   date;
  v_fecha        timestamp;
  v_hora         int;
  v_minuto       int;
  v_existente_id int;
begin
  -- Lunes de la semana actual en hora Argentina
  v_week_start := v_now::date - ((extract(isodow from v_now)::int) - 1);

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

    -- horarios_fijos.hora_inicio es de tipo `time`; extraemos hora y minuto.
    v_hora   := coalesce(extract(hour   from v_h.hora_inicio)::int, 8);
    v_minuto := coalesce(extract(minute from v_h.hora_inicio)::int, 0);

    for v_week_offset in 0..(p_weeks - 1) loop
      v_fecha := (v_week_start + (v_week_offset * 7 + (v_h.dia_semana - 1)))::timestamp
                 + make_interval(hours => v_hora, mins => v_minuto);

      -- Saltea si ya existe (tolerancia ±1h)
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
        cancelacion_cierre_minutos, categoria, sala
      ) values (
        p_estudio_id, v_h.id, v_h.nombre, v_h.instructor, v_h.instructor_descripcion,
        v_h.incluye, v_h.imagen_url, v_h.imagen_ajuste, v_h.galeria_urls, v_fecha,
        coalesce(v_h.duracion_min, 60),
        coalesce(v_h.lugares_total, 12),
        coalesce(v_h.lugares_total, 12),
        coalesce(v_h.creditos, 10),
        -- Sin coalesce a 0: null = hereda el default del estudio.
        v_h.reserva_cierre_minutos,
        v_h.cancelacion_cierre_minutos,
        v_h.categoria, v_h.sala
      );
      v_creadas := v_creadas + 1;
    end loop;
  end loop;

  return json_build_object('creadas', v_creadas, 'omitidas', v_omitidas);
end;
$$;

grant execute on function public.generar_clases_estudio(int, int) to authenticated;


-- USO --
-- Para generar 3 meses de clases del estudio 1:
-- select public.generar_clases_estudio(1, 13);
