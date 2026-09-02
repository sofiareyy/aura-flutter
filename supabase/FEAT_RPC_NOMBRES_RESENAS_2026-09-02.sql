-- =============================================================================
-- Nombres de autoras de reseñas, para el lado ALUMNA (2026-09-02)
-- =============================================================================
-- Una alumna que mira las reseñas de un estudio veía "Usuario Aura" en todas
-- las ajenas: la RLS de `usuarios` sólo deja ver la fila propia y las alumnas
-- del estudio propio. O sea que las reseñas eran anónimas justo para quien
-- las usa para decidir si reserva.
--
-- Esta RPC devuelve el nombre ABREVIADO ("Juana S."). La decisión de
-- seguridad es DÓNDE se abrevia: se hace acá, en SQL, no en Dart. Si se
-- abreviara en el cliente, el apellido completo viajaría igual en la
-- respuesta y se vería con las herramientas del navegador. Así el apellido
-- NUNCA sale del servidor.
--
-- Qué NO puede hacer, por construcción:
--   · devolver email, avatar o cualquier otra columna: la firma es (id, nombre);
--   · enumerar el padrón (90 usuarias): sólo responde por quien DEJÓ una
--     reseña — un dato que esa persona eligió publicar;
--   · usarse sin sesión: exige auth.uid().
--
-- El estudio sigue usando `estudio_nombres_alumnas`, que le da el nombre
-- completo: tiene relación directa con sus alumnas.

create or replace function public.resenas_nombres_publicos(p_ids uuid[])
 returns table(id uuid, nombre text)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select u.id,
         case
           -- Cuenta borrada: se respeta la lápida, igual que en los mails.
           when u.rol = 'eliminado' then 'Usuario Aura'
           when coalesce(trim(u.nombre), '') = '' then 'Usuario Aura'
           else split_part(trim(u.nombre), ' ', 1) ||
                case
                  when position(' ' in trim(u.nombre)) > 0
                    then ' ' ||
                         upper(left(split_part(trim(u.nombre), ' ', 2), 1)) ||
                         '.'
                  else ''
                end
         end as nombre
    from public.usuarios u
   where auth.uid() is not null
     and u.id = any (coalesce(p_ids, '{}'::uuid[]))
     and exists (
       select 1 from public.study_reviews r where r.usuario_id = u.id
     );
$function$;

-- Sólo con sesión. Una invitada sigue viendo "Usuario Aura", coherente con
-- que se le pide cuenta para el resto.
revoke all on function public.resenas_nombres_publicos(uuid[]) from public, anon;
grant execute on function public.resenas_nombres_publicos(uuid[]) to authenticated;
