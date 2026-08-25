-- ═══════════════════════════════════════════════════════════════════════════
-- FIX · el generador no crea clases encima de una que ya existe (huerfanas)
-- 2026-08-25
--
-- LA INTERACCION (encontrada en la verificacion de punta a punta del 25/8)
-- Cuatro piezas correctas por separado se encadenan mal:
--   1. clases.horario_fijo_id es ON DELETE SET NULL: borrar una grilla NO
--      borra sus clases, quedan huerfanas y publicadas.
--   2. El chequeo de existencia de generar_clases_estudio iba SOLO por
--      horario_fijo_id: una huerfana es invisible para el, crea otra encima.
--   3. El guard del 25/8 (trg_horarios_fijos_00_sin_duplicados) es de
--      GRILLAS, no de clases: la grilla recreada no choca con nada.
--   4. _deleteFixed (Dart) si cancela y borra las clases antes de borrar la
--      grilla, pero cada paso esta en try{}catch(_){}: si el candado del
--      24/8 (reserva presente/completada) u otro error frena el borrado de
--      una clase, se traga el error y borra la grilla igual.
-- Medido: borrar grilla lun 18:15 -> 3 huerfanas; recrear + generar -> 4
-- creadas, 3 fechas DUPLICADAS. Hoy no muerde (no hay reservas); el 13/9 si.
--
-- EL ARREGLO: un segundo chequeo por (estudio_id, fecha exacta), sin mirar
-- horario_fijo_id ni tipo. El generador nunca crea encima de una clase que
-- ya existe en ese minuto para ese estudio, venga de donde venga. Cierra
-- tambien las huerfanas viejas y, de yapa, frena que el cron siga creando
-- semanas duplicadas para las 60 grillas repetidas de Tiwar hasta que se
-- limpien. Devuelve el conteo aparte ('ocupadas') para diagnostico; el Dart
-- solo lee creadas/omitidas.
--
-- El primer chequeo (por grilla, +/- 1 h) se conserva: es del que depende
-- trg_horarios_fijos_mover_clases para que mover una grilla no duplique.
--
-- Efecto colateral deliberado: si un estudio carga una clase suelta (o un
-- workshop) exactamente en el minuto de una clase de grilla, esa semana la
-- grilla no genera la suya. Es lo que dice la regla y es coherente con el
-- guard de grillas: un minuto, una clase, por estudio.
--
-- Lo que NO cierra: la huerfana sigue publicada y el estudio cree que la
-- borro. Eso es el try/catch de _deleteFixed y va a la Tanda C.
-- ═══════════════════════════════════════════════════════════════════════════

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
       limit 1;

      if v_existente_id is not null then
        v_ocupadas := v_ocupadas + 1; continue;
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
