-- ============================================================================
-- AURA — Pico/valle por hora, sin precio promedio (2026-08-07)
-- ============================================================================
--
-- Dos cambios sobre el modo 'rango':
--
-- 1) SE VA EL PRECIO PROMEDIO. Solo hay dos estados:
--        franja marcada como valle  -> creditos_min (horario flojo)
--        todo lo demás              -> creditos_max (horario lleno)
--    Antes, lo no marcado cobraba round((min+max)/2). Ya no existe ese caso:
--    Aura marca los horarios flojos y el resto es pico por definición.
--
-- 2) LAS FRANJAS PASAN A SER DE 1 HORA. Antes eran bloques anchos
--    ('manana_temprano' = 6 a 9, etc.), así que no se podía distinguir las 7
--    de las 8. Ahora cada hora se marca por separado.
--
--    Formato nuevo de estudios.horarios_config:
--        {"valle": [{"dia": 1, "hora": 8}, {"dia": 1, "hora": 19}]}
--        dia  = isodow (1 = lunes ... 7 = domingo)
--        hora = 0..23, la hora en punto
--
--    Solo se guarda `valle`. Guardar también `pico` sería estado duplicado
--    que se puede desincronizar: si no está en valle, es pico. Misma razón por
--    la que no hay columna `archivada` en clases.
--
-- 3) HORARIOS ROTOS: cada clase toma la franja de su hora en punto hacia
--    abajo. 8:30 y 8:45 usan la franja de las 8. 9:15 usa la de las 9.
--    Es un floor de la hora, que es lo que ya hacía `extract(hour from ...)`.
--
-- Ojo: hoy los 9 estudios están en modo 'fijo', así que este cambio no mueve
-- ningún precio en producción. Es preparar el terreno antes de pasar a Sculpt
-- (u otro) a modo rango.

begin;


-- ── 1. Migrar horarios_config al formato por hora ───────────────────────────
--
-- Los bloques anchos viejos se expanden a sus horas:
--     madrugada 0-6 | manana_temprano 6-9 | manana 9-12 | mediodia 12-15
--     tarde 15-18   | tarde_noche 18-21   | noche 21-24
--
-- Solo se conserva `valle`. Las entradas viejas de `pico` se descartan a
-- propósito: bajo las reglas nuevas "no marcado" ya significa pico, así que
-- arrastrarlas sería redundante (y Citra tiene 42 bloques pico heredados que
-- no queremos reactivar por la ventana de atrás).

update public.estudios e
   set horarios_config = jsonb_build_object(
     'valle',
     coalesce((
       select jsonb_agg(distinct jsonb_build_object('dia', d.dia, 'hora', h.hora))
         from jsonb_array_elements(
                coalesce(e.horarios_config -> 'valle', '[]'::jsonb)
              ) as elem
        cross join lateral (
                select (elem ->> 'dia')::int as dia
              ) d
        cross join lateral (
                select generate_series(lo, hi - 1) as hora
                  from (
                    select case elem ->> 'rango'
                             when 'madrugada'       then 0
                             when 'manana_temprano' then 6
                             when 'manana'          then 9
                             when 'mediodia'        then 12
                             when 'tarde'           then 15
                             when 'tarde_noche'     then 18
                             when 'noche'           then 21
                           end as lo,
                           case elem ->> 'rango'
                             when 'madrugada'       then 6
                             when 'manana_temprano' then 9
                             when 'manana'          then 12
                             when 'mediodia'        then 15
                             when 'tarde'           then 18
                             when 'tarde_noche'     then 21
                             when 'noche'           then 24
                           end as hi
                  ) lim
                 where lo is not null
              ) h
        where d.dia between 1 and 7
     ), '[]'::jsonb)
   )
 where e.horarios_config is not null
   and jsonb_array_length(coalesce(e.horarios_config -> 'valle', '[]'::jsonb)) > 0;

-- Estudios sin valle cargado: normalizamos al formato nuevo, vacío.
update public.estudios
   set horarios_config = '{"valle": []}'::jsonb
 where horarios_config is null
    or jsonb_array_length(coalesce(horarios_config -> 'valle', '[]'::jsonb)) = 0;


-- ── 2. calcular_precio_clase v5 ─────────────────────────────────────────────
--
-- Misma firma que la v4 (bigint, text, int, text). Cambia solo el modo rango:
-- desaparece el promedio y la franja pasa a ser la hora en punto.

create or replace function public.calcular_precio_clase(
  p_estudio_id bigint,
  p_categoria  text,
  p_dia        int,
  p_hora       text
) returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tipo_estudio text;
  v_modo         text;
  v_min          int;
  v_max          int;
  v_config       jsonb;
  v_horarios     jsonb;
  v_hora         int;
  v_es_valle     boolean := false;
