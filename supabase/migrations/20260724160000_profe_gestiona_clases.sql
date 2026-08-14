-- ============================================================================
-- Opción A: la profe puede CREAR y EDITAR clases (no borrar, no precio libre)
-- ============================================================================
--
-- Hasta ahora la profe solo veía Mis Clases y Asistencia; no podía tocar clases
-- (endurecido en D1/D2). Se abre para que pueda armar su agenda:
--   - INSERT y UPDATE de clases de su estudio  -> SÍ
--   - DELETE                                    -> NO (sigue solo admin/dueña)
--   - Workshops (precio libre en pesos)         -> NO (solo admin/dueña)
--
-- El precio de una clase normal no lo "elige" la profe: lo deriva el sistema
-- del horario (pico/normal/valle) según la config del estudio, y el form se lo
-- muestra read-only. Por eso NO validamos un rango fijo acá (el precio dinámico
-- cae fuera de [min,max] a propósito: valle = min*0.9, pico = max*mult). El
-- único vector de precio MANUAL es el workshop (pesos a mano), y ese lo
-- bloqueamos server-side para la profe.
-- ============================================================================

-- ── RLS: sumar 'profe' a INSERT y UPDATE (DELETE queda igual, sin profe) ─────
drop policy if exists "estudio inserta sus clases" on public.clases;
create policy "estudio inserta sus clases"
  on public.clases for insert
  to authenticated
  with check (
    exists (
      select 1 from public.estudio_admins ea
       where ea.estudio_id = clases.estudio_id
         and ea.usuario_id = auth.uid()
         and ea.rol in ('estudio', 'admin_estudio', 'profe')
    )
  );

drop policy if exists "estudio actualiza sus clases" on public.clases;
create policy "estudio actualiza sus clases"
  on public.clases for update
  to authenticated
  using (
    exists (
      select 1 from public.estudio_admins ea
       where ea.estudio_id = clases.estudio_id
         and ea.usuario_id = auth.uid()
         and ea.rol in ('estudio', 'admin_estudio', 'profe')
    )
  )
  with check (
    exists (
      select 1 from public.estudio_admins ea
       where ea.estudio_id = clases.estudio_id
         and ea.usuario_id = auth.uid()
         and ea.rol in ('estudio', 'admin_estudio', 'profe')
    )
  );

-- DELETE: NO se toca. La policy "estudio elimina sus clases" sigue exigiendo
-- rol in ('estudio','admin_estudio'), así que la profe no puede borrar.


-- Helper SECURITY DEFINER para leer el rol del caller en un estudio saltando la
-- RLS de estudio_admins. auth.uid() dentro de un definer sigue devolviendo al
-- caller real (viene del JWT), así que la lectura es correcta y no depende de
-- que la policy de self-read siga siendo permisiva.
create or replace function public.rol_en_estudio(p_estudio_id int)
returns text
language sql
security definer
stable
set search_path = public
as $$
  select rol
    from public.estudio_admins
   where estudio_id = p_estudio_id
     and usuario_id = auth.uid()
   limit 1;
$$;

revoke execute on function public.rol_en_estudio(int) from public, anon;
grant execute on function public.rol_en_estudio(int) to authenticated;


-- ── Trigger: la profe no puede crear ni editar workshops ────────────────────
-- SECURITY INVOKER: current_user refleja quién ejecutó el statement. Solo
-- aplica a escrituras directas del cliente (authenticated/anon); los RPC y el
-- backend (postgres/service_role) pasan derecho. El rol lo resuelve el helper
-- definer (rol_en_estudio) para no depender de la RLS de estudio_admins.
create or replace function public.clases_gate_profe()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_rol text;
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  v_rol := public.rol_en_estudio(new.estudio_id);

  -- Solo restringimos a la profe. Admin/dueña sin cambios.
  if v_rol is distinct from 'profe' then
    return new;
  end if;

  if coalesce(new.tipo, 'clase') = 'workshop' then
    raise exception 'Una profe no puede crear ni editar workshops. Pedíselo a un administrador del estudio.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_clases_gate_profe on public.clases;
create trigger trg_clases_gate_profe
  before insert or update on public.clases
  for each row execute function public.clases_gate_profe();
