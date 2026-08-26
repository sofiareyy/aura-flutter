-- ═══════════════════════════════════════════════════════════════════════════
-- Tiwar Fitness: reset de la grilla + INDICE UNICO de horarios
-- 2026-08-26 · confirmado por la usuaria con los numeros a la vista
--
-- POR QUE UN RESET Y NO UN DEDUPE
-- Tiwar tenia 130 grillas para 70 slots (60 duplicados) por mandar el
-- formulario de rango dos veces el 25/8. Pero ademas los horarios cargados
-- NO son los que dicta: tenia una clase por hora de 08:30 a 21:30 L-V,
-- incluyendo 16:30 que era "Open Box" (no va a Aura) y toda la franja
-- 10:30-14:30 que no existe. Y le faltaba el sabado. Asi que no alcanzaba
-- con deduplicar: se borra todo y se carga lo real.
--
-- LO REAL (confirmado por el estudio):
--   L a V : 08:30, 09:30, 15:30, 17:30, 18:30, 19:30, 20:30   (7 × 5 = 35)
--   Sabado: 11:30, 12:30                                       (2)
--   Domingo: cerrado
--   = 37 horarios fijos. Nombre "Cross / Funct / Hyrox", sin instructor,
--   cupo 12 de arranque (Tiwar lo ajusta desde su panel).
--
-- SEGURIDAD: Tiwar tiene 0 reservas en cualquier estado (medido). El bloque
-- aborta si aparece alguna. Las clases se borran PRIMERO y explicitamente:
-- `clases.horario_fijo_id` es ON DELETE SET NULL, no CASCADE, asi que borrar
-- solo las grillas dejaria las clases huerfanas y publicadas (aprendido al
-- limpiar Yessi el 25/8).
--
-- ⚠️ PRECIOS: quedan segun la config de franjas ACTUAL de Tiwar
-- (valle = horas 8, 9, 19, 20), o sea 08:30/09:30/19:30/20:30 a 11cr y
-- 15:30/17:30/18:30 + sabado a 14cr. Se le hizo notar a la usuaria que esa
-- config parece invertida para un box (8-9 y 19-20 suelen ser las horas
-- pico). Si se cambia, `admin_set_pricing_estudio` recalcula las clases
-- futuras solo: NO hay que recargar la grilla.
--
-- EL INDICE UNICO va al final, cuando ya no quedan duplicados en ninguna
-- parte de la base. Es la red definitiva: el trigger
-- `trg_horarios_fijos_00_sin_duplicados` (25/8) da el mensaje legible, el
-- indice garantiza que ni un bug ni un acceso directo puedan crear dos
-- horarios en el mismo (estudio, dia, hora, sala).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. LIMPIAR ────────────────────────────────────────────────────────────
do $$
declare v_res int; v_c int; v_h int;
begin
  select count(*) into v_res
    from public.reservas r join public.clases c on c.id = r.clase_id
   where c.estudio_id = 17;
  if v_res <> 0 then
    raise exception 'ABORT: Tiwar tiene % reservas, revisar a mano', v_res;
  end if;
  if not exists (select 1 from public.estudios where id = 17 and nombre = 'Tiwar Fitness') then
    raise exception 'ABORT: el estudio 17 no es Tiwar Fitness';
  end if;

  delete from public.clases         where estudio_id = 17;  get diagnostics v_c = row_count;
  delete from public.horarios_fijos where estudio_id = 17;  get diagnostics v_h = row_count;
  raise notice 'borradas % clases y % grillas', v_c, v_h;
end $$;

-- ── 2. CARGAR ─────────────────────────────────────────────────────────────
-- Como `postgres` el trigger de precio sale temprano (guarda de current_user),
-- asi que el precio de cada horario se calcula explicitamente con la MISMA
-- funcion que usa el trigger. Se verifica despues que no haya desvios.
insert into public.horarios_fijos
  (estudio_id, nombre, instructor, dia_semana, hora_inicio, duracion_min, lugares_total, activo, creditos)
select 17, 'Cross / Funct / Hyrox', null, d, h::time, 60, 12, true,
       (public.calcular_precio_clase(17, null, d, h) ->> 'creditos')::int
  from generate_series(1, 5) d,
       unnest(array['08:30','09:30','15:30','17:30','18:30','19:30','20:30']) h
union all
select 17, 'Cross / Funct / Hyrox', null, 6, h::time, 60, 12, true,
       (public.calcular_precio_clase(17, null, 6, h) ->> 'creditos')::int
  from unnest(array['11:30','12:30']) h;

select public.generar_clases_estudio(17, 9) as generacion;

-- ── 3. INDICE UNICO ───────────────────────────────────────────────────────
-- Incluye la sala (normalizada) con el mismo criterio del trigger del 25/8:
-- dos salones pueden dictar al mismo minuto, el mismo salon dos veces no.
create unique index if not exists horarios_fijos_slot_uidx
  on public.horarios_fijos (estudio_id, dia_semana, hora_inicio, (lower(trim(coalesce(sala, '')))));
