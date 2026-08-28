-- ============================================================================
-- MENORES DE LA AUDITORÍA FRESCA — los que no necesitan decisión de producto
-- Re-medidos el 28/8: los 8 seguían abiertos. Acá van 6; el 4 (clase huérfana
-- de YN Pilates) y el 8 (RPC de bienvenida) esperan decisión de la usuaria.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- m5 · storage.objects no tenía policy DELETE en NINGÚN bucket: nadie podía
--      borrar lo que subía, ni Aura. Con estudios subiendo fotos, el bucket
--      sólo crecía. Se calca la expresión de cada policy de INSERT, que ya
--      define "tu carpeta": quien puede subir ahí, puede borrar ahí.
-- ----------------------------------------------------------------------------
drop policy if exists avatares_delete_own_folder on storage.objects;
create policy avatares_delete_own_folder on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatares'
         and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists user_media_delete_own_folder on storage.objects;
create policy user_media_delete_own_folder on storage.objects
  for delete to authenticated
  using (bucket_id = 'user-media'
         and (storage.foldername(name))[1] = 'avatars'
         and (storage.foldername(name))[2] = auth.uid()::text);

drop policy if exists study_media_delete_own_folder on storage.objects;
create policy study_media_delete_own_folder on storage.objects
  for delete to authenticated
  using (bucket_id = 'study-media'
         and (storage.foldername(name))[1] = any (array['study-profile','study-gallery','class-media','logos'])
         and (storage.foldername(name))[2] = auth.uid()::text
         and (public.is_admin() or exists (
               select 1 from public.estudio_admins ea where ea.usuario_id = auth.uid())));

-- Aura (superadmin) puede limpiar cualquier bucket: hoy no podía ni borrar
-- lo que subía un estudio que se dio de baja.
drop policy if exists storage_delete_superadmin on storage.objects;
create policy storage_delete_superadmin on storage.objects
  for delete to authenticated
  using (bucket_id in ('avatares','user-media','study-media') and public.is_admin());

-- ----------------------------------------------------------------------------
-- m7 · `plan`, `subscription_status`, `mp_subscription_id` y `renewal_date`
--      eran auto-escribibles por la propia usuaria. Medido el 26/8: ninguna
--      función regala créditos mirándolas, así que el efecto se limitaba a un
--      badge falso — pero son datos de suscripción y los pone el webhook de
--      Mercado Pago, nunca el cliente.
--      Verificado antes de cerrar: NINGÚN punto del Dart las escribe.
--      (Eran 2 en la nota; medido el 28/8 son 4.)
-- ----------------------------------------------------------------------------
create or replace function public.usuarios_bloquear_columnas_sensibles()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  -- Las RPC security definer (owned by postgres) y el service_role corren con
  -- otro current_user y pasan.
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if new.rol is distinct from old.rol then
    raise exception 'No se puede cambiar el rol desde el cliente';
  end if;
  if new.estudio_id is distinct from old.estudio_id then
    raise exception 'No se puede cambiar el estudio desde el cliente';
  end if;
  if new.creditos is distinct from old.creditos then
    raise exception 'Los creditos se ajustan solo por el ledger';
  end if;
  if new.email is distinct from old.email then
    raise exception 'El email no se cambia desde el cliente';
  end if;
  if new.empresa_id is distinct from old.empresa_id
     or new.es_corporativo is distinct from old.es_corporativo then
    raise exception 'El vinculo con una empresa lo asigna Aura, no el cliente';
  end if;
  -- 2026-08-28: la suscripción la escribe el webhook de Mercado Pago
  -- (service_role), nunca la usuaria.
  if new.plan is distinct from old.plan
     or new.subscription_status is distinct from old.subscription_status
     or new.mp_subscription_id is distinct from old.mp_subscription_id
     or new.renewal_date is distinct from old.renewal_date then
    raise exception 'Tu plan lo actualiza Aura cuando se procesa el pago';
  end if;

  return new;
end
$function$;

-- ----------------------------------------------------------------------------
-- m9 · La policy se llamaba "Admins leen config" pero es `using (true)`: la
--      lee cualquiera. NO se cierra a propósito — el chequeo de `min_build`
--      corre ANTES del login, así que cerrarla rompería el gate de versión.
--      Se renombra para que el nombre diga la verdad.
-- ----------------------------------------------------------------------------
alter policy "Admins leen config" on public.configuracion_global
  rename to "config global: lectura publica (la lee el gate de version pre-login)";

-- ----------------------------------------------------------------------------
-- m10 · `horarios_fijos` tenía "todos pueden ver horarios" con `using (true)`:
--       cualquier usuario logueado leía las grillas de todos los estudios, y
--       esa policy anulaba (por OR) las 4 acotadas por `es_miembro_de_estudio`
--       que se pusieron el 24/8 para multi-sede.
--       Verificado: en el Dart sólo la leen `estudio_admin_service` y
--       `mis_clases_screen`, los dos del panel del estudio. La alumna nunca
--       lee esta tabla (ve `clases`, que sí es pública).
-- ----------------------------------------------------------------------------
drop policy if exists "todos pueden ver horarios" on public.horarios_fijos;

-- ----------------------------------------------------------------------------
-- m11 · Las 5 funciones sin `search_path`. Las 5 son trigger functions
--       *invoker* (0 SECURITY DEFINER), así que no había vector real: es
--       prolijidad y consistencia con las otras 112.
-- ----------------------------------------------------------------------------
alter function public.aura_inicio_mes_art()          set search_path to 'public';
alter function public.set_study_review_updated_at()  set search_path to 'public';
alter function public.set_updated_at()               set search_path to 'public';
alter function public.sync_categoria_estudio()       set search_path to 'public';
alter function public.sync_categorias_clase()        set search_path to 'public';
