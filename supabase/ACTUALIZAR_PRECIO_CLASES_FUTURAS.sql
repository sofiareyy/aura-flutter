-- AURA - Propagar cambios de precio del estudio a las clases futuras (2026-07-11).
--
-- Cuando el backoffice cambia el precio de un estudio (fijo o min/max), puede
-- actualizar los créditos de todas las clases FUTURAS (fecha >= hoy AR). No
-- toca clases pasadas ni workshops (que tienen precio libre). También sincroniza
-- los horarios_fijos para que las próximas generaciones usen el nuevo precio.

-- Cuenta las clases futuras (no workshops) de un estudio.
create or replace function public.admin_contar_clases_futuras(p_estudio_id int)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
  v_hoy   date := (timezone('America/Argentina/Buenos_Aires', now()))::date;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  select count(*)
    into v_count
    from public.clases
   where estudio_id = p_estudio_id
     and coalesce(tipo, 'clase') <> 'workshop'
     and (fecha)::timestamp >= (v_hoy)::timestamp;

  return coalesce(v_count, 0);
end;
$$;

grant execute on function public.admin_contar_clases_futuras(int)
  to authenticated, service_role;

-- Setea los créditos de las clases futuras (no workshops) + horarios fijos.
create or replace function public.admin_set_precio_clases_futuras(
  p_estudio_id int,
  p_creditos   int
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int := 0;
  v_hoy   date := (timezone('America/Argentina/Buenos_Aires', now()))::date;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  if p_creditos is null then
    return 0;
  end if;

  update public.clases
     set creditos = p_creditos
   where estudio_id = p_estudio_id
     and coalesce(tipo, 'clase') <> 'workshop'
     and (fecha)::timestamp >= (v_hoy)::timestamp;

  get diagnostics v_count = row_count;

  -- Que las futuras generaciones desde horarios fijos también usen el precio.
  update public.horarios_fijos
     set creditos = p_creditos
   where estudio_id = p_estudio_id;

  return v_count;
end;
$$;

grant execute on function public.admin_set_precio_clases_futuras(int, int)
  to authenticated, service_role;
