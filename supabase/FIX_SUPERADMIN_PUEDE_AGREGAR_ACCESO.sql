-- AURA - Permitir que superadmins (backoffice) agreguen/saquen accesos a
-- cualquier estudio, no solo a los que ellos administran (2026-05-14).
--
-- Bug: desde /admin/estudios el superadmin no puede agregar acceso a un
-- estudio porque la RPC studio_promote_user_to_admin chequea que el caller
-- este en estudio_admins. Ahora tambien aceptamos callers presentes en
-- la tabla admin_users (backoffice).


create or replace function public.studio_promote_user_to_admin(
  p_estudio_id int,
  p_email      text
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id          uuid := auth.uid();
  v_caller_authorized  boolean;
  v_is_superadmin      boolean;
  v_target_id          uuid;
  v_normalized_email   text := lower(trim(p_email));
begin
  if v_caller_id is null then
    return json_build_object('ok', false, 'error', 'no_auth');
  end if;
  if v_normalized_email = '' then
    return json_build_object('ok', false, 'error', 'email_required');
  end if;

  -- Superadmin (backoffice) o admin del estudio
  select exists (
    select 1 from public.admin_users where user_id = v_caller_id
  ) into v_is_superadmin;

  if v_is_superadmin then
    v_caller_authorized := true;
  else
    select exists (
      select 1 from public.estudio_admins
       where estudio_id = p_estudio_id
         and usuario_id = v_caller_id
    ) into v_caller_authorized;
  end if;

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

  insert into public.estudio_admins (estudio_id, usuario_id, rol)
  values (p_estudio_id, v_target_id, 'admin_estudio')
  on conflict (estudio_id, usuario_id) do nothing;

  update public.usuarios
     set rol = 'admin_estudio'
   where id = v_target_id
     and rol = 'usuario';

  update public.usuarios
     set estudio_id = p_estudio_id
   where id = v_target_id
     and estudio_id is null;

  return json_build_object('ok', true, 'user_id', v_target_id);
end;
$$;

grant execute on function public.studio_promote_user_to_admin(int, text)
  to authenticated;


-- Mismo cambio en remove_estudio_admin_access

create or replace function public.remove_estudio_admin_access(
  p_estudio_id int,
  p_usuario_id uuid
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id          uuid := auth.uid();
  v_caller_authorized  boolean;
  v_is_superadmin      boolean;
begin
  if v_caller_id is null then
    return json_build_object('ok', false, 'error', 'no_auth');
  end if;

  select exists (
    select 1 from public.admin_users where user_id = v_caller_id
  ) into v_is_superadmin;

  if v_is_superadmin then
    v_caller_authorized := true;
  else
    select exists (
      select 1 from public.estudio_admins
       where estudio_id = p_estudio_id
         and usuario_id = v_caller_id
    ) into v_caller_authorized;
  end if;

  if not v_caller_authorized then
    return json_build_object('ok', false, 'error', 'forbidden');
  end if;

  delete from public.estudio_admins
   where estudio_id = p_estudio_id
     and usuario_id = p_usuario_id;

  update public.usuarios u
     set estudio_id = (
       select ea.estudio_id from public.estudio_admins ea
        where ea.usuario_id = p_usuario_id
        order by ea.created_at desc
        limit 1
     )
   where u.id = p_usuario_id
     and u.estudio_id = p_estudio_id;

  update public.usuarios u
     set rol = 'usuario',
         estudio_id = null
   where u.id = p_usuario_id
     and not exists (
       select 1 from public.estudio_admins
        where usuario_id = p_usuario_id
     );

  return json_build_object('ok', true);
end;
$$;

grant execute on function public.remove_estudio_admin_access(int, uuid)
  to authenticated;
