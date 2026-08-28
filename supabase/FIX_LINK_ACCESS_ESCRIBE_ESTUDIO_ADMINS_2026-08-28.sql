-- m6 · `admin_link_estudio_access` (el fallback legacy de vincular acceso)
-- escribía SOLO `usuarios.rol/estudio_id` (el puntero de sede activa) y 0
-- filas en `estudio_admins` — que es donde miran los permisos reales
-- (`es_miembro_de_estudio`, `puede_ver_reservas_de_clase`, etc.). Si el
-- backoffice caía a este fallback, el estudio quedaba "vinculado" a la vista
-- pero sin acceso real: síntoma confuso.
--
-- Decisión de la usuaria (28/8): NO borrarla (el backoffice la tiene como
-- fallback vivo en admin_service.dart:274); hacerla consistente. Se le suma
-- el MISMO insert que hace `studio_promote_user_to_admin`, calcado:
-- acumula (on conflict do nothing), nunca reemplaza.

create or replace function public.admin_link_estudio_access(p_estudio_id bigint, p_email text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user_id uuid;
  v_nombre_estudio text;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  if p_estudio_id is null then
    raise exception 'Estudio inválido';
  end if;

  if trim(coalesce(p_email, '')) = '' then
    raise exception 'Ingresá un email válido';
  end if;

  select u.id
    into v_user_id
  from public.usuarios u
  where lower(trim(u.email)) = lower(trim(p_email))
  limit 1;

  if v_user_id is null then
    raise exception 'No existe una cuenta Aura con ese email. Primero tiene que registrarse.';
  end if;

  update public.usuarios
     set rol = 'admin_estudio',
         estudio_id = p_estudio_id
   where id = v_user_id;

  -- 2026-08-28: el acceso REAL. Mismo insert que studio_promote_user_to_admin:
  -- SUMA la membresía (do nothing si ya está), no reemplaza las existentes.
  insert into public.estudio_admins (estudio_id, usuario_id, rol)
  values (p_estudio_id, v_user_id, 'admin_estudio')
  on conflict (estudio_id, usuario_id) do nothing;

  select e.nombre
    into v_nombre_estudio
  from public.estudios e
  where e.id = p_estudio_id;

  perform public.log_admin_action(
    'Vincular acceso estudio',
    coalesce(trim(p_email), '') || ' -> ' || coalesce(v_nombre_estudio, 'Estudio'),
    'estudios'
  );
end;
$function$;
