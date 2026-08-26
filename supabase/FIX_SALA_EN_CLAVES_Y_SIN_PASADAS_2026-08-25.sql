-- ═══════════════════════════════════════════════════════════════════════════
-- FIX · la sala distingue horarios, y el generador no publica el pasado
-- 2026-08-25 · salio de la revision del formulario de grilla
--
-- 1) SALA EN LA CLAVE. El guard de grillas (trg_horarios_fijos_00_sin_duplicados)
--    y el segundo chequeo del generador iban por (estudio, dia, hora) /
--    (estudio, fecha) sin mirar `sala`: un estudio con dos salones no podia
--    tener dos clases al mismo minuto. Ahora la clave incluye
--    lower(trim(coalesce(sala,''))) en los dos lados, asi que:
--      misma hora, misma sala (o ninguna)  -> sigue rechazado (caso Tiwar)
--      misma hora, salas distintas          -> pasa, y se publican las dos
--    El mensaje del guard le dice al estudio que cargue la sala si es otra.
--
-- 2) SIN CLASES PASADAS. `v_week_start` es el lunes de la semana, asi que
--    crear una grilla un martes publicaba las clases del lunes anterior.
--    Medido el 25/8: 3 clases del 24/8 al crear "PRUEBA grilla". Se saltean
--    (cuentan como omitidas). El cron no cambia: siempre corre de madrugada
--    y ya venia saltando las existentes.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.horarios_fijos_sin_duplicados()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_dias text[] := array['lunes','martes','miércoles','jueves','viernes','sábado','domingo'];
begin
  -- En UPDATE solo importa si cambio el slot.
  if tg_op = 'UPDATE'
     and new.dia_semana  is not distinct from old.dia_semana
     and new.hora_inicio is not distinct from old.hora_inicio
     and new.estudio_id  is not distinct from old.estudio_id then
    return new;
  end if;

  if exists (
    select 1 from public.horarios_fijos h
     where h.estudio_id  = new.estudio_id
       and h.dia_semana  = new.dia_semana
       and h.hora_inicio = new.hora_inicio
       -- 2026-08-25: la SALA entra en la clave. Dos salones pueden dictar al
       -- mismo minuto; el mismo salon (o ninguno) dos veces, no. Normalizada
       -- para que "Sala 1" y " sala 1" cuenten como la misma.
       and lower(trim(coalesce(h.sala, ''))) = lower(trim(coalesce(new.sala, '')))
       and h.id is distinct from new.id
  ) then
    if coalesce(trim(new.sala), '') <> '' then
      raise exception
        'Ya tenés un horario fijo el % a las % en la sala %. Si querés cambiarlo, editá ese en vez de crear otro.',
        coalesce(v_dias[new.dia_semana], 'día '||new.dia_semana),
        to_char(new.hora_inicio, 'HH24:MI'), trim(new.sala)
        using errcode = 'unique_violation';
    else
      raise exception
        'Ya tenés un horario fijo el % a las %. Si es en otra sala, cargá el nombre de la sala; si no, editá ese en vez de crear otro.',
        coalesce(v_dias[new.dia_semana], 'día '||new.dia_semana),
        to_char(new.hora_inicio, 'HH24:MI')
        using errcode = 'unique_violation';
    end if;
  end if;

  return new;
end;
$function$
;

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

    -- La ETIQUETA sale SIEMPRE de la regla, aunque el precio venga del horario
    -- fijo. Antes esta rama hacia `v_tipo := 'normal'` hardcodeado, y como el
    -- trigger siempre le pone precio al horario, la rama corria SIEMPRE: toda
    -- clase generada nacia etiquetada 'normal'. En un estudio en modo rango eso
    -- significa que una clase de franja valle salia diciendo 'normal', y el
    -- badge de Explorar la mostraba como precio reducido siendo pico.
    -- `horarios_fijos` no tiene columna `tipo_precio`, asi que no hay de donde
    -- copiarla: hay que calcularla.
    v_resultado := public.calcular_precio_clase(p_estudio_id, null, v_h.dia_semana, v_hora_text);
    v_tipo := coalesce(v_resultado->>'tipo', 'normal');

    if coalesce(v_h.creditos, 0) > 0 then
      -- El PRECIO sigue saliendo del horario fijo (D3): si el estudio tiene uno
      -- cargado, la grilla lo respeta en vez de recalcularlo.
      v_creditos := v_h.creditos;
    else
      v_creditos := (v_resultado->>'creditos')::int;
    end if;

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
        cancelacion_cierre_minutos, categorias, sala, tipo_precio
      ) values (
        p_estudio_id, v_h.id, v_h.nombre, v_h.instructor,
        v_h.instructor_descripcion, v_h.incluye, v_h.imagen_url,
        v_h.imagen_ajuste, v_h.galeria_urls, v_fecha,
        coalesce(v_h.duracion_min, 60),
        coalesce(v_h.lugares_total, 12),
        coalesce(v_h.lugares_total, 12),
        v_creditos, v_h.reserva_cierre_minutos, v_h.cancelacion_cierre_minutos,
        coalesce(v_h.categorias, '{}'), v_h.sala, v_tipo
      );
      v_creadas := v_creadas + 1;
    end loop;
  end loop;

  return json_build_object('creadas', v_creadas, 'omitidas', v_omitidas, 'ocupadas', v_ocupadas);
end;
$function$
;
