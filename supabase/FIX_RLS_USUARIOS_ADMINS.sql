-- AURA - Fix RLS para que admins vean a sus pares del mismo estudio (2026-05-06)
-- Bug 20: en PerfilEstudioScreen la lista de administradores solo muestra al
-- usuario actual. Causa: la policy de SELECT sobre `usuarios` solo permite ver
-- la propia fila. Agregamos una policy adicional que deja a cualquier admin de
-- estudio ver a los otros admins del mismo estudio.


-- 1. DIAGNOSTICO: ver policies actuales sobre usuarios

select policyname, cmd, qual
  from pg_policies
 where schemaname = 'public' and tablename = 'usuarios'
 order by policyname;


-- 2. FIX: agregar policy de SELECT para admins del mismo estudio

drop policy if exists "Admins ven otros admins del mismo estudio" on public.usuarios;

create policy "Admins ven otros admins del mismo estudio"
  on public.usuarios
  for select
  to authenticated
  using (
    estudio_id is not null
    and estudio_id in (
      select u.estudio_id
        from public.usuarios u
       where u.id = auth.uid()
         and u.rol in ('estudio', 'admin_estudio')
         and u.estudio_id is not null
    )
    and rol in ('estudio', 'admin_estudio')
  );


-- 3. Verificacion (correr aparte)
-- select policyname, cmd from pg_policies
--  where schemaname = 'public' and tablename = 'usuarios'
--  order by policyname;
