-- Eliminar estudio (permanente) desde el backoffice. 2026-07-07.
--
-- Borra el estudio y TODO lo asociado, respetando el orden de FKs:
--  - invitaciones_grupo -> clases es RESTRICT: hay que borrarlas antes.
--  - clases NO tiene FK a estudios (no cascadea) => se borran explícitamente.
--    Al borrar clases cascadean reservas y lista_espera (FK ON DELETE CASCADE).
--  - liquidaciones y resenas -> estudios son RESTRICT: se borran antes.
--  - El resto (horarios_fijos, study_reviews, favoritos_estudios,
--    estudio_alumnos, notificaciones_estudio, estudio_admins) cascadea al
--    borrar el estudio. usuarios.estudio_asociado_id es SET NULL.
--  - usuarios.estudio_id NO tiene FK: se desvincula a mano para no dejar
--    cuentas apuntando a un estudio inexistente (no se borra la cuenta).

create or replace function public.admin_delete_estudio(p_estudio_id bigint)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_nombre text;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  select nombre into v_nombre from public.estudios where id = p_estudio_id;
  if v_nombre is null then
    raise exception 'El estudio no existe';
  end if;

  -- invitaciones_grupo referencian clases con RESTRICT
  delete from public.invitaciones_grupo
   where clase_id in (
     select id from public.clases where estudio_id = p_estudio_id
   );

  -- clases (cascadea reservas y lista_espera)
  delete from public.clases where estudio_id = p_estudio_id;

  -- FKs RESTRICT directas sobre estudios
  delete from public.liquidaciones where estudio_id = p_estudio_id;
  delete from public.resenas where estudio_id = p_estudio_id;

  -- desvincular cuentas del estudio (usuarios.estudio_id no tiene FK)
  update public.usuarios set estudio_id = null where estudio_id = p_estudio_id;

  -- estudio (cascadea el resto de relaciones)
  delete from public.estudios where id = p_estudio_id;

  perform public.log_admin_action(
    'Eliminar estudio',
    coalesce(v_nombre, 'Estudio') || ' (#' || p_estudio_id || ')',
    'estudios'
  );
end;
$function$;
