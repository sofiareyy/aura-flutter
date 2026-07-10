-- AURA - Backoffice: gestión de accesos por estudio separando admins y profes
-- (2026-07-09).
--
-- Contexto: desde /admin/estudios el superadmin solo podía "agregar acceso"
-- (siempre como admin_estudio) y no distinguía admins de profes. Estas RPCs
-- son ADITIVAS (no tocan las funciones existentes) y habilitan el panel
-- reorganizado por secciones: Admins del estudio / Profes del estudio, con
-- agregar admin, agregar profe, cambiar rol y eliminar cada uno.
--
-- Autorización: en las tres funciones el caller puede ser
--   * un superadmin (fila en admin_users), o
--   * un admin REAL del estudio (estudio_admins.rol in ('estudio','admin_estudio')).
-- Una profe nunca puede gestionar accesos.


-- Helper inline (repetido en cada función para no depender de otra migración):
--   superadmin OR admin real del estudio.


-- 1. admin_list_studio_members --------------------------------------------
-- Lista TODOS los miembros de un estudio (admins y profes) con su rol.
-- Additiva: no reemplaza a admin_list_studio_accesses.
create or replace function public.admin_list_studio_members(p_estudio_id int)
returns table (id uuid, nombre text, email text, rol text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid := auth.uid();
  v_authorized boolean;
begin
  if v_caller_id is null then
    return;
  end if;

  select
    exists (select 1 from public.admin_users where user_id = v_caller_id)
    or exists (
      select 1 from public.estudio_admins
       where estudio_id = p_estudio_id
         and usuario_id = v_caller_id
         and rol in ('estudio', 'admin_estudio')
    )
  into v_authorized;

  if not v_authorized then
    return;
  end if;

  return query
    select u.id, u.nombre, u.email, ea.rol
      from public.estudio_admins ea
      join public.usuarios u on u.id = ea.usuario_id
     where ea.estudio_id = p_estudio_id
     order by
       case ea.rol when 'estudio' then 0 when 'admin_estudio' then 1 else 2 end,
       u.email;
end;
$$;

grant execute on function public.admin_list_studio_members(int) to authenticated;


-- 2. admin_add_studio_profe -----------------------------------------------
-- Agrega una profe (por email de una cuenta Aura existente) desde el
-- backoffice o desde el panel del estudio. Superadmin-aware.
create or replace function public.admin_add_studio_profe(
  p_estudio_id int,
  p_email      text
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id        uuid := auth.uid();
  v_authorized       boolean;
  v_target_id        uuid;
  v_normalized_email text := lower(trim(p_email));
begin
  if v_caller_id is null then
    return json_build_object('ok', false, 'error', 'no_auth');
  end if;
  if v_normalized_email = '' then
    return json_build_object('ok', false, 'error', 'email_required');
  end if;

  select
    exists (select 1 from public.admin_users where user_id = v_caller_id)
    or exists (
      select 1 from public.estudio_admins
       where estudio_id = p_estudio_id
         and usuario_id = v_caller_id
         and rol in ('estudio', 'admin_estudio')
    )
  into v_authorized;

  if not v_authorized then
    return json_build_object('ok', false, 'error', 'forbidden');
  end if;

  select id into v_target_id
    from public.usuarios
   where lower(trim(email)) = v_normalized_email
   limit 1;

  if v_target_id is null then
    return json_build_object('ok', false, 'error', 'user_not_found');
  end if;

  -- Vincular como profe (si ya era admin del estudio, no la degradamos)
  insert into public.estudio_admins (estudio_id, usuario_id, rol)
  values (p_estudio_id, v_target_id, 'profe')
  on conflict (estudio_id, usuario_id) do nothing;

  -- Subir rol global a 'profe' solo si era 'usuario' (no degradar un admin)
  update public.usuarios
     set rol = 'profe'
   where id = v_target_id
     and rol = 'usuario';

  -- Si no tiene estudio activo, ponerle este
  update public.usuarios
     set estudio_id = p_estudio_id
   where id = v_target_id
     and estudio_id is null;

  return json_build_object('ok', true, 'user_id', v_target_id);
end;
$$;

grant execute on function public.admin_add_studio_profe(int, text) to authenticated;


-- 3. admin_set_studio_access_rol ------------------------------------------
-- Cambia el rol de un miembro existente (admin_estudio <-> profe). Usado por
-- el botón "editar" de cada acceso.
create or replace function public.admin_set_studio_access_rol(
  p_estudio_id int,
  p_usuario_id uuid,
  p_rol        text
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id  uuid := auth.uid();
  v_authorized boolean;
  v_exists     boolean;
begin
  if v_caller_id is null then
    return json_build_object('ok', false, 'error', 'no_auth');
  end if;
  if p_rol not in ('admin_estudio', 'profe') then
    return json_build_object('ok', false, 'error', 'invalid_rol');
  end if;

  select
    exists (select 1 from public.admin_users where user_id = v_caller_id)
    or exists (
      select 1 from public.estudio_admins
       where estudio_id = p_estudio_id
         and usuario_id = v_caller_id
         and rol in ('estudio', 'admin_estudio')
    )
  into v_authorized;

  if not v_authorized then
    return json_build_object('ok', false, 'error', 'forbidden');
  end if;

  select exists (
    select 1 from public.estudio_admins
     where estudio_id = p_estudio_id
       and usuario_id = p_usuario_id
  ) into v_exists;

  if not v_exists then
    return json_build_object('ok', false, 'error', 'not_member');
  end if;

  update public.estudio_admins
     set rol = p_rol
   where estudio_id = p_estudio_id
     and usuario_id = p_usuario_id;

  -- Reflejar en usuarios.rol solo si el rol global era operativo de estudio
  -- (no pisar un 'estudio' dueño ni un 'admin' global de Aura).
  update public.usuarios
     set rol = p_rol
   where id = p_usuario_id
     and rol in ('usuario', 'profe', 'admin_estudio');

  return json_build_object('ok', true);
end;
$$;

grant execute on function public.admin_set_studio_access_rol(int, uuid, text)
  to authenticated;


-- VERIFICACION ------------------------------------------------------------
-- select * from public.admin_list_studio_members(1);
-- select public.admin_add_studio_profe(1, 'profe@correo.com');
-- select public.admin_set_studio_access_rol(1, '<uuid>', 'admin_estudio');
