-- AURA - Backfill de usuarios huérfanos (2026-06-22).
--
-- Bug: usuarios que se registran con Apple o Google se crean en auth.users
-- pero NO se insertan en public.usuarios (la inserción desde el cliente
-- fallaba silenciosamente; en Apple además el email viene null en reintentos).
-- Resultado: "registro no completado" y sesión a medias.
--
-- El fix de cliente (ensureUsuarioCreado + listener onAuthStateChange) cubre a
-- los usuarios NUEVOS. Este SQL repara a los que YA quedaron huérfanos.


-- 1. DIAGNÓSTICO: ¿cuántos usuarios están en auth.users pero no en usuarios?

select au.id, au.email, au.raw_user_meta_data->>'full_name' as full_name,
       au.created_at
  from auth.users au
  left join public.usuarios u on u.id = au.id
 where u.id is null
 order by au.created_at desc;


-- 2. BACKFILL: crear la fila faltante en public.usuarios.
--    Para Apple sin email, usamos el relay privado como fallback estable.

insert into public.usuarios (id, email, nombre, rol, creditos)
select
  au.id,
  coalesce(au.email, au.id || '@privaterelay.appleid.com'),
  coalesce(
    nullif(trim(au.raw_user_meta_data->>'full_name'), ''),
    nullif(trim(au.raw_user_meta_data->>'name'), ''),
    nullif(split_part(coalesce(au.email, ''), '@', 1), ''),
    'Usuario'
  ),
  'usuario',
  0
from auth.users au
left join public.usuarios u on u.id = au.id
where u.id is null;


-- 3. VERIFICACIÓN: re-correr (1); no debería devolver filas.
--    Y confirmar los últimos 5 creados:

select id, email, nombre, rol
  from public.usuarios
 order by created_at desc
 limit 5;
