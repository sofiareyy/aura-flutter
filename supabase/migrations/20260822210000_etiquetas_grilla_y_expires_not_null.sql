-- ============================================================================
-- AURA — Las clases generadas nacian mal etiquetadas
-- ============================================================================
-- (2026-08-22) Tanda A, items 2 y 6 (etiquetas + expires_at NOT NULL).
--
-- ── PARTE 1: la etiqueta de precio en la grilla generada ───────────────────
--
-- EL BUG
-- `generar_clases_estudio` hacia:
--     if coalesce(v_h.creditos, 0) > 0 then
--       v_creditos := v_h.creditos;
--       v_tipo := 'normal';          <-- HARDCODEADO
--
-- Y como `trg_horarios_fijos_fija_precio` SIEMPRE le pone precio al horario
-- fijo, esa rama corria SIEMPRE. O sea que toda clase generada por la grilla
-- nacia con `tipo_precio = 'normal'`, sin importar su franja.
--
-- En un estudio en modo rango eso significa que una clase de franja valle
-- salia diciendo 'normal'. Y el badge de Explorar muestra "PRECIO REDUCIDO"
-- para 'normal' y 'valle', asi que las clases PICO de Sculpt se anunciaban
-- como precio reducido. El precio cobrado siempre estuvo bien; lo unico
-- desincronizado era la etiqueta.
--
-- Por que no alcanzaba con copiarla: `horarios_fijos` NO TIENE columna
-- `tipo_precio`. No hay de donde copiar; hay que calcularla.
--
-- EL ARREGLO
-- El calculo de la regla sale fuera del `if`. La ETIQUETA siempre viene de
-- `calcular_precio_clase`; el PRECIO sigue saliendo del horario fijo cuando lo
-- tiene, que era la intencion de D3 (migracion 20260722110000).
--
-- ORDEN CRITICO: primero la funcion, DESPUES el backfill. Al reves, el cron
-- `regenerar-grillas-diario` de las 03:00 las repone esa misma noche.
--
-- VERIFICADO
--   * antes: 72 clases desincronizadas (64 futuras), todas de Sculpt
--   * el backfill cambio exactamente esas 72: 54 -> valle, 18 -> pico
--   * ningun otro estudio se movio (los 8 en modo fijo ya estaban bien)
--   * `creditos` NO se toco: suma 13438 antes y despues, rango 11-18 igual
--   * quedan 0 desincronizadas
--   * simulando el cron con rollback: genero 41 clases nuevas y 0 salieron mal
--     etiquetadas. Antes del arreglo habrian salido las 41 como 'normal'.
--
-- ── PARTE 2: expires_at NOT NULL ────────────────────────────────────────────
--
-- Contraparte del arreglo de `admin_adjust_user_credits` (20260822180000).
-- Aquel cerro la funcion que creaba creditos eternos; esto cierra la tabla,
-- para que no vuelvan por ningun otro camino. `grant_user_credits` todavia
-- acepta un vencimiento nulo si alguien se lo pasa: ahora la base lo rechaza.
--
-- Se relevo TODO lo que escribe en creditos_movimientos antes de aplicar:
--   * solo DOS funciones insertan: grant_user_credits y admin_adjust_user_credits
--   * los 9 llamadores de grant_user_credits pasan vencimiento explicito
--   * el Dart solo LEE (home_screen, referidos_service usan .select)
--   * delete-account solo BORRA
--   * el `grant_user_credits(..., null, ...)` que aparecia en reservar_clase
--     esta DENTRO DE UN COMENTARIO que documenta el bug viejo. Falso positivo.
--
-- Verificado con rollback las dos puntas: insert sin vencimiento rechazado,
-- grant_user_credits con vencimiento sigue andando, sin vencimiento ahora
-- falla, y el credito manual con sus 90 dias entra bien.
-- ============================================================================

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

  return json_build_object('creadas', v_creadas, 'omitidas', v_omitidas);
end;
$function$
;

-- ── Backfill de las 72 etiquetas (DESPUES de la funcion) ─────────────────
-- Solo la ETIQUETA. `creditos` no se toca: el precio ya estaba bien, lo unico
-- desincronizado era el label.
update public.clases c
   set tipo_precio = calc.tipo
  from (
    select id,
           (public.calcular_precio_clase(
              estudio_id, null,
              extract(isodow from fecha)::int,
              to_char(fecha, 'HH24:MI')
            ) ->> 'tipo') as tipo
      from public.clases
     where coalesce(tipo, 'clase') <> 'workshop'
  ) calc
 where c.id = calc.id
   and calc.tipo is not null
   and c.tipo_precio is distinct from calc.tipo;

-- ── expires_at NOT NULL ──────────────────────────────────────────────────
alter table public.creditos_movimientos alter column expires_at set not null;

comment on column public.creditos_movimientos.expires_at is
  'Vencimiento del lote de creditos. NOT NULL desde 2026-08-22: un credito sin vencimiento no vence nunca y queda como deuda abierta. Si hace falta uno de muy larga vida, poner una fecha lejana, no null.';
