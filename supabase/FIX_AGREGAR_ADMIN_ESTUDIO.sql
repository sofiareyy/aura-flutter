-- AURA - RPC para que un dueño/admin de estudio pueda promover a otro usuario
-- como admin_estudio del mismo estudio (2026-05-06).
--
-- Bug: `_agregarAdmin` en perfil_estudio_screen.dart hace
--   `from('usuarios').select('id, email')` sin filtros, asumiendo que ve a
-- todos los users. Con RLS sano, solo ve la propia fila → "no se encontro
-- un usuario con ese email". Aparte el update tambien lo bloquearia RLS.
--
-- Fix: una funcion SECURITY DEFINER que valida autorizacion y hace el
-- update en un solo paso, sin depender de policies.


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
  v_caller_rol         text;
  v_caller_estudio_id  int;
  v_target_id          uuid;
  v_normalized_email   text := lower(trim(p_email));
begin
  if v_caller_id is null then
    return json_build_object('ok', false, 'error', 'no_auth');
  end if;

  if v_normalized_email = '' then
    return json_build_object('ok', false, 'error', 'email_required');
  end if;

  select rol, estudio_id
    into v_caller_rol, v_caller_estudio_id
    from public.usuarios
   where id = v_caller_id;

  if v_caller_rol is null or v_caller_rol not in ('estudio', 'admin_estudio') then
    return json_build_object('ok', false, 'error', 'forbidden');
  end if;

  if v_caller_estudio_id is null or v_caller_estudio_id <> p_estudio_id then
    return json_build_object('ok', false, 'error', 'not_owner_of_estudio');
  end if;

  select id
    into v_target_id
    from public.usuarios
   where lower(trim(email)) = v_normalized_email
   limit 1;

  if v_target_id is null then
    return json_build_object('ok', false, 'error', 'user_not_found');
  end if;

  update public.usuarios
     set rol        = 'admin_estudio',
         estudio_id = p_estudio_id
   where id = v_target_id;

  return json_build_object('ok', true, 'user_id', v_target_id);
end;
$$;

grant execute on function public.studio_promote_user_to_admin(int, text)
  to authenticated;


-- Verificacion rapida (descomentar y ajustar para probar):
-- select public.studio_promote_user_to_admin(1, 'test@aura.com');
