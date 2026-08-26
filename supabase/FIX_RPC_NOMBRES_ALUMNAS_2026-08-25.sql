-- ═══════════════════════════════════════════════════════════════════════════
-- FIX · RPC limpia para los nombres de alumnas, y fuera la policy provisoria
-- 2026-08-25 · item 22 de la Tanda C
--
-- El 25/8 a la mañana se abrió `usuarios_select_alumnas_de_mis_clases` para
-- que Asistencia mostrara nombres (antes: 'Alumno' para todas). Una policy
-- habilita la FILA ENTERA: el estudio podia leer tambien creditos, plan,
-- codigo_referido, empresa_id, avatar_url de esa alumna. Mas de lo que la
-- pantalla necesita.
--
-- Ahora: una RPC SECURITY DEFINER que devuelve SOLO (id, nombre, email), y
-- solo de usuarias con una reserva no cancelada en una clase de un estudio
-- que quien llama administra (mismo criterio que la policy, via el helper
-- `es_alumna_de_mi_estudio`, que se conserva). La policy se dropea.
--
-- La usan tres pantallas del estudio (las tres leian `usuarios` directo):
--   asistencia_screen  -> lista de asistentes y nombre al escanear un QR
--   cobros_screen      -> nombres en la liquidacion
-- Cualquier otra lectura de `usuarios` del lado estudio es de su propia fila.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.estudio_nombres_alumnas(p_ids uuid[])
returns table (id uuid, nombre text, email text)
language sql
stable
security definer
set search_path to 'public'
as $function$
  select u.id, u.nombre, u.email
    from public.usuarios u
   where u.id = any (coalesce(p_ids, '{}'::uuid[]))
     and auth.uid() is not null
     and public.es_alumna_de_mi_estudio(u.id);
$function$;

revoke execute on function public.estudio_nombres_alumnas(uuid[]) from public, anon;
grant  execute on function public.estudio_nombres_alumnas(uuid[]) to authenticated, service_role;

drop policy if exists usuarios_select_alumnas_de_mis_clases on public.usuarios;

notify pgrst, 'reload schema';
