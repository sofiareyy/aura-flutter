-- ============================================================================
-- AURA — El cupo se resincroniza solo al cambiar lugares_total (2026-08-07)
-- ============================================================================
--
-- Causa del desfasaje que corrigió 20260807170000: al editar una clase, el
-- panel manda `lugares_total` pero solo toca `lugares_disponibles` cuando el
-- total es 0. Bajar el cupo de 12 a 4 dejaba disponibles en 12, y la clase
-- aceptaba 12 reservas para 4 lugares.
--
-- Se resuelve en la base en vez de en Flutter a propósito: así queda cubierto
-- cualquier camino de escritura (panel, grilla, RPC, una app vieja ya
-- instalada) sin depender de que se actualice la app.
--
-- Solo actúa cuando lugares_total CAMBIA. Las reservas normales mueven
-- lugares_disponibles sin tocar el total, así que este trigger no interfiere
-- con apply_reservation ni con las cancelaciones.

create or replace function public.clases_resync_cupo()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_ocupados int;
begin
  -- Nada que hacer si el cupo total no cambió.
  if tg_op = 'UPDATE'
     and new.lugares_total is not distinct from old.lugares_total then
    return new;
  end if;

  select count(*)
    into v_ocupados
    from public.reservas r
   where r.clase_id = new.id
     and coalesce(r.estado, '') not in ('cancelada', 'cancelada_por_estudio');

  new.lugares_disponibles := greatest(
    0,
    coalesce(new.lugares_total, 0) - coalesce(v_ocupados, 0)
  );

  return new;
end;
$$;

-- Solo UPDATE: en el INSERT la clase todavía no tiene id ni reservas, y el
-- alta ya setea lugares_disponibles = lugares_total.
drop trigger if exists trg_clases_resync_cupo on public.clases;
create trigger trg_clases_resync_cupo
  before update on public.clases
  for each row execute function public.clases_resync_cupo();


-- ── VERIFICACIÓN ────────────────────────────────────────────────────────────
-- El trigger tiene que aparecer en la lista.
select tgname as trigger, pg_get_triggerdef(oid) as definicion
  from pg_trigger
 where tgrelid = 'public.clases'::regclass
   and not tgisinternal
 order by tgname;
