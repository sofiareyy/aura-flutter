-- La descripción viaja de la grilla fija a cada clase generada.
-- APLICADO EN PRODUCCIÓN el 2026-10-19.
--
-- POR QUÉ: `clases` tiene `descripcion` pero `horarios_fijos` NO, así que una
-- descripción cargada en la grilla no existía: había que escribirla clase por
-- clase, y cada vez que el cron generaba una semana nueva salía vacía otra
-- vez. Apareció con dos pedidos el mismo día — la grilla de EQUMM y el texto
-- de "primera vez" de Rockcycle — y los dos necesitan lo mismo.

alter table public.horarios_fijos add column if not exists descripcion text;

comment on column public.horarios_fijos.descripcion is
  'Se copia a cada clase que genera la grilla. Antes del 19/10 sólo existía en `clases`, así que se perdía en cada regeneración.';

CREATE OR REPLACE FUNCTION public.generar_clases_estudio(p_estudio_id integer, p_weeks integer DEFAULT 9)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_now          timestamp := (now() at time zone 'America/Argentina/Buenos_Aires');
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
  v_ocupadas     int := 0;
  v_resultado    json;
  v_creditos     int;
  v_tipo         text;
  v_serv         record;
begin
  -- [FIX seguridad] Un usuario solo genera la grilla de un estudio que administra
  -- (o superadmin). El cron corre como service_role (auth.uid() null) y salta.
  if auth.uid() is not null and not public.es_miembro_de_estudio(p_estudio_id::bigint) then
    return json_build_object('creadas', 0, 'omitidas', 0, 'error', 'no_autorizado');
  end if;

  v_week_start := v_now::date - ((extract(isodow from v_now)::int) - 1);

  for v_h in
    select * from public.horarios_fijos
     where estudio_id = p_estudio_id and coalesce(activo, true) = true
  loop
    if v_h.dia_semana is null or v_h.dia_semana < 1 or v_h.dia_semana > 7 then
      v_omitidas := v_omitidas + 1; continue;
    end if;
    if v_h.nombre is null or trim(v_h.nombre) = '' then
      v_omitidas := v_omitidas + 1; continue;
    end if;

    v_hora   := coalesce(extract(hour from v_h.hora_inicio)::int, 8);
    v_minuto := coalesce(extract(minute from v_h.hora_inicio)::int, 0);
    v_hora_text := lpad(v_hora::text, 2, '0') || ':' || lpad(v_minuto::text, 2, '0');

    -- Servicio de precio fijo del horario (2026-08-27). Si el horario quedó
    -- guardado con dos servicios (no debería: el trigger lo rechaza), el
    -- helper levantaría; se protege para que UNA grilla rota no frene la
    -- generación de todo el estudio.
    begin
      select * into v_serv
        from public.servicio_precio_fijo(p_estudio_id::bigint, v_h.categorias);
    exception when others then
      v_serv := null;
    end;

    -- La ETIQUETA sale SIEMPRE de la regla, aunque el precio venga del horario
    -- fijo. `horarios_fijos` no tiene columna `tipo_precio`, así que no hay de
    -- dónde copiarla: hay que calcularla. Con servicio, 'servicio'.
    v_resultado := public.calcular_precio_clase(p_estudio_id, v_serv.servicio, v_h.dia_semana, v_hora_text);
    v_tipo := coalesce(v_resultado->>'tipo', 'normal');

    if coalesce(v_h.creditos, 0) > 0 then
      -- El PRECIO sigue saliendo del horario fijo (D3): si el estudio tiene uno
      -- cargado, la grilla lo respeta en vez de recalcularlo.
      v_creditos := v_h.creditos;
    elsif (v_resultado->>'creditos') is not null then
      v_creditos := (v_resultado->>'creditos')::int;
    else
      v_creditos := 0;
    end if;

    -- Servicio con precio 0 (clase gratis): v_h.creditos puede ser 0 y el
    -- cálculo también ⇒ v_creditos 0 es válido acá, el CHECK de clases lo
    -- permite (creditos >= 0).

    for v_week_offset in 0..(p_weeks - 1) loop
      v_fecha := (v_week_start + (v_week_offset * 7 + (v_h.dia_semana - 1)))::timestamp
                 + make_interval(hours => v_hora, mins => v_minuto);

      select id into v_existente_id
        from public.clases
       where estudio_id = p_estudio_id and horario_fijo_id = v_h.id
         and fecha between v_fecha - interval '1 hour' and v_fecha + interval '1 hour'
       limit 1;

      if v_existente_id is not null then
        v_omitidas := v_omitidas + 1; continue;
      end if;

      -- 2026-08-25: SEGUNDO chequeo, por (estudio, fecha exacta), venga de la
      -- grilla que venga o de ninguna. El primero va por horario_fijo_id y
      -- es ciego a las clases HUERFANAS: clases.horario_fijo_id es ON DELETE
      -- SET NULL, asi que borrar una grilla no borra sus clases; si despues
      -- se recrea la grilla, el generador creaba otra clase encima de cada
      -- huerfana (medido: 3 fechas duplicadas). El camino real del Dart
      -- (_deleteFixed) intenta borrar las clases antes, pero cada paso esta
      -- en try/catch: si el candado de borrado (reserva presente/completada)
      -- o cualquier otro error lo frena, la clase queda huerfana y publicada.
      -- Regla: el generador NUNCA crea encima de una clase que ya existe en
      -- ese minuto para ese estudio. Cuenta aparte como 'ocupadas'.
      select id into v_existente_id
        from public.clases
       where estudio_id = p_estudio_id
         and fecha = v_fecha
         -- 2026-08-25: misma clave que el guard de grillas: la sala distingue.
         and lower(trim(coalesce(sala, ''))) = lower(trim(coalesce(v_h.sala, '')))
       limit 1;

      if v_existente_id is not null then
        v_ocupadas := v_ocupadas + 1; continue;
      end if;

      -- 2026-08-25: no publicar lo que ya paso. La semana arranca el lunes,
      -- asi que una grilla creada un martes publicaba el lunes anterior
      -- (medido: 3 clases del 24/8 al crear el 25/8). Se cuenta como omitida.
      if v_fecha < v_now then
        v_omitidas := v_omitidas + 1; continue;
      end if;

      insert into public.clases (
        estudio_id, horario_fijo_id, nombre, instructor,
        instructor_descripcion, incluye, imagen_url, imagen_ajuste,
        galeria_urls, fecha, duracion_min, lugares_total,
        lugares_disponibles, creditos, reserva_cierre_minutos,
        cancelacion_cierre_minutos, categorias, sala, tipo_precio,
        descripcion
      ) values (
        p_estudio_id, v_h.id, v_h.nombre, v_h.instructor,
        v_h.instructor_descripcion, v_h.incluye, v_h.imagen_url,
        v_h.imagen_ajuste, v_h.galeria_urls, v_fecha,
        coalesce(v_h.duracion_min, 60),
        coalesce(v_h.lugares_total, 12),
        coalesce(v_h.lugares_total, 12),
        v_creditos, v_h.reserva_cierre_minutos, v_h.cancelacion_cierre_minutos,
        coalesce(v_h.categorias, '{}'), v_h.sala, v_tipo,
        v_h.descripcion
      );
      v_creadas := v_creadas + 1;
    end loop;
  end loop;

  return json_build_object('creadas', v_creadas, 'omitidas', v_omitidas, 'ocupadas', v_ocupadas);
end;
$function$
;
