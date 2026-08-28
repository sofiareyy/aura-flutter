-- Item 17 · `estudio_vistas` tenía INSERT con `with check (true)` para
-- authenticated: cualquier logueada podía insertar vistas sin límite y con
-- CUALQUIER usuario_id. anon nunca pudo insertar y eso no cambia.
--
-- Regla nueva: la vista es TUYA (usuario_id = auth.uid()) y como mucho UNA
-- por estudio por hora.
--
-- ⚠️ El dedup NO puede ser un `not exists` directo en el with_check: esa
-- subconsulta corre bajo la RLS del caller, y `estudio_vistas` no tiene
-- policy de SELECT ⇒ la subconsulta veía 0 filas y dejaba pasar TODO
-- (medido el 29/8 en la primera versión de este fix). Por eso el chequeo
-- vive en un helper SECURITY DEFINER, que ve la tabla de verdad.

create or replace function public.vista_reciente(p_estudio_id integer)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from public.estudio_vistas v
     where v.usuario_id = auth.uid()
       and v.estudio_id = p_estudio_id
       and v.fecha > now() - interval '1 hour'
  );
$$;

revoke execute on function public.vista_reciente(integer) from public, anon;
grant  execute on function public.vista_reciente(integer) to authenticated, service_role;

drop policy if exists estudio_vistas_insert on public.estudio_vistas;
create policy estudio_vistas_insert on public.estudio_vistas
  for insert to authenticated
  with check (
    usuario_id = auth.uid()
    and not public.vista_reciente(estudio_id)
  );
