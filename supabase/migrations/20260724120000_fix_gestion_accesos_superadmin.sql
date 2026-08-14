-- ============================================================================
-- FIX: gestión de accesos (admin/profe) desde el backoffice y el panel estudio
-- ============================================================================
--
-- Bug reportado: un super-admin de Aura (presente en `admin_users`) no podía
-- agregarse/agregar como administrador de un estudio desde el backoffice
-- ("no me dejó" = forbidden).
--
-- Causa: la migración D2 (20260722100000) endureció studio_promote_user_to_admin
-- y remove_estudio_admin_access para frenar la escalada de una profe, pero al
-- hacerlo dejó SOLO el chequeo contra `estudio_admins` y borró el camino del
-- super-admin (`admin_users`). Resultado: quien maneja el backoffice pero no es
-- ya admin de ESE estudio quedaba afuera.
--
-- Además detectamos:
--   - `admin_remove_studio_access` (que llama el backoffice para "quitar
--     acceso") NO existía en el repo → el remove del backoffice fallaba.
--   - `studio_add_profe` (panel estudio) tampoco aceptaba super-admin.
--
-- Solución: un único criterio de autorización para TODOS los RPCs de gestión
-- de accesos, vía el helper `caller_puede_gestionar_accesos`:
--     super-admin (admin_users)  OR  admin real del estudio
--     (estudio_admins con rol in ('estudio','admin_estudio')).
-- Esto restaura al super-admin SIN reabrir la escalada de la profe: una profe
-- (rol 'profe') no está en admin_users ni cumple el rol admin, así que sigue
-- sin poder promover ni quitar. Se preserva la protección de la dueña
-- (rol='estudio' no se puede quitar) y los downgrades de usuarios.
--
-- admin_add_studio_profe y admin_set_studio_access_rol ya contemplaban el
-- super-admin, así que no se tocan.
-- ============================================================================

-- ── Helper: ¿el caller puede gestionar accesos de este estudio? ─────────────
-- SECURITY DEFINER para poder leer admin_users / estudio_admins salteando RLS.
-- auth.uid() dentro de un definer sigue devolviendo al caller real (viene del
-- claim del JWT, no cambia por el contexto definer), así que la autorización es
-- correcta.
create or replace function public.caller_puede_gestionar_accesos(p_estudio_id int)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
           select 1 from public.admin_users where user_id = auth.uid()
         )
      or exists (
           select 1 from public.estudio_admins
            where estudio_id = p_estudio_id
              and usuario_id = auth.uid()
              and rol in ('estudio', 'admin_estudio')
         );
$$;

revoke execute on function public.caller_puede_gestionar_accesos(int) from public, anon;
grant execute on function public.caller_puede_gestionar_accesos(int) to authenticated;


