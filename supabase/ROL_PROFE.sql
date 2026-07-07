-- Rol "profe": admin de estudio con vista limitada. 2026-07-07.
--
-- Modelo: reutiliza estudio_admins (M:N) + usuarios.rol, igual que
-- admin_estudio. La profe se vincula a un estudio existente; obtiene por RLS
-- (policies de clases/reservas que chequean estudio_admins) permiso para ver y
-- cancelar clases y ver asistencia. La vista limitada (sin Cobros, Config,
-- datos bancarios ni gestión de usuarios) es gating de UI/ruteo en Flutter.
--
-- Onboarding: la profe YA tiene su cuenta normal de Aura. La dueña la agrega
-- por email desde "Mis Profes" y el sistema le asigna el rol. Sin mails ni
-- contraseñas temporales.

-- 1. Ampliar el CHECK de estudio_admins.rol para admitir 'profe' -----------
alter table public.estudio_admins
  drop constraint if exists estudio_admins_rol_check;
alter table public.estudio_admins
  add constraint estudio_admins_rol_check
  check (rol in ('estudio', 'admin_estudio', 'profe'));

-- 2. RPC: studio_add_profe -------------------------------------------------
-- La dueña/admin del estudio agrega una profe por email. Solo admins reales
-- (rol estudio/admin_estudio) pueden agregar profes; una profe no.
create or replace function public.studio_add_profe(
  p_estudio_id int,
  p_email      text
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id         uuid := auth.uid();
  v_caller_authorized boolean;
  v_target_id         uuid;
  v_normalized_email  text := lower(trim(p_email));
begin
  if v_caller_id is null then
    return json_build_object('ok', false, 'error', 'no_auth');
  end if;
  if v_normalized_email = '' then
    return json_build_object('ok', false, 'error', 'email_required');
  end if;

  -- El caller debe ser admin REAL del estudio (no una profe)
  select exists (
    select 1 from public.estudio_admins
     where estudio_id = p_estudio_id
       and usuario_id = v_caller_id
       and rol in ('estudio', 'admin_estudio')
  ) into v_caller_authorized;

  if not v_caller_authorized then
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

  -- Subir rol a 'profe' solo si era 'usuario' (no degradar un admin_estudio)
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

grant execute on function public.studio_add_profe(int, text) to authenticated;

-- 3. RPC: studio_list_profes ----------------------------------------------
-- Lista las profes de un estudio. Solo admins reales del estudio.
create or replace function public.studio_list_profes(p_estudio_id int)
returns table (id uuid, nombre text, email text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid := auth.uid();
begin
  if v_caller_id is null then
    return;
  end if;
  if not exists (
    select 1 from public.estudio_admins
     where estudio_id = p_estudio_id
       and usuario_id = v_caller_id
       and rol in ('estudio', 'admin_estudio')
  ) then
    return;
  end if;

  return query
    select u.id, u.nombre, u.email
      from public.estudio_admins ea
      join public.usuarios u on u.id = ea.usuario_id
     where ea.estudio_id = p_estudio_id
       and ea.rol = 'profe'
     order by u.email;
end;
$$;

grant execute on function public.studio_list_profes(int) to authenticated;

-- Nota: para ELIMINAR una profe se reutiliza remove_estudio_admin_access
-- (ya existente): borra la fila de estudio_admins y baja el rol a 'usuario'
-- si no le quedan estudios.