begin
  select coalesce(e.tipo_estudio, 'fitness'),
         coalesce(e.tipo_precio, 'fijo'),
         e.creditos_min, e.creditos_max, e.precio_config, e.horarios_config
    into v_tipo_estudio, v_modo, v_min, v_max, v_config, v_horarios
    from public.estudios e
   where e.id = p_estudio_id;

  if not found then
    return json_build_object('creditos', null, 'tipo', 'normal', 'ok', false);
  end if;

  v_min := coalesce(v_min, (nullif(v_config ->> 'min', '')::numeric)::int);
  v_max := coalesce(v_max, (nullif(v_config ->> 'max', '')::numeric)::int, v_min);

  if v_min is null then
    return json_build_object('creditos', null, 'tipo', 'normal', 'ok', false);
  end if;
  if v_max is null or v_max < v_min then
    v_max := v_min;
  end if;

  if v_tipo_estudio = 'experiencia' then
    return json_build_object('creditos', v_min, 'tipo', 'experiencia', 'ok', true);
  end if;

  -- MODO FIJO: un único precio, sin importar el horario.
  if v_modo <> 'rango' then
    return json_build_object('creditos', v_min, 'tipo', 'normal', 'ok', true);
  end if;

  -- MODO RANGO.
  -- Hora en punto hacia abajo: '8:30' y '8:45' caen en la franja 8; '9:15' en
  -- la 9. split_part sobre ':' ya descarta los minutos, que es el floor.
  v_hora := coalesce(
    nullif(split_part(coalesce(p_hora, '08:00'), ':', 1), '')::int,
    8
  );
  if v_hora < 0 or v_hora > 23 then
    v_hora := 8;
  end if;

  select exists (
           select 1
             from jsonb_array_elements(
                    coalesce(v_horarios -> 'valle', '[]'::jsonb)
                  ) as elem
            where (elem ->> 'dia')::int  = p_dia
              and (elem ->> 'hora')::int = v_hora
         )
    into v_es_valle;

  if v_es_valle then
    return json_build_object('creditos', v_min, 'tipo', 'valle', 'ok', true);
  end if;

  -- Todo lo no marcado es pico. Ya no existe el promedio.
  return json_build_object('creditos', v_max, 'tipo', 'pico', 'ok', true);
end;
$$;

grant execute on function public.calcular_precio_clase(bigint, text, int, text)
  to authenticated, service_role;


-- ── 3. Recalcular lo ya cargado con las reglas nuevas ───────────────────────
-- Corre como dueño de la migración, así que los triggers de precio no
-- interfieren (solo actúan sobre escrituras del cliente).

update public.clases c
   set creditos    = (calc.res ->> 'creditos')::int,
       tipo_precio = calc.res ->> 'tipo'
  from (
    select id,
           public.calcular_precio_clase(
             estudio_id, null,
             extract(isodow from fecha)::int,
             to_char(fecha, 'HH24:MI')
           ) as res
      from public.clases
     where coalesce(tipo, 'clase') <> 'workshop'
  ) calc
 where c.id = calc.id
   and coalesce((calc.res ->> 'ok')::boolean, false);

update public.horarios_fijos h
   set creditos = (calc.res ->> 'creditos')::int
  from (
    select id,
           public.calcular_precio_clase(
             estudio_id, null, dia_semana, to_char(hora_inicio, 'HH24:MI')
           ) as res
      from public.horarios_fijos
  ) calc
 where h.id = calc.id
   and coalesce(to_jsonb(h) ->> 'tipo', 'clase') <> 'workshop'
   and coalesce((calc.res ->> 'ok')::boolean, false);


commit;


-- ── VERIFICACIÓN (solo lee) ─────────────────────────────────────────────────

-- 1) Formato nuevo de horarios_config por estudio.
select id,
       nombre,
       tipo_precio,
       creditos_min,
       creditos_max,
       jsonb_array_length(coalesce(horarios_config -> 'valle', '[]'::jsonb))
         as franjas_valle,
       horarios_config
  from public.estudios
 where activo = true
 order by nombre;

-- 2) Ninguna clase debería quedar en tipo_precio 'normal' si su estudio está
--    en modo rango (ya no existe el promedio). Debe dar 0 filas.
select c.id, e.nombre as estudio, c.fecha, c.creditos, c.tipo_precio
  from public.clases c
  join public.estudios e on e.id = c.estudio_id
 where e.tipo_precio = 'rango'
   and coalesce(c.tipo, 'clase') <> 'workshop'
   and c.tipo_precio = 'normal'
 order by e.nombre, c.fecha;

-- 3) Prueba de la regla de horarios rotos: 8:30 tiene que resolver igual
--    que 8:00, y distinto de 9:00 si esa franja está marcada distinto.
--    Cambiá el id por un estudio en modo rango para probarlo de verdad.
-- select public.calcular_precio_clase(9, null, 1, '08:00') as h8,
--        public.calcular_precio_clase(9, null, 1, '08:30') as h8_30,
--        public.calcular_precio_clase(9, null, 1, '08:45') as h8_45,
--        public.calcular_precio_clase(9, null, 1, '09:15') as h9_15;