-- ── 1. Promover a admin (backoffice + panel estudio) ────────────────────────
create or replace function public.studio_promote_user_to_admin(
  p_estudio_id int,
  p_email      text
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_id        uuid;
  v_normalized_email text := lower(trim(coalesce(p_email, '')));
begin
  if auth.uid() is null then
    return json_build_object('ok', false, 'error', 'no_auth');
  end if;
  if v_normalized_email = '' then
    return json_build_object('ok', false, 'error', 'email_required');
  end if;

  if not public.caller_puede_gestionar_accesos(p_estudio_id) then
    return json_build_object('ok', false, 'error', 'forbidden');
  end if;

  select id into v_target_id
    from public.usuarios
   where lower(trim(email)) = v_normalized_email
   limit 1;

  if v_target_id is null then
    return json_build_object('ok', false, 'error', 'user_not_found');
  end if;

  -- Si ya existe el vínculo no se pisa el rol (no degradar a la dueña). Para
  -- subir una profe existente a admin está admin_set_studio_access_rol.
  insert into public.estudio_admins (estudio_id, usuario_id, rol)
  values (p_estudio_id, v_target_id, 'admin_estudio')
  on conflict (estudio_id, usuario_id) do nothing;

  update public.usuarios
     set rol = 'admin_estudio'
   where id = v_target_id
     and coalesce(rol, 'usuario') = 'usuario';

  update public.usuarios
     set estudio_id = p_estudio_id
   where id = v_target_id
     and estudio_id is null;

  return json_build_object('ok', true, 'user_id', v_target_id);
end;
$$;

revoke execute on function public.studio_promote_user_to_admin(int, text) from public, anon;
grant execute on function public.studio_promote_user_to_admin(int, text) to authenticated;


-- ── 2. Agregar profe (panel estudio) ────────────────────────────────────────
create or replace function public.studio_add_profe(
  p_estudio_id int,
  p_email      text
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_id        uuid;
  v_normalized_email text := lower(trim(coalesce(p_email, '')));
begin
  if auth.uid() is null then
    return json_build_object('ok', false, 'error', 'no_auth');
  end if;
  if v_normalized_email = '' then
    return json_build_object('ok', false, 'error', 'email_required');
  end if;

  if not public.caller_puede_gestionar_accesos(p_estudio_id) then
    return json_build_object('ok', false, 'error', 'forbidden');
  end if;

  select id into v_target_id
    from public.usuarios
   where lower(trim(email)) = v_normalized_email
   limit 1;

  if v_target_id is null then
    return json_build_object('ok', false, 'error', 'user_not_found');
  end if;

  -- Vincular como profe (si ya era admin del estudio, no la degradamos).
  insert into public.estudio_admins (estudio_id, usuario_id, rol)
  values (p_estudio_id, v_target_id, 'profe')
  on conflict (estudio_id, usuario_id) do nothing;

  update public.usuarios
     set rol = 'profe'
   where id = v_target_id
     and rol = 'usuario';

  update public.usuarios
     set estudio_id = p_estudio_id
   where id = v_target_id
     and estudio_id is null;

  return json_build_object('ok', true, 'user_id', v_target_id);
end;
$$;

revoke execute on function public.studio_add_profe(int, text) from public, anon;
grant execute on function public.studio_add_profe(int, text) to authenticated;


-- ── 3. Quitar acceso (panel estudio: remove_estudio_admin_access) ───────────
-- Preserva la protección de la dueña (rol='estudio' no se puede quitar) y el
-- downgrade del usuario si deja de ser miembro de cualquier estudio.
create or replace function public.remove_estudio_admin_access(
  p_estudio_id int,
  p_usuario_id uuid
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_rol text;
begin
  if auth.uid() is null then
    return json_build_object('ok', false, 'error', 'no_auth');
  end if;

  if not public.caller_puede_gestionar_accesos(p_estudio_id) then
    return json_build_object('ok', false, 'error', 'forbidden');
  end if;

  select rol into v_target_rol
    from public.estudio_admins
   where estudio_id = p_estudio_id
     and usuario_id = p_usuario_id;

  if v_target_rol = 'estudio' then
    return json_build_object('ok', false, 'error', 'no_se_puede_sacar_duena');
  end if;

  delete from public.estudio_admins
   where estudio_id = p_estudio_id
     and usuario_id = p_usuario_id;

  -- Si el estudio quitado era el activo, mover el activo a otro que le quede.
  update public.usuarios u
     set estudio_id = (
       select ea.estudio_id from public.estudio_admins ea
        where ea.usuario_id = p_usuario_id
        order by ea.created_at desc
        limit 1
     )
   where u.id = p_usuario_id
     and u.estudio_id = p_estudio_id;

  -- Si ya no es miembro de ningún estudio, vuelve a usuario común.
  update public.usuarios u
     set rol = 'usuario',
         estudio_id = null
   where u.id = p_usuario_id
     and not exists (
       select 1 from public.estudio_admins where usuario_id = p_usuario_id
     );

  return json_build_object('ok', true);
end;
$$;

revoke execute on function public.remove_estudio_admin_access(int, uuid) from public, anon;
grant execute on function public.remove_estudio_admin_access(int, uuid) to authenticated;


-- ── 4. Quitar acceso (backoffice: admin_remove_studio_access) ───────────────
-- La app lo llamaba pero NO existía en el repo. Misma lógica que el remove del
-- panel, con el nombre de parámetro que usa el backoffice (p_user_id).
create or replace function public.admin_remove_studio_access(
  p_estudio_id int,
  p_user_id    uuid
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_rol text;
begin
  if auth.uid() is null then
    return json_build_object('ok', false, 'error', 'no_auth');
  end if;

  if not public.caller_puede_gestionar_accesos(p_estudio_id) then
    return json_build_object('ok', false, 'error', 'forbidden');
  end if;

  select rol into v_target_rol
    from public.estudio_admins
   where estudio_id = p_estudio_id
     and usuario_id = p_user_id;

  if v_target_rol = 'estudio' then
    return json_build_object('ok', false, 'error', 'no_se_puede_sacar_duena');
  end if;

  delete from public.estudio_admins
   where estudio_id = p_estudio_id
     and usuario_id = p_user_id;

  update public.usuarios u
     set estudio_id = (
       select ea.estudio_id from public.estudio_admins ea
        where ea.usuario_id = p_user_id
        order by ea.created_at desc
        limit 1
     )
   where u.id = p_user_id
     and u.estudio_id = p_estudio_id;

  update public.usuarios u
     set rol = 'usuario',
         estudio_id = null
   where u.id = p_user_id
     and not exists (
       select 1 from public.estudio_admins where usuario_id = p_user_id
     );

  return json_build_object('ok', true);
end;
$$;

revoke execute on function public.admin_remove_studio_access(int, uuid) from public, anon;
grant execute on function public.admin_remove_studio_access(int, uuid) to authenticated;
