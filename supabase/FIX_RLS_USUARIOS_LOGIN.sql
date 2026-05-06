-- AURA - Fix RLS para que cualquier usuario logueado pueda leer/actualizar su
-- propia fila en `public.usuarios` (2026-05-06).
--
-- Bug reportado: al hacer login con test@aura.com (rol usuario) y tambien con
-- el mail de un estudio, despues del signIn la app dispara PostgrestException.
-- Causa mas probable: la policy de SELECT en `public.usuarios` se rompio o
-- nunca existio, asi que el cliente logueado no puede leer su propio perfil
-- (la app hace `from('usuarios').select('rol').eq('id', uid)` despues del
-- signInWithPassword).


-- 1. DIAGNOSTICO: ver policies actuales sobre usuarios

select policyname, cmd, qual, with_check
  from pg_policies
 where schemaname = 'public'
   and tablename = 'usuarios'
 order by policyname;


-- 2. DIAGNOSTICO: confirmar que el usuario test existe en auth y en public

select id, email from auth.users where email = 'test@aura.com';
select id, email, nombre, rol, creditos from public.usuarios where email = 'test@aura.com';


-- 3. Asegurar que RLS esta activado

alter table public.usuarios enable row level security;


-- 4. FIX: policy de SELECT del propio perfil

drop policy if exists "Usuarios ven su perfil" on public.usuarios;
drop policy if exists "Usuarios leen su perfil" on public.usuarios;
drop policy if exists "users select own" on public.usuarios;

create policy "Usuarios ven su perfil"
  on public.usuarios
  for select
  to authenticated
  using (auth.uid() = id);


-- 5. FIX: policy de UPDATE del propio perfil (creditos, notifs, avatar, etc.)

drop policy if exists "Usuarios actualizan su perfil" on public.usuarios;
drop policy if exists "users update own" on public.usuarios;

create policy "Usuarios actualizan su perfil"
  on public.usuarios
  for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);


-- 6. FIX: policy de INSERT del propio perfil (red de seguridad si el trigger
--    de auth.users no creo la fila y Flutter cae al upsert de
--    `crearUsuarioSiNoExiste`).

drop policy if exists "Usuarios crean su perfil" on public.usuarios;
drop policy if exists "users insert own" on public.usuarios;

create policy "Usuarios crean su perfil"
  on public.usuarios
  for insert
  to authenticated
  with check (auth.uid() = id);


-- 7. (opcional) Si test@aura.com existe en auth.users pero NO en
--    public.usuarios, descomentar para crearlo:

-- insert into public.usuarios (id, email, nombre, rol, creditos)
-- select id, email, 'Usuario Test', 'usuario', 60
--   from auth.users
--  where email = 'test@aura.com'
--    and id not in (select id from public.usuarios);


-- 8. VERIFICACION final: re-correr (1) y confirmar que estan las 3 policies.
