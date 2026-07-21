-- ============================================================================
-- D3 punto 10 — La grilla respeta el precio que puso el estudio
-- ============================================================================
--
-- `generar_clases_estudio` nunca leía `horarios_fijos.creditos`: recalculaba
-- todo con `calcular_precio_clase`. Un horario fijo con precio elegido dentro
-- del rango generaba clases con OTRO precio. Ahora usa el precio del horario
-- si está seteado, y solo cae a calcular_precio_clase como fallback.
--
-- Sigue sin derivar el precio de la categoría (D3/Tanda B): calcular_precio_
-- clase recibe null y solo se usa para horarios sin precio propio.
-- ============================================================================

create or replace function public.generar_clases_estudio(
  p_estudio_id int,
  p_weeks int default 9
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now          timestamp := (
    now() at time zone 'America/Argentina/Buenos_Aires'
  );
  v_week_start   date;
  v_week_offset  int;
  v_h            record;
  v_creadas      int := 0;
  v_omitidas     int := 0;
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

  for v_h in
    select * from public.horarios_fijos
     where estudio_id = p_estudio_id
       and coalesce(activo, true) = true
  loop
    if v_h.dia_semana is null
       or v_h.dia_semana < 1
       or v_h.dia_semana > 7 then
      v_omitidas := v_omitidas + 1;
      continue;
    end if;

    if v_h.nombre is null or trim(v_h.nombre) = '' then
      v_omitidas := v_omitidas + 1;
      continue;
    end if;

    v_hora   := coalesce(extract(hour from v_h.hora_inicio)::int, 8);
    v_minuto := coalesce(extract(minute from v_h.hora_inicio)::int, 0);
    v_hora_text := lpad(v_hora::text, 2, '0')
                   || ':'
                   || lpad(v_minuto::text, 2, '0');

    -- El precio sale del horario fijo (que es lo que eligió el estudio). Solo
    -- si el horario no tiene precio propio se recurre a calcular_precio_clase,
    -- que a su vez NO depende de la categoría (recibe null).
    if coalesce(v_h.creditos, 0) > 0 then
      v_creditos := v_h.creditos;
      v_tipo := coalesce(v_h.tipo_precio, 'normal');
    else
      v_resultado := public.calcular_precio_clase(
        p_estudio_id, null, v_h.dia_semana, v_hora_text
      );
      v_creditos := (v_resultado->>'creditos')::int;
      v_tipo := v_resultado->>'tipo';
    end if;

    for v_week_offset in 0..(p_weeks - 1) loop
      v_fecha := (
        v_week_start + (v_week_offset * 7 + (v_h.dia_semana - 1))
      )::timestamp
      + make_interval(hours => v_hora, mins => v_minuto);

      select id into v_existente_id
        from public.clases
       where estudio_id = p_estudio_id
         and horario_fijo_id = v_h.id
         and fecha between v_fecha - interval '1 hour'
                       and v_fecha + interval '1 hour'
       limit 1;

      if v_existente_id is not null then
        v_omitidas := v_omitidas + 1;
        continue;
      end if;

      insert into public.clases (
        estudio_id, horario_fijo_id, nombre, instructor,
        instructor_descripcion, incluye, imagen_url, imagen_ajuste,
        galeria_urls, fecha, duracion_min, lugares_total,
        lugares_disponibles, creditos, reserva_cierre_minutos,
        cancelacion_cierre_minutos, categorias, sala, tipo_precio
      ) values (
        p_estudio_id, v_h.id, v_h.nombre, v_h.instructor,
        v_h.instructor_descripcion, v_h.incluye, v_h.imagen_url,
        v_h.imagen_ajuste, v_h.galeria_urls, v_fecha,
        coalesce(v_h.duracion_min, 60),
        coalesce(v_h.lugares_total, 12),
        coalesce(v_h.lugares_total, 12),
        v_creditos,
        v_h.reserva_cierre_minutos,
        v_h.cancelacion_cierre_minutos,
        coalesce(v_h.categorias, '{}'),
        v_h.sala, v_tipo
      );
      v_creadas := v_creadas + 1;
    end loop;
  end loop;

  return json_build_object('creadas', v_creadas, 'omitidas', v_omitidas);
end;
$$;

grant execute on function public.generar_clases_estudio(int, int)
  to authenticated, service_role;
