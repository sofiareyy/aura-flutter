-- ============================================================================
-- D2 — Permisos de rol: promover/quitar admins con filtro de rol y
--      protección de la dueña del estudio
-- ============================================================================
--
-- Puntos 5 y 6 (doble devolución + cupo que no se libera) quedaron cubiertos
-- en D1 al reescribir la cancelación como `cancelar_mi_reserva` /
-- `estudio_cancelar_clase` (FOR UPDATE + chequeo de estado + restauración de
-- lugares_disponibles). No se reabre nada acá.
--
-- Punto 7 (profe borra clases / cambia CBU): las policies de `clases` y
-- `estudios` ya se arreglaron en D1 con filtro `rol in ('estudio',
-- 'admin_estudio')` + trigger que bloquea comisiones/pricing. No se repite.
--
-- Este archivo cierra el punto 8: escalada de privilegios vía
-- studio_promote_user_to_admin / remove_estudio_admin_access.
-- ============================================================================

-- La "dueña" del estudio es quien tiene rol='estudio' en estudio_admins.
-- 'admin_estudio' es un administrador agregado; 'profe' es acceso limitado.

-- ── promover a admin: solo un admin puede, nunca una profe ─────────────────
create or replace function public.studio_promote_user_to_admin(
  p_estudio_id int,
  p_email      text
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id        uuid := auth.uid();
  v_caller_rol       text;
  v_target_id        uuid;
  v_normalized_email text := lower(trim(coalesce(p_email, '')));
begin
  if v_caller_id is null then
    return json_build_object('ok', false, 'error', 'no_auth');
  end if;
  if v_normalized_email = '' then
    return json_build_object('ok', false, 'error', 'email_required');
  end if;

  -- Antes bastaba con estar en estudio_admins (cualquier rol). Ahora se exige
  -- ser admin/dueña: una profe no puede meter cómplices como admin.
  select rol into v_caller_rol
    from public.estudio_admins
   where estudio_id = p_estudio_id
     and usuario_id = v_caller_id;

  if v_caller_rol is null or v_caller_rol not in ('estudio', 'admin_estudio') then
    return json_build_object('ok', false, 'error', 'forbidden');
  end if;

  select id into v_target_id
    from public.usuarios
   where lower(trim(email)) = v_normalized_email
   limit 1;

  if v_target_id is null then
    return json_build_object('ok', false, 'error', 'user_not_found');
  end if;

  -- Si ya existe el vínculo, no se pisa el rol (no degradar a la dueña).
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

revoke execute on function public.studio_promote_user_to_admin(int, text)
  from public, anon;
grant execute on function public.studio_promote_user_to_admin(int, text)
  to authenticated;


-- ── quitar acceso: solo admin, y NUNCA se puede sacar a la dueña ───────────
create or replace function public.remove_estudio_admin_access(
  p_estudio_id int,
  p_usuario_id uuid
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id  uuid := auth.uid();
  v_caller_rol text;
  v_target_rol text;
begin
  if v_caller_id is null then
    return json_build_object('ok', false, 'error', 'no_auth');
  end if;

  select rol into v_caller_rol
    from public.estudio_admins
   where estudio_id = p_estudio_id
     and usuario_id = v_caller_id;

  if v_caller_rol is null or v_caller_rol not in ('estudio', 'admin_estudio') then
    return json_build_object('ok', false, 'error', 'forbidden');
  end if;

  select rol into v_target_rol
    from public.estudio_admins
   where estudio_id = p_estudio_id
     and usuario_id = p_usuario_id;

  -- La dueña (rol='estudio') no se puede sacar por esta vía: era el vector
  -- por el que una profe/otro admin podía dejar al estudio sin dueña.
  if v_target_rol = 'estudio' then
    return json_build_object('ok', false, 'error', 'no_se_puede_sacar_duena');
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
       select 1 from public.estudio_admins where usuario_id = p_usuario_id
     );

  return json_build_object('ok', true);
end;
$$;

revoke execute on function public.remove_estudio_admin_access(int, uuid)
  from public, anon;
grant execute on function public.remove_estudio_admin_access(int, uuid)
  to authenticated;
