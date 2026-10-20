-- La grilla de EQUMM (estudio 61). APLICADO EN PRODUCCIÓN el 2026-10-19.
--
-- ORDEN IMPORTANTE: primero la configuración de precios, después los
-- horarios. El precio de cada horario NO se escribe a mano: lo pone el
-- trigger `horarios_fijos_fija_precio` leyendo `horarios_config` del estudio.
-- Si los horarios se cargaran antes, saldrían todos a `creditos_max`.

-- 1. Fitness, para "Entrenamiento funcional". Sólo tenía {Pilates}, así que
--    esa clase no tenía dónde ir y habría quedado catalogada como Pilates.
update public.estudios
   set categorias = array['Pilates', 'Fitness']
 where id = 61;

-- 2. Las franjas de 11 créditos. La regla es "valle cobra creditos_min (11),
--    todo lo demás creditos_max (14)", y `horarios_config` estaba VACÍO: sin
--    esto las 15 clases salían a 14. Es el mismo agujero por el que Rock
--    declara 16–18 y cobra 16 en todo.
--    isodow: 1=lun … 7=dom.
update public.estudios
   set horarios_config = jsonb_build_object('pico', '[]'::jsonb, 'valle', jsonb_build_array(
         jsonb_build_object('dia', 2, 'hora', 12),   -- mar 12:00
         jsonb_build_object('dia', 4, 'hora', 12),   -- jue 12:00
         jsonb_build_object('dia', 2, 'hora', 17),   -- mar 17:00
         jsonb_build_object('dia', 4, 'hora', 17),   -- jue 17:00
         jsonb_build_object('dia', 5, 'hora', 17)))  -- vie 17:00
 where id = 61;

-- 3. La gracia. Vencía el 16/10 pero el estudio no dio ni una clase: recién
--    ahora se le carga la grilla. Dos meses desde hoy.
update public.estudios
   set fecha_inicio_cobro = (now() at time zone 'America/Argentina/Buenos_Aires')::date
                            + interval '2 months'
 where id = 61;

-- 4. Los 15 horarios. `creditos` NO se pasa: lo calcula el trigger.
--    Duración 60 min: la grilla es por hora en punto y hay dos slots
--    consecutivos el martes (17 y 18), así que 60 cierra exacto.
insert into public.horarios_fijos
  (estudio_id, nombre, dia_semana, hora_inicio, duracion_min, lugares_total,
   categoria, categorias, descripcion, activo)
values
  (61, 'Reformer',                3, '08:00', 60, 1, 'Pilates', array['Pilates'], 'Pilates reformer. Intensidad baja a media.', true),
  (61, 'Reformer + Funcional',    1, '09:00', 60, 1, 'Pilates', array['Pilates'], 'Pilates reformer con trabajo funcional. Intensidad media a alta.', true),
  (61, 'Reformer + Funcional',    3, '09:00', 60, 1, 'Pilates', array['Pilates'], 'Pilates reformer con trabajo funcional. Intensidad media a alta.', true),
  (61, 'Reformer',                5, '10:00', 60, 1, 'Pilates', array['Pilates'], 'Pilates reformer. Intensidad baja a media.', true),
  (61, 'Reformer',                3, '11:00', 60, 1, 'Pilates', array['Pilates'], 'Pilates reformer. Intensidad baja a media.', true),
  (61, 'Reformer',                4, '11:00', 60, 1, 'Pilates', array['Pilates'], 'Pilates reformer. Intensidad baja a media.', true),
  (61, 'Reformer',                6, '11:00', 60, 1, 'Pilates', array['Pilates'], 'Pilates reformer. Intensidad baja a media.', true),
  (61, 'Reformer',                2, '12:00', 60, 2, 'Pilates', array['Pilates'], 'Pilates reformer. Intensidad baja a media.', true),
  (61, 'Reformer',                4, '12:00', 60, 2, 'Pilates', array['Pilates'], 'Pilates reformer. Intensidad baja a media.', true),
  (61, 'Reformer',                2, '17:00', 60, 2, 'Pilates', array['Pilates'], 'Pilates reformer. Intensidad baja a media.', true),
  (61, 'Reformer',                4, '17:00', 60, 2, 'Pilates', array['Pilates'], 'Pilates reformer. Intensidad baja a media.', true),
  (61, 'Reformer + Funcional',    5, '17:00', 60, 2, 'Pilates', array['Pilates'], 'Pilates reformer con trabajo funcional. Intensidad media a alta.', true),
  (61, 'Reformer',                2, '18:00', 60, 3, 'Pilates', array['Pilates'], 'Pilates reformer. Intensidad baja a media.', true),
  (61, 'Reformer',                1, '20:00', 60, 2, 'Pilates', array['Pilates'], 'Pilates reformer. Intensidad baja a media.', true),
  (61, 'Entrenamiento funcional', 4, '20:00', 60, 3, 'Fitness', array['Fitness'], 'Entrenamiento funcional. Intensidad media a alta.', true);
