-- ═══════════════════════════════════════════════════════════════════════════
-- FIX · no se puede cargar dos veces el mismo horario fijo
-- 2026-08-25
--
-- EL CASO (Tiwar Fitness, 25/8)
-- El formulario de grilla es un RANGO (Desde / Hasta / duracion) y genera un
-- horario fijo por franja. El estudio lo mando dos veces con 46 s de
-- diferencia --08:30→21:30 y 09:30→22:30-- y quedaron 130 grillas para 70
-- slots: 60 slots con dos filas identicas. Como `generar_clases_estudio`
-- acota el chequeo de existencia por `horario_fijo_id`, cada grilla genero
-- su propia serie: 1158 clases, 534 de mas. El generador es inocente
-- (medido: idempotente en 3 corridas); la duplicacion entra entera por
-- las grillas repetidas.
--
-- No habia NADA que lo impidiera: `horarios_fijos` solo tiene la PK por id.
--
-- POR QUE UN TRIGGER Y NO (TODAVIA) UN INDICE UNICO
-- Postgres rechaza `create unique index` mientras existan duplicados, y hoy
-- existen: los 60 de Tiwar (esperan que el estudio confirme que horarios
-- quiere de verdad) y 1 en Yessi Funes (mie 18:00, dos grillas DISTINTAS:
-- Fumcional/Natalia y Funcional/Tomas -- decision del estudio). El trigger da
-- la misma proteccion desde hoy sin depender de esa limpieza. El indice
-- unico `(estudio_id, dia_semana, hora_inicio)` va en la migracion que
-- limpie Tiwar; este trigger queda igual como capa del mensaje legible.
--
-- POR QUE RECHAZA EN VEZ DE SALTEAR EN SILENCIO
-- El Dart hace `insert(rows)` en un solo lote y muestra `rows.length` como
-- "creados". Saltear en silencio dejaria un lote a medias con un cartel que
-- miente. Rechazar deja el lote entero afuera con un mensaje que dice QUE
-- slot choca, y es exactamente lo que va a hacer el indice unico despues
-- (23505), asi que el comportamiento no cambia al agregarlo.
--
-- Sin guarda de current_user: un horario fijo duplicado no es legitimo para
-- nadie, ni backoffice ni cron (ninguno inserta grillas).
--
-- La unicidad es por (estudio, dia, hora): dos estudios distintos pueden
-- tener el mismo slot, y un mismo estudio puede tener 08:30 y 09:30.
-- `activo` no entra: reactivar se hace editando la fila, no creando otra.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.horarios_fijos_sin_duplicados()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
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
       and h.id is distinct from new.id
  ) then
    raise exception
      'Ya tenés un horario fijo el % a las %. Si querés cambiarlo, editá ese en vez de crear otro.',
      coalesce(v_dias[new.dia_semana], 'día '||new.dia_semana),
      to_char(new.hora_inicio, 'HH24:MI')
      using errcode = 'unique_violation';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_horarios_fijos_00_sin_duplicados on public.horarios_fijos;

-- El "00" en el nombre lo hace correr antes que fija_precio y sync_categorias
-- (los BEFORE de una misma tabla corren en orden alfabetico): si va a fallar,
-- que falle antes de calcular nada.
create trigger trg_horarios_fijos_00_sin_duplicados
  before insert or update on public.horarios_fijos
  for each row execute function public.horarios_fijos_sin_duplicados();
