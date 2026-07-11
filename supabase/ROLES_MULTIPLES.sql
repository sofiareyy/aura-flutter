-- AURA - Roles multiples por usuario (2026-07-11).
--
-- Un usuario puede ser admin_estudio de un estudio y profe de otro al mismo
-- tiempo (ya se soportaba en estudio_admins.rol). El "rol activo" que usa el
-- ruteo es el del estudio activo (usuarios.estudio_id): al elegir/cambiar de
-- estudio, sincronizamos usuarios.rol con el rol de ESE estudio.

-- 1. list_my_studios ahora devuelve el rol por estudio ---------------------
drop function if exists public.list_my_studios();

create or replace function public.list_my_studios()
returns table (
  estudio_id int,
  nombre     text,
  foto_url   text,
  is_active  boolean,
  rol        text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_active int;
begin
  if v_uid is null then
    return;
  end if;

  select estudio_id into v_active
    from public.usuarios where id = v_uid;

  return query
    select e.id,
           e.nombre,
           e.foto_url,
           (e.id = v_active),
           ea.rol
      from public.estudio_admins ea
      join public.estudios e on e.id = ea.estudio_id
     where ea.usuario_id = v_uid
     order by e.nombre;
end;
$$;

grant execute on function public.list_my_studios() to authenticated;


-- 2. set_active_estudio sincroniza el rol global con el rol del estudio -----
-- Devuelve boolean (true = ok) para evitar literales de texto que se corrompen
-- al copiar/pegar. El superadmin de Aura se identifica por admin_users (no por
-- usuarios.rol), asi que sincronizar el rol aca no afecta el acceso al backoffice.
drop function if exists public.set_active_estudio(int);

create or replace function public.set_active_estudio(
  p_estudio_id int
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_rol text;
begin
  if v_uid is null then
    return false;
  end if;

  select rol into v_rol
    from public.estudio_admins
   where estudio_id = p_estudio_id
     and usuario_id = v_uid;

  if v_rol is null then
    return false;
  end if;

  update public.usuarios
     set estudio_id = p_estudio_id,
         rol = v_rol
   where id = v_uid;

  return true;
end;
$$;

grant execute on function public.set_active_estudio(int) to authenticated;
