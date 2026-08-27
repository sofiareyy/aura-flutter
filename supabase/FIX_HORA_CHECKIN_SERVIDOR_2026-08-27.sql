-- La hora del check-in la pone el SERVIDOR, no el cliente.
--
-- El bug, encontrado el 27/8 con la reserva #673 (Juanita, el primer cliente
-- real): el panel escribe
--     'checked_in_at': DateTime.now().toIso8601String()
-- y en Dart eso devuelve la hora LOCAL **sin marca de zona**
-- ("2026-08-27T09:09:41.995175", sin Z ni -03:00). Postgres la recibe en una
-- columna `timestamptz` y la interpreta como UTC ⇒ el check-in queda guardado
-- **3 horas antes** de la hora real. Juanita entró 09:09 y figuraba 06:09.
--
-- Afecta a TODOS los estudios y está también en el build 26, así que se
-- arregla en la base: así vale también para la app vieja que los estudios
-- tienen instalada hoy, sin esperar ningún build.
--
-- No toca plata: la liquidación usa `estado` y `creditos_usados`. Lo que
-- arregla es el registro de a qué hora entró cada alumna.

create or replace function public.reservas_sella_checkin()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  -- Sólo la escritura DIRECTA del cliente. Las RPC security definer, el cron
  -- (`completar_reservas_vencidas`) y el service_role corren con otro
  -- `current_user` y pasan sin que les toquemos nada. Mismo patrón que
  -- `reservas_no_marcar_antes_de_tiempo`.
  -- Esto es lo que además permite corregir a mano una fila vieja por SQL sin
  -- que el trigger la re-selle con la hora de hoy.
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    -- Una reserva nace sin check-in. Si el cliente igual manda algo, se sella.
    if new.checked_in_at is not null then
      new.checked_in_at := now();
    end if;
    return new;
  end if;

  if new.checked_in_at is distinct from old.checked_in_at then
    -- Poner en null es "deshacer el check-in": se respeta tal cual.
    if new.checked_in_at is null then
      return new;
    end if;
    new.checked_in_at := now();

  elsif coalesce(new.estado, '') in ('presente', 'ausente')
        and new.estado is distinct from old.estado
        and new.checked_in_at is null then
    -- Marcó asistencia sin mandar la hora: la ponemos igual.
    new.checked_in_at := now();
  end if;

  return new;
end;
$$;

-- El nombre importa: los BEFORE corren por orden alfabético, así que éste va
-- después de `trg_reservas_columnas_sensibles` (que autoriza) y de
-- `trg_reservas_no_marcar_antes` (que frena si es temprano).
drop trigger if exists trg_reservas_sella_checkin on public.reservas;
create trigger trg_reservas_sella_checkin
  before insert or update on public.reservas
  for each row execute function public.reservas_sella_checkin();
