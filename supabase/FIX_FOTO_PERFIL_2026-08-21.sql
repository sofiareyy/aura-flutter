-- =====================================================================
-- FIX: la foto de perfil nunca funcionó — 2026-08-21
-- Aplicado vía Management API y verificado con rollback + efecto (6/6).
-- Solo base: aplica a todos al instante, sin build.
-- =====================================================================
--
-- EL BUG
-- Las DOS pantallas que suben foto de perfil apuntan al bucket `avatares`,
-- que no tenía NINGUNA policy. RLS las rechazaba y el try/catch mostraba
-- "No se pudo subir la imagen" sin decir por qué.
--
--   editar_perfil_screen.dart -> MediaUploadService.uploadAvatar()
--                                path: {uid}/perfil.{ext}
--   mi_perfil_screen.dart:794 -> upload directo
--                                path: {uid}/perfil.jpg
--
-- MEDIDO antes del fix:
--   subir avatar a `avatares`  -> violates row-level security policy
--   usuarios con avatar_url    -> 0 de 77
--   objetos en `avatares`      -> 0
-- Que ninguno de los 77 usuarios tenga foto confirma que nunca anduvo.
--
-- Las dos pantallas SON alcanzables (se verificó el router):
--   /perfil/editar  <- configuracion_screen.dart:39 y mi_perfil_screen.dart:367
--   /perfil         <- main_shell.dart:138 (barra de navegación)
--
-- POR QUÉ HACEN FALTA 3 POLICIES, NO 1
-- Las dos pantallas usan NOMBRE FIJO (`perfil.jpg`) con `upsert: true`. La
-- primera foto es un INSERT, pero la SEGUNDA es un overwrite = UPDATE.
-- MEDIDO: con policy de solo INSERT, la 1ra pasa y la 2da actualiza 0 filas
-- (falla, otra vez en silencio). Por eso va también la de UPDATE.
-- (`study-media` no tiene este problema: `pickAndUpload` usa nombres con
-- timestamp y nunca colisiona.)
--
-- OJO CON LA CONVENCIÓN DE PATH
-- Acá el uid es el segmento 1 (`{uid}/perfil.jpg`), a diferencia de
-- study-media/user-media donde es el 2 (`{carpeta}/{uid}/archivo`). Es así
-- porque el código ya arma ese path.
-- =====================================================================

drop policy if exists "avatares_upload_own_folder" on storage.objects;
drop policy if exists "avatares_update_own_folder" on storage.objects;
drop policy if exists "avatares_public_read"       on storage.objects;

create policy "avatares_upload_own_folder" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'avatares'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Necesaria para CAMBIAR la foto (upsert sobre el mismo nombre).
create policy "avatares_update_own_folder" on storage.objects
for update to authenticated
using (
  bucket_id = 'avatares'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'avatares'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "avatares_public_read" on storage.objects
for select to public using (bucket_id = 'avatares');

-- NO se crea policy de DELETE: nada la necesita y es menos superficie.
-- Los límites del bucket (10 MB, image/*) ya estaban puestos por
-- FIX_TANDA2_2026-08-21.sql.

-- =====================================================================
-- VERIFICACIÓN — 6 pruebas, con ROLLBACK, midiendo efecto
-- =====================================================================
-- Corrida del 2026-08-21 (post-aplicación, contra producción): 6/6.
--   1 subo MI foto a MI carpeta              -> pasa
--   2 CAMBIO mi foto (upsert, mismo nombre)  -> 1 fila   <- la del detalle
--   3 subo a la carpeta de OTRO              -> bloqueado
--   4 piso la foto de OTRO                   -> 0 filas
--   5 borro la foto de OTRO                  -> bloqueado
--   6 anon sube                              -> bloqueado
--
-- Y sin tocar nada más:
--   study-media  81 objetos (intacto) · user-media 1 objeto (intacto)
--   las 4 policies previas siguen · 4 -> 7 policies
--   límites: los 3 buckets en 10 MB / image/*
--
-- Reversión:
--   drop policy "avatares_upload_own_folder" on storage.objects;
--   drop policy "avatares_update_own_folder" on storage.objects;
--   drop policy "avatares_public_read"       on storage.objects;

-- (fin)
