-- ═══════════════════════════════════════════════════════════════════════════
-- FIX v2 · la RPC de nombres devuelve también avatar_url (foto)
-- 2026-08-25 · pedido en la revisión: mostrar email y foto del asistente
--
-- Cambia el tipo de retorno (suma avatar_url), asi que hay que DROP + CREATE.
-- Sigue devolviendo SOLO datos de presentacion (id, nombre, email, avatar_url),
-- nunca la fila entera, y solo de alumnas con reserva en clases del estudio.
-- ═══════════════════════════════════════════════════════════════════════════

drop function if exists public.estudio_nombres_alumnas(uuid[]);

create function public.estudio_nombres_alumnas(p_ids uuid[])
returns table (id uuid, nombre text, email text, avatar_url text)
language sql
stable
security definer
set search_path to 'public'
as $function$
  select u.id, u.nombre, u.email, u.avatar_url
    from public.usuarios u
   where u.id = any (coalesce(p_ids, '{}'::uuid[]))
     and auth.uid() is not null
     and public.es_alumna_de_mi_estudio(u.id);
$function$;

revoke execute on function public.estudio_nombres_alumnas(uuid[]) from public, anon;
grant  execute on function public.estudio_nombres_alumnas(uuid[]) to authenticated, service_role;

notify pgrst, 'reload schema';
