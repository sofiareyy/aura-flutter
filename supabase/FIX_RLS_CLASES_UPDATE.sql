-- AURA - Fix RLS para que un estudio pueda actualizar sus clases (2026-05-06)
-- Bug: cambiar la categoria de una clase desde el panel del estudio devuelve
-- PostgrestException. Causa probable: falta policy de UPDATE en clases para
-- usuarios con rol 'estudio' / 'admin_estudio'.
--
-- IMPORTANTE: la columna real en usuarios es `estudio_id` (no
-- `estudio_asociado_id`). El policy original sugerido apunta a una columna
-- inexistente; este archivo lo corrige.


-- 1. DIAGNOSTICO: ver policies actuales

select policyname, cmd, qual, with_check
  from pg_policies
 where schemaname = 'public'
   and tablename = 'clases'
 order by policyname;


-- 2. (opcional) ver mapping del usuario logueado a estudio
-- select id, email, rol, estudio_id from public.usuarios where id = auth.uid();


-- 3. FIX: agregar policy de UPDATE para estudios

drop policy if exists "estudio actualiza sus clases" on public.clases;
drop policy if exists "estudios actualizan sus clases" on public.clases;
drop policy if exists "Estudios actualizan sus clases" on public.clases;

create policy "estudio actualiza sus clases"
  on public.clases
  for update
  to authenticated
  using (
    estudio_id in (
      select estudio_id
        from public.usuarios
       where id = auth.uid()
         and rol in ('estudio', 'admin_estudio')
         and estudio_id is not null
    )
  )
  with check (
    estudio_id in (
      select estudio_id
        from public.usuarios
       where id = auth.uid()
         and rol in ('estudio', 'admin_estudio')
         and estudio_id is not null
    )
  );


-- 4. Mismo patron para INSERT y DELETE por si tambien estaban faltando

drop policy if exists "estudio inserta sus clases" on public.clases;
create policy "estudio inserta sus clases"
  on public.clases
  for insert
  to authenticated
  with check (
    estudio_id in (
      select estudio_id
        from public.usuarios
       where id = auth.uid()
         and rol in ('estudio', 'admin_estudio')
         and estudio_id is not null
    )
  );

drop policy if exists "estudio elimina sus clases" on public.clases;
create policy "estudio elimina sus clases"
  on public.clases
  for delete
  to authenticated
  using (
    estudio_id in (
      select estudio_id
        from public.usuarios
       where id = auth.uid()
         and rol in ('estudio', 'admin_estudio')
         and estudio_id is not null
    )
  );


-- 5. Verificacion post-fix (correr aparte para chequear)
-- select policyname, cmd from pg_policies
--  where schemaname = 'public' and tablename = 'clases'
--  order by policyname;
