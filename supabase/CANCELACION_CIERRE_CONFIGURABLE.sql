-- ============================================================================
-- FIX 1 + FIX 3 — Ventana de cancelacion separada de la de reserva,
--                 configurable por estudio.
-- ============================================================================
--
-- PROBLEMA (FIX 1)
-- `reserva_cierre_minutos` gobernaba DOS reglas distintas a la vez: hasta
-- cuando se puede reservar y hasta cuando se puede cancelar. Ademas la
-- propagacion desde horarios_fijos usaba `coalesce(..., 0)`, asi que la
-- columna quedaba en 0 (= "sin ventana") y nunca en null. El fallback de
-- 720 min del cliente no se disparaba nunca y en la practica se podia
-- cancelar hasta el minuto de inicio con devolucion total de creditos,
-- mientras al usuario se le mostraba una politica de 12 hs.
--
-- SOLUCION (FIX 3)
-- Dos columnas independientes, con cascada clase -> estudio -> default:
--   reserva_cierre_minutos      default estudio 0   (se reserva hasta el inicio)
--   cancelacion_cierre_minutos  default estudio 720 (12 hs)
-- null en la clase = "sin override, usar el default del estudio". Por eso
-- las columnas de `clases` y `horarios_fijos` quedan NULLABLE y SIN default.
--
-- Idempotente: se puede correr mas de una vez.
-- ============================================================================

begin;

-- ── 1. Defaults por estudio ────────────────────────────────────────────────
alter table public.estudios
  add column if not exists reserva_cierre_minutos integer not null default 0;

alter table public.estudios
  add column if not exists cancelacion_cierre_minutos integer not null default 720;

comment on column public.estudios.reserva_cierre_minutos is
  'Minutos antes del inicio en que cierran las reservas. Default 0 = se puede reservar hasta que la clase arranca. Editable por el estudio.';

comment on column public.estudios.cancelacion_cierre_minutos is
  'Minutos antes del inicio en que cierra la cancelacion. Default 720 (12 hs). Cancelar mas tarde consume los creditos. Editable por el estudio.';

-- Guardas de rango: entre 0 y 7 dias. Evita que un typo en el panel
-- (ej. "7200" horas) deje al estudio sin reservas ni cancelaciones.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'estudios_cierres_rango_check'
  ) then
    alter table public.estudios
      add constraint estudios_cierres_rango_check check (
        reserva_cierre_minutos between 0 and 10080
        and cancelacion_cierre_minutos between 0 and 10080
      );
  end if;
end $$;

-- ── 2. Override opcional por clase y por horario fijo ──────────────────────
-- NULLABLE y sin default a proposito: null = heredar del estudio.
alter table public.clases
  add column if not exists cancelacion_cierre_minutos integer;

alter table public.horarios_fijos
  add column if not exists cancelacion_cierre_minutos integer;

comment on column public.clases.cancelacion_cierre_minutos is
  'Override de la ventana de cancelacion para esta clase. null = usar estudios.cancelacion_cierre_minutos.';

comment on column public.horarios_fijos.cancelacion_cierre_minutos is
  'Override de la ventana de cancelacion para este horario fijo. null = usar el default del estudio.';

comment on column public.clases.reserva_cierre_minutos is
  'Override de la ventana de reserva para esta clase. null = usar estudios.reserva_cierre_minutos. OJO: 0 NO es null, 0 significa "se reserva hasta el inicio".';

-- ── 3. Soltar el NOT NULL de reserva_cierre_minutos ────────────────────────
-- Sin esto no se puede expresar "sin override, heredar del estudio". Era la
-- causa de fondo del bug: como null no entraba, se guardaba 0, y 0 significa
-- "sin ventana". Por eso la politica de 12 hs nunca se aplicaba.
alter table public.clases
  alter column reserva_cierre_minutos drop not null;

alter table public.horarios_fijos
  alter column reserva_cierre_minutos drop not null;

-- ── 4. Limpiar el 0 espurio que dejo el coalesce viejo ─────────────────────
-- Los 0 escritos por `coalesce(v_h.reserva_cierre_minutos, 0)` no fueron una
-- decision del estudio: eran el default disfrazado. Los pasamos a null para
-- que hereden. Solo tocamos las filas cuyo horario fijo tampoco tenia valor,
-- para no pisar a un estudio que eligio 0 a proposito.
update public.clases c
   set reserva_cierre_minutos = null
  from public.horarios_fijos h
 where c.horario_fijo_id = h.id
   and c.reserva_cierre_minutos = 0
   and h.reserva_cierre_minutos is null;

update public.clases
   set reserva_cierre_minutos = null
 where reserva_cierre_minutos = 0
   and horario_fijo_id is null;

-- ── 5. Re-emitir generar_clases_estudio propagando las dos columnas ────────
-- Identica a la de PRICING_DINAMICO.sql salvo el bloque de insert: se quita
-- el coalesce(...,0) y se suma cancelacion_cierre_minutos.
create or replace function public.generar_clases_estudio(
  p_estudio_id int,
  p_weeks int default 4
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now          timestamp := (now() at time zone 'America/Argentina/Buenos_Aires');
  v_week_start   date;
  v_week_offset  int;
  v_h            record;
  v_creadas      int := 0;
  v_omitidas     int := 0;
  v_fecha        timestamp;
  v_estudio_cat  text;
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
        -- Sin coalesce a 0: null = heredar del estudio.
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

grant execute on function public.generar_clases_estudio(int, int) to authenticated;

-- ── 6. RPC para que el estudio edite sus dos ventanas ──────────────────────
-- Solo un admin del estudio puede tocarlas. Devuelve los valores guardados.
create or replace function public.set_estudio_cierres(
  p_estudio_id int,
  p_reserva_cierre_minutos int,
  p_cancelacion_cierre_minutos int
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_ok  boolean;
begin
  if v_uid is null then
    return json_build_object('ok', false, 'error', 'No autenticado');
  end if;

  select exists (
    select 1 from public.estudio_admins
     where estudio_id = p_estudio_id
       and usuario_id = v_uid
  ) into v_ok;

  if not v_ok then
    return json_build_object('ok', false, 'error', 'No administras este estudio');
  end if;

  if p_reserva_cierre_minutos is null
     or p_cancelacion_cierre_minutos is null
     or p_reserva_cierre_minutos not between 0 and 10080
     or p_cancelacion_cierre_minutos not between 0 and 10080 then
    return json_build_object('ok', false, 'error', 'Valores fuera de rango (0 a 7 dias)');
  end if;

  update public.estudios
     set reserva_cierre_minutos = p_reserva_cierre_minutos,
         cancelacion_cierre_minutos = p_cancelacion_cierre_minutos
   where id = p_estudio_id;

  return json_build_object(
    'ok', true,
    'reserva_cierre_minutos', p_reserva_cierre_minutos,
    'cancelacion_cierre_minutos', p_cancelacion_cierre_minutos
  );
end;
$$;

grant execute on function public.set_estudio_cierres(int, int, int) to authenticated;

commit;

-- ── VERIFICACION ───────────────────────────────────────────────────────────
-- select id, nombre, reserva_cierre_minutos, cancelacion_cierre_minutos
--   from public.estudios order by nombre;
--
-- Clases que quedaron heredando (deberian ser la mayoria):
-- select count(*) filter (where reserva_cierre_minutos is null)     as hereda_reserva,
--        count(*) filter (where cancelacion_cierre_minutos is null) as hereda_cancelacion,
--        count(*) as total
--   from public.clases where fecha >= now();
