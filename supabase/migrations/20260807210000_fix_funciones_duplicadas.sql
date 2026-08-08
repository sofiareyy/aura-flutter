-- ============================================================================
-- AURA — Firmas duplicadas: unificar rol_en_estudio y admin_remove_studio_access
-- (2026-08-07)
-- ============================================================================
--
-- La auditoría previa al build encontró tres funciones con más de una versión
-- conviviendo. Dos se arreglan acá; pack_credits_expiration queda pendiente
-- hasta saber cuál usa el flujo de pago (ver nota al final).
--
--
-- 1) rol_en_estudio(integer) y rol_en_estudio(bigint)
--    Los cuerpos son IDÉNTICOS: mismo SQL, mismo security definer, mismo
--    search_path. No hay riesgo de comportamiento, solo de que PostgREST o el
--    resolutor de tipos tenga que elegir. Queda la de bigint (int->bigint
--    ensancha solo, así que ningún llamador se rompe).
--
--
-- 2) admin_remove_studio_access — ACÁ SÍ HABÍA UN BUG
--    Las dos versiones hacían cosas distintas:
--
--    (bigint, uuid) -> void   [LEGACY, del modelo pre-M:N]
--        * solo autorizaba a superadmin
--        * NO borraba de estudio_admins: apenas pisaba usuarios.rol y
--          estudio_id, así que la persona CONSERVABA el acceso
--        * no protegía a la dueña
--
--    (integer, uuid) -> json  [correcta, migración 20260724120000]
--        * autoriza superadmin O admin real del estudio
--        * protege rol='estudio' (dueña)
--        * borra de estudio_admins de verdad
--        * reubica el estudio activo y degrada a 'usuario' si no le queda
--          ninguno
--
--    El cliente (admin_service.dart) ignora el valor de retorno, así que si
--    caía en la legacy el backoffice decía "listo" sin sacar nada.
--
--    Dejamos UNA sola, con la lógica correcta y parámetro bigint (los id son
--    bigint; bigint->int no castea solo y ya nos mordió con
--    calcular_precio_clase). Se conserva el log de auditoría que tenía la
--    legacy, que era lo único bueno que aportaba.

begin;


-- ── 1. rol_en_estudio: queda solo la de bigint ──────────────────────────────
drop function if exists public.rol_en_estudio(integer);

-- Reafirmamos la que queda (idéntica a las dos que había).
create or replace function public.rol_en_estudio(p_estudio_id bigint)
returns text
language sql
security definer
stable
set search_path = public
as $$
  select rol
    from public.estudio_admins
   where estudio_id = p_estudio_id
     and usuario_id = auth.uid()
   limit 1;
$$;

revoke execute on function public.rol_en_estudio(bigint) from public, anon;
grant execute on function public.rol_en_estudio(bigint) to authenticated;


-- ── 2. admin_remove_studio_access: una sola, con la lógica correcta ─────────
drop function if exists public.admin_remove_studio_access(bigint, uuid);
drop function if exists public.admin_remove_studio_access(integer, uuid);

create function public.admin_remove_studio_access(
  p_estudio_id bigint,
  p_user_id    uuid
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_rol text;
  v_email      text;
begin
  if auth.uid() is null then
    return json_build_object('ok', false, 'error', 'no_auth');
  end if;

  -- superadmin O admin real del estudio. Una profe no gestiona accesos.
  if not public.caller_puede_gestionar_accesos(p_estudio_id::int) then
    return json_build_object('ok', false, 'error', 'forbidden');
  end if;

  select rol into v_target_rol
    from public.estudio_admins
   where estudio_id = p_estudio_id
     and usuario_id = p_user_id;

  if v_target_rol is null then
    return json_build_object('ok', false, 'error', 'no_es_miembro');
  end if;

  if v_target_rol = 'estudio' then
    return json_build_object('ok', false, 'error', 'no_se_puede_sacar_duena');
  end if;

  -- Esto es lo que la versión legacy NO hacía.
  delete from public.estudio_admins
   where estudio_id = p_estudio_id
     and usuario_id = p_user_id;

  -- Si el estudio quitado era el activo, mover el activo a otro que le quede.
  update public.usuarios u
     set estudio_id = (
       select ea.estudio_id from public.estudio_admins ea
        where ea.usuario_id = p_user_id
        order by ea.created_at desc
        limit 1
     )
   where u.id = p_user_id
     and u.estudio_id = p_estudio_id;

  -- Si ya no es miembro de ningún estudio, vuelve a usuario común.
  update public.usuarios u
     set rol = 'usuario',
         estudio_id = null
   where u.id = p_user_id
     and not exists (
       select 1 from public.estudio_admins where usuario_id = p_user_id
     );

  -- Log de auditoría (lo aportaba la versión legacy). Si fallara, no debe
  -- tumbar el quitado de acceso, que es lo importante.
  begin
    select email into v_email from public.usuarios where id = p_user_id;
    perform public.log_admin_action(
      'Quitar acceso estudio',
      coalesce(v_email, p_user_id::text),
      'estudios'
    );
  exception when others then
    null;
  end;

  return json_build_object('ok', true);
end;
$$;

revoke execute on function
  public.admin_remove_studio_access(bigint, uuid) from public, anon;
grant execute on function
  public.admin_remove_studio_access(bigint, uuid)
  to authenticated, service_role;


commit;


-- ── VERIFICACIÓN (solo lee) ─────────────────────────────────────────────────

-- 1) Ya no debe quedar ninguna función con firmas duplicadas, salvo
--    pack_credits_expiration (pendiente, ver abajo).
select p.proname,
       count(*) as versiones,
       string_agg(pg_get_function_identity_arguments(p.oid), '  ||  ') as firmas
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.prokind = 'f'
 group by p.proname
having count(*) > 1
 order by p.proname;

-- 2) Las dos que tocamos, con su firma final.
select p.proname,
       pg_get_function_identity_arguments(p.oid) as firma,
       pg_get_function_result(p.oid)             as retorna
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('rol_en_estudio', 'admin_remove_studio_access')
 order by p.proname;


-- ── PENDIENTE: pack_credits_expiration ──────────────────────────────────────
-- Tiene 3 versiones con reglas de vencimiento DISTINTAS:
--   (date)        -> fin del mes +2
--   (date, int)   -> compra + 90 días
--   (text, int)   -> los días configurados del pack, o 30/60 por defecto
-- No hay ambigüedad (distinta aridad y tipo de retorno), así que no rompe
-- nada hoy. Pero antes de unificarlas hay que saber cuál usa el flujo de pago.
-- Correr esto y decidir con el resultado:
--
--   select p.proname, pg_get_function_identity_arguments(p.oid) as firma
--     from pg_proc p
--    where p.pronamespace = 'public'::regnamespace
--      and p.prosrc ilike '%pack_credits_expiration%'
--    order by p.proname;
