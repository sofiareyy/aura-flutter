-- ============================================================================
-- AURA — Baja de "invitar por mail": se va invitaciones_grupo (2026-08-13)
-- ============================================================================
--
-- El "invitá amigas a esta clase" pedía escribir el mail de la otra persona.
-- Nadie se lo sabe de memoria, así que la función no se usaba, y además era
-- uno a uno. Se reemplazó por "Compartir esta clase", que abre el compartir
-- nativo del teléfono con un link a la página de la clase.
--
-- Lo que ya se sacó del lado del código:
--   * la hoja de invitación en detalle_clase_screen.dart (~200 líneas)
--   * el contador "N amigas van"
--   * la edge function email-invitacion-clase
--
-- Queda esta tabla sin ningún escritor.
--
-- ⚠️ EL ORDEN IMPORTA. `admin_delete_estudio` borra de invitaciones_grupo
-- antes de borrar las clases (el FK a clases es RESTRICT). Si dropeamos la
-- tabla sin redefinir esa función, el drop pasa sin quejarse y "eliminar
-- estudio" explota DESPUÉS, en ejecución, porque plpgsql resuelve los nombres
-- recién ahí. Por eso primero va la función y después el drop.

begin;

-- ── 1. admin_delete_estudio sin el bloque de invitaciones ───────────────────
-- Copia exacta de la versión vigente, sacando solo el delete de
-- invitaciones_grupo. El resto queda igual.
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


-- ── 2. Recién ahora, la tabla ───────────────────────────────────────────────
-- `delete-account` también la nombra, pero envuelve cada tabla en try/catch
-- ("si la tabla no existe... ignoramos el error"), así que no se rompe.
drop table if exists public.invitaciones_grupo;

commit;


-- ── VERIFICACIÓN (solo lee) ─────────────────────────────────────────────────

-- 1) La tabla ya no existe. Tiene que dar 0 filas.
select table_name
  from information_schema.tables
 where table_schema = 'public'
   and table_name = 'invitaciones_grupo';

-- 2) admin_delete_estudio ya no la menciona. `menciona_invitaciones` = false.
select p.proname,
       p.prosrc ilike '%invitaciones_grupo%' as menciona_invitaciones
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname = 'admin_delete_estudio';

-- 3) ¿Alguna otra función quedó nombrándola? Tiene que dar 0 filas.
select p.proname, pg_get_function_identity_arguments(p.oid) as firma
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.prosrc ilike '%invitaciones_grupo%'
 order by p.proname;
