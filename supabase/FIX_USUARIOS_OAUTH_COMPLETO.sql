-- ============================================================================
-- AURA - Fix completo alta de usuarios OAuth (Apple / Google) - 2026-06-22
-- ============================================================================
-- Correr ENTERO de una sola vez en el SQL Editor de Supabase.
--
-- Bug: usuarios que se registran con Apple/Google se crean en auth.users pero
-- NO en public.usuarios -> "registro no completado". Dos causas:
--   1) Faltaban / estaban rotas las policies RLS de public.usuarios, así que
--      el insert del cliente fallaba ("violates row-level security policy").
--   2) En Apple el email viene null en reintentos, lo que rompía el insert.
--
-- Este script:
--   A) Asegura las policies RLS correctas (select/insert/update del propio
--      perfil).
--   B) Backfillea los usuarios ya huérfanos (en auth.users pero no en usuarios).
--
-- Es idempotente: se puede correr varias veces sin problema.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 0. DIAGNÓSTICO INICIAL (opcional, solo informa)
-- ----------------------------------------------------------------------------

-- Policies actuales sobre usuarios
select policyname, cmd, qual, with_check
  from pg_policies
 where schemaname = 'public'
   and tablename = 'usuarios'
 order by policyname;

-- Cuántos usuarios están en auth.users pero NO en usuarios
select count(*) as usuarios_huerfanos
  from auth.users au
  left join public.usuarios u on u.id = au.id
 where u.id is null;


-- ----------------------------------------------------------------------------
-- A. POLICIES RLS de public.usuarios
-- ----------------------------------------------------------------------------

-- A.1 Asegurar que RLS está activado
alter table public.usuarios enable row level security;

-- A.2 SELECT: cada usuario ve su propio perfil
drop policy if exists "Usuarios ven su perfil" on public.usuarios;
drop policy if exists "Usuarios leen su perfil" on public.usuarios;
drop policy if exists "users select own" on public.usuarios;

create policy "Usuarios ven su perfil"
  on public.usuarios
  for select
  to authenticated
  using (auth.uid() = id);

-- A.3 INSERT: cada usuario crea su propia fila (alta OAuth desde el cliente)
drop policy if exists "Usuarios crean su perfil" on public.usuarios;
drop policy if exists "users insert own" on public.usuarios;

create policy "Usuarios crean su perfil"
  on public.usuarios
  for insert
  to authenticated
  with check (auth.uid() = id);

-- A.4 UPDATE: cada usuario actualiza su propia fila (créditos, avatar, etc.)
drop policy if exists "Usuarios actualizan su perfil" on public.usuarios;
drop policy if exists "users update own" on public.usuarios;

create policy "Usuarios actualizan su perfil"
  on public.usuarios
  for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);


-- ----------------------------------------------------------------------------
-- B. BACKFILL de usuarios huérfanos
-- ----------------------------------------------------------------------------
-- Para Apple sin email usamos el relay privado como fallback estable.

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


-- ----------------------------------------------------------------------------
-- C. VERIFICACIÓN FINAL
-- ----------------------------------------------------------------------------

-- Debe devolver 0
select count(*) as huerfanos_restantes
  from auth.users au
  left join public.usuarios u on u.id = au.id
 where u.id is null;

-- Las 3 policies deben estar presentes
select policyname, cmd
  from pg_policies
 where schemaname = 'public'
   and tablename = 'usuarios'
 order by cmd;

-- Últimos 5 usuarios creados
select id, email, nombre, rol
  from public.usuarios
 order by created_at desc
 limit 5;
