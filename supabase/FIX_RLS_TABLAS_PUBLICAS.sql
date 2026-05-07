-- AURA - Habilitar RLS en tablas que Supabase reportó como CRITICAL
-- (study_categories y notificaciones_estudio_alumnos). 2026-05-06.
--
-- Contexto de uso (revisado en el codigo):
--
--   * study_categories          -> read-only por API. Se lee en
--     EstudiosService.getCategorias() para mostrar el filtro de
--     categorias en Explorar. Las altas/bajas/modificaciones se hacen
--     desde el dashboard de Supabase, no desde la app.
--
--   * notificaciones_estudio_alumnos -> tabla de log. Solo se INSERTA
--     desde AvisoAlumnosService.enviarAviso() cuando un estudio manda
--     un aviso a alumnos de una clase. La app nunca la lee.


-- 1. study_categories: lectura abierta, escritura solo via service_role/dashboard.

alter table public.study_categories enable row level security;

drop policy if exists "study_categories_select_all" on public.study_categories;
create policy "study_categories_select_all"
  on public.study_categories
  for select
  to public
  using (true);

-- No creamos policies de INSERT/UPDATE/DELETE adrede: con RLS prendido
-- y sin policies de escritura, el anon/authenticated key no puede
-- modificar la tabla. Los cambios de categorias se hacen desde el
-- dashboard de Supabase (que usa service_role y bypassea RLS).


-- 2. notificaciones_estudio_alumnos: solo el estudio dueño de la clase
--    puede insertar/leer.

alter table public.notificaciones_estudio_alumnos enable row level security;

drop policy if exists "notif_estudio_alumnos_insert" on public.notificaciones_estudio_alumnos;
create policy "notif_estudio_alumnos_insert"
  on public.notificaciones_estudio_alumnos
  for insert
  to authenticated
  with check (
    exists (
      select 1
        from public.clases c
        join public.usuarios u on u.estudio_id = c.estudio_id
       where c.id = clase_id
         and u.id = auth.uid()
         and u.rol in ('estudio', 'admin_estudio')
    )
  );

drop policy if exists "notif_estudio_alumnos_select_owner" on public.notificaciones_estudio_alumnos;
create policy "notif_estudio_alumnos_select_owner"
  on public.notificaciones_estudio_alumnos
  for select
  to authenticated
  using (
    exists (
      select 1
        from public.clases c
        join public.usuarios u on u.estudio_id = c.estudio_id
       where c.id = clase_id
         and u.id = auth.uid()
         and u.rol in ('estudio', 'admin_estudio')
    )
  );

-- Sin UPDATE/DELETE adrede: la tabla es un log de auditoria, no se
-- toca despues de insertada. Si en el futuro hace falta limpiar,
-- service_role bypassea RLS desde el dashboard.


-- VERIFICACION
-- Después de correr lo de arriba, deberian aparecer estas policies:

select schemaname, tablename, policyname, cmd
  from pg_policies
 where schemaname = 'public'
   and tablename in ('study_categories', 'notificaciones_estudio_alumnos')
 order by tablename, policyname;
