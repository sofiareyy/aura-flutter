-- =====================================================================
-- FIX tanda 2 — 2026-08-21
-- Tres agujeros de la segunda auditoría. Aplicados vía Management API y
-- verificados con rollback + efecto. Solo base, sin Dart => sin build.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 🔴 1. Borrado en cascada: la usuaria destruía facturación del estudio
-- ---------------------------------------------------------------------
-- Bug: `usuarios_self_all` (policy ALL para authenticated con
-- USING id = auth.uid()) habilitaba DELETE. Una usuaria hacía
-- DELETE /rest/v1/usuarios?id=eq.<ella> con su propio token y cascadeaba
-- por las 12 FKs. MEDIDO:
--     reservas             5 -> 2
--     créditos facturables 65 -> 30   (el estudio pierde 35 cobrables)
--     ledger              15 -> 11
--     pagos               29 -> 28   <- se destruye un registro de pago
--     auth.users                     queda huérfana
--
-- Fix: la policy era REDUNDANTE para todo menos DELETE — SELECT, INSERT y
-- UPDATE ya tienen policies propias (usuarios_select_self,
-- usuarios_insert_self, usuarios_update_self, "estudio actualiza su perfil").
-- Se borra y el DELETE desaparece sin tocar nada más.
--
-- No rompe delete-account: corre con service_role, que tiene
-- rolbypassrls = true (verificado). Y la app NUNCA borra la fila directo:
-- 0 DELETE sobre `usuarios` en todo lib/ (auth_service.dart:196 y
-- admin_service.dart:148 invocan la edge function).
--
-- ⚠️ OJO: esto NO cierra el problema contable. `delete-account` en su paso 5
-- hace el mismo DELETE (como service_role) y cascadea IGUAL — medido, mismos
-- números. Lo que se cierra es el camino SILENCIOSO: ahora pasa por la edge,
-- que devuelve créditos de clases futuras y avisa a los estudios.
-- Ver pendientes/PRESERVAR_FACTURACION.md.
--
-- Verificado 6/6 (con rollback y contra producción):
--   DELETE propio -> 0 filas | SELECT -> 1 fila | UPDATE perfil -> OK
--   UPDATE creditos -> bloqueado por trigger | INSERT propio -> OK
--   service_role borra -> 1 fila (delete-account intacto)

drop policy if exists "usuarios_self_all" on public.usuarios;

-- Reversión:
-- create policy "usuarios_self_all" on public.usuarios for all to authenticated
--   using (id = auth.uid()) with check (id = auth.uid());


-- ---------------------------------------------------------------------
-- 🟠 2. Storage: cualquier logueado subía a la carpeta de otro estudio
-- ---------------------------------------------------------------------
-- Bug: la policy de INSERT era solo `bucket_id = 'study-media'`. Sin
-- restricción de path, de dueño, de tamaño ni de tipo. MEDIDO: una usuaria
-- común subió a study-media (81 -> 82 objetos) y podía escribir en
-- `study-profile/<uuid-de-otro-estudio>/…`. Los buckets son públicos, así que
-- servía para hostear cualquier archivo en el dominio del proyecto.
-- (Borrar y pisar ajenos ya estaba bloqueado.)
--
-- Convención verificada: los 82 objetos tienen (foldername)[2] = owner.
-- Rutas reales: study-profile/, study-gallery/, class-media/, logos/ en
-- study-media; avatars/ en user-media.
--
-- Verificado 6/6: estudio a SU carpeta OK | a la de otro bloqueado |
-- usuaria común a study-media bloqueado | carpeta inventada bloqueada |
-- avatar propio OK | avatar de otro bloqueado.

drop policy if exists "study_media_auth_upload" on storage.objects;
drop policy if exists "user_media_auth_upload"  on storage.objects;

create policy "study_media_upload_own_folder" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'study-media'
  and (storage.foldername(name))[1] in ('study-profile','study-gallery','class-media','logos')
  and (storage.foldername(name))[2] = auth.uid()::text
  and (public.is_admin()
       or exists (select 1 from public.estudio_admins ea where ea.usuario_id = auth.uid()))
);

create policy "user_media_upload_own_folder" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'user-media'
  and (storage.foldername(name))[1] = 'avatars'
  and (storage.foldername(name))[2] = auth.uid()::text
);

-- Límites que faltaban (estaban los dos en NULL).
-- 10 MB: el archivo más grande hoy pesa 6,30 MB. image/*: los tipos en uso
-- son jpeg, png, avif, heic y heif (el cliente los infiere de la extensión).
update storage.buckets
   set file_size_limit = 10485760,
       allowed_mime_types = array['image/*']
 where id in ('study-media','user-media','avatares');


-- ---------------------------------------------------------------------
-- 🟠 3. Tabla `resenas` legacy: reseñas sin haber ido
-- ---------------------------------------------------------------------
-- Había DOS tablas de reseñas:
--   study_reviews -> la que usa la app (reviews_service.dart). CHECK
--                    auth.uid() = usuario_id AND can_review_study(...).
--                    MEDIDO: bloquea opinar sin haber ido. Correcta.
--   resenas       -> legacy, 0 filas, ningún Dart la toca. CHECK solo
--                    usuario_id = auth.uid(), sin requisito de asistencia,
--                    y SELECT USING true. MEDIDO: PASÓ.
--
-- Se borra en vez de acotarla: nada la lee. Único referente real era
-- admin_delete_estudio (una línea), que se reescribe sin ella.
-- El hit de "resenas" en Dart era falso positivo: 'aura_resenas' es un id
-- de canal de notificaciones Android.
--
-- Verificado: admin_delete_estudio(4) sigue borrando (estudios 9 -> 8) y una
-- usuaria común sigue recibiendo 'No autorizado'.

create or replace function public.admin_delete_estudio(p_estudio_id bigint)
 returns void language plpgsql security definer set search_path to 'public'
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
  -- (public.resenas se eliminó el 2026-08-21: tabla legacy, 0 filas, sin uso)

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

drop table if exists public.resenas;

-- (fin)
