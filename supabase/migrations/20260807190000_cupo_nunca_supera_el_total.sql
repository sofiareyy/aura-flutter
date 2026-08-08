-- ============================================================================
-- AURA — lugares_disponibles NUNCA puede superar lugares_total (2026-08-07)
-- ============================================================================
--
-- El cupo lo define el estudio con `lugares_total`. `lugares_disponibles` es
-- un derivado y no puede quedar por encima: no puede haber 5 lugares libres en
-- una clase de 4.
--
-- Reemplaza a trg_clases_resync_cupo (20260807180000), que solo actuaba cuando
-- lugares_total cambiaba. Le faltaban dos agujeros:
--   1) un UPDATE que subiera lugares_disponibles sin tocar el total pasaba
--      derecho;
--   2) el INSERT no tenía ninguna protección.
--
-- Ahora hay dos capas:
--   * el trigger CORRIGE (recalcula y acota), en INSERT y en UPDATE;
--   * un CHECK GARANTIZA que el dato inválido no pueda existir.
-- Como el trigger es BEFORE, corrige antes de que el CHECK evalúe: el CHECK es
-- la red de seguridad, no algo que le vaya a explotar al estudio en la cara.

create or replace function public.clases_resync_cupo()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_ocupados int;
  v_total    int := coalesce(new.lugares_total, 0);
begin
  -- Si cambió el cupo total (o es una clase nueva), recalculamos desde las
  -- reservas reales.
  if tg_op = 'INSERT'
     or new.lugares_total is distinct from old.lugares_total then

    select count(*)
      into v_ocupados
      from public.reservas r
     where r.clase_id = new.id
       and coalesce(r.estado, '') not in ('cancelada', 'cancelada_por_estudio');

    new.lugares_disponibles := greatest(0, v_total - coalesce(v_ocupados, 0));
    return new;
  end if;

  -- Si no cambió el total, igual acotamos: disponibles vive en [0, total].
  -- Esto ataja cualquier escritura directa que lo deje fuera de rango, venga
  -- del panel, de un RPC o de una app vieja.
  if new.lugares_disponibles is null then
    new.lugares_disponibles := v_total;
  else
    new.lugares_disponibles := greatest(0, least(new.lugares_disponibles, v_total));
  end if;

  return new;
end;
$$;

drop trigger if exists trg_clases_resync_cupo on public.clases;
create trigger trg_clases_resync_cupo
  before insert or update on public.clases
  for each row execute function public.clases_resync_cupo();


-- ── Sanear las filas viejas antes del CHECK ─────────────────────────────────
-- El resync de 20260807170000 solo tocó clases FUTURAS, así que quedaron
-- clases pasadas con disponibles > total y el CHECK no valida.
--
-- Acá solo se ACOTA al rango válido, no se recalcula desde las reservas: en
-- una clase que ya pasó, el número que quedó registrado es historia y no
-- queremos reescribirlo más de lo necesario.
update public.clases
   set lugares_disponibles = greatest(
         0,
         least(coalesce(lugares_disponibles, 0), coalesce(lugares_total, 0))
       )
 where lugares_disponibles is not null
   and lugares_total is not null
   and (lugares_disponibles > lugares_total or lugares_disponibles < 0);


-- ── El CHECK, como garantía dura ────────────────────────────────────────────
do $$
begin
  alter table public.clases drop constraint if exists clases_cupo_coherente_check;
  alter table public.clases
    add constraint clases_cupo_coherente_check
    check (
      lugares_disponibles is null
      or lugares_total is null
      or (lugares_disponibles >= 0 and lugares_disponibles <= lugares_total)
    );
end $$;


-- ── VERIFICACIÓN (solo lee) ─────────────────────────────────────────────────

-- 1) ¿Queda alguna clase con más disponibles que el cupo? Tiene que dar 0.
select count(*) as clases_con_cupo_invalido
  from public.clases
 where lugares_disponibles is not null
   and lugares_total is not null
   and (lugares_disponibles > lugares_total or lugares_disponibles < 0);

-- 2) El constraint tiene que aparecer.
select conname, pg_get_constraintdef(oid) as definicion
  from pg_constraint
 where conrelid = 'public.clases'::regclass
   and conname = 'clases_cupo_coherente_check';
