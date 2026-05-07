-- AURA - Habilitar que una cuenta pueda administrar multiples estudios
-- (2026-05-07).
--
-- Hasta hoy `usuarios.estudio_id` (un solo int) era a la vez "permiso" y
-- "workspace activo". Eso impedia ser admin de varios estudios.
--
-- Modelo nuevo:
--   * estudio_admins(estudio_id, usuario_id) -> permisos M:N
--   * usuarios.estudio_id queda como "estudio activo" (workspace seleccionado),
--     mutable. El usuario puede cambiarlo via RPC set_active_estudio.
--   * RLS de tablas operativas (clases, notificaciones_estudio_alumnos)
--     ahora chequea estudio_admins, no usuarios.estudio_id.


-- 1. TABLA estudio_admins -----------------------------------------------

create table if not exists public.estudio_admins (
  estudio_id  int  not null references public.estudios(id) on delete cascade,
  usuario_id  uuid not null references public.usuarios(id) on delete cascade,
  rol         text not null default 'admin_estudio'
    check (rol in ('estudio', 'admin_estudio')),
  created_at  timestamptz not null default now(),
  primary key (estudio_id, usuario_id)
);

create index if not exists estudio_admins_usuario_idx
  on public.estudio_admins (usuario_id);


-- 2. MIGRAR relaciones existentes ---------------------------------------

insert into public.estudio_admins (estudio_id, usuario_id, rol)
select u.estudio_id, u.id, u.rol
  from public.usuarios u
 where u.estudio_id is not null
   and u.rol in ('estudio', 'admin_estudio')
on conflict (estudio_id, usuario_id) do nothing;


-- 3. RLS en estudio_admins ----------------------------------------------

alter table public.estudio_admins enable row level security;

drop policy if exists "estudio_admins_select_self" on public.estudio_admins;
create policy "estudio_admins_select_self"
  on public.estudio_admins
  for select
  to authenticated
  using (usuario_id = auth.uid());

-- INSERT/UPDATE/DELETE solo via SECURITY DEFINER RPCs (no creamos policies
-- de escritura, asi solo se modifica desde las funciones).


-- 4. Actualizar RLS en clases para usar estudio_admins -------------------

drop policy if exists "estudio actualiza sus clases" on public.clases;
create policy "estudio actualiza sus clases"
  on public.clases
  for update
  to authenticated
  using (
    exists (
      select 1 from public.estudio_admins ea
       where ea.estudio_id = clases.estudio_id
         and ea.usuario_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.estudio_admins ea
       where ea.estudio_id = clases.estudio_id
         and ea.usuario_id = auth.uid()
    )
  );

drop policy if exists "estudio inserta sus clases" on public.clases;
create policy "estudio inserta sus clases"
  on public.clases
  for insert
  to authenticated
  with check (
    exists (
      select 1 from public.estudio_admins ea
       where ea.estudio_id = clases.estudio_id
         and ea.usuario_id = auth.uid()
    )
  );

drop policy if exists "estudio elimina sus clases" on public.clases;
create policy "estudio elimina sus clases"
  on public.clases
  for delete
  to authenticated
  using (
    exists (
      select 1 from public.estudio_admins ea
       where ea.estudio_id = clases.estudio_id
         and ea.usuario_id = auth.uid()
    )
  );


-- 5. Actualizar RLS en notificaciones_estudio_alumnos --------------------

drop policy if exists "notif_estudio_alumnos_insert" on public.notificaciones_estudio_alumnos;
create policy "notif_estudio_alumnos_insert"
  on public.notificaciones_estudio_alumnos
  for insert
  to authenticated
  with check (
    exists (
      select 1
        from public.clases c
        join public.estudio_admins ea on ea.estudio_id = c.estudio_id
       where c.id = clase_id
         and ea.usuario_id = auth.uid()
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
        join public.estudio_admins ea on ea.estudio_id = c.estudio_id
       where c.id = clase_id
         and ea.usuario_id = auth.uid()
    )
  );


-- 6. Actualizar RPC studio_promote_user_to_admin -------------------------
-- Antes: pisaba usuarios.estudio_id (rompia multi-estudio).
-- Ahora: inserta en estudio_admins (acumulativo) y solo setea estudio_id
-- como "activo" si el usuario no tenia uno.

create or replace function public.studio_promote_user_to_admin(
  p_estudio_id int,
  p_email      text
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id          uuid := auth.uid();
  v_caller_authorized  boolean;
  v_target_id          uuid;
  v_normalized_email   text := lower(trim(p_email));
begin
  if v_caller_id is null then
    return json_build_object('ok', false, 'error', 'no_auth');
  end if;
  if v_normalized_email = '' then
    return json_build_object('ok', false, 'error', 'email_required');
  end if;

  select exists (
    select 1 from public.estudio_admins
     where estudio_id = p_estudio_id
       and usuario_id = v_caller_id
  ) into v_caller_authorized;

  if not v_caller_authorized then
    return json_build_object('ok', false, 'error', 'forbidden');
  end if;

  select id into v_target_id
    from public.usuarios
   where lower(trim(email)) = v_normalized_email
   limit 1;

  if v_target_id is null then
    return json_build_object('ok', false, 'error', 'user_not_found');
  end if;

  insert into public.estudio_admins (estudio_id, usuario_id, rol)
  values (p_estudio_id, v_target_id, 'admin_estudio')
  on conflict (estudio_id, usuario_id) do nothing;

  -- Bumpear rol si el target era 'usuario'
  update public.usuarios
     set rol = 'admin_estudio'
   where id = v_target_id
     and rol = 'usuario';

  -- Si el target no tiene un estudio activo, le ponemos este
  update public.usuarios
     set estudio_id = p_estudio_id
   where id = v_target_id
     and estudio_id is null;

  return json_build_object('ok', true, 'user_id', v_target_id);
end;
$$;

grant execute on function public.studio_promote_user_to_admin(int, text)
  to authenticated;


-- 7. RPC: set_active_estudio (cambiar workspace) -------------------------

create or replace function public.set_active_estudio(
  p_estudio_id int
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id  uuid := auth.uid();
  v_authorized boolean;
begin
  if v_caller_id is null then
    return json_build_object('ok', false, 'error', 'no_auth');
  end if;

  select exists (
    select 1 from public.estudio_admins
     where estudio_id = p_estudio_id
       and usuario_id = v_caller_id
  ) into v_authorized;

  if not v_authorized then
    return json_build_object('ok', false, 'error', 'forbidden');
  end if;

  update public.usuarios
     set estudio_id = p_estudio_id
   where id = v_caller_id;

  return json_build_object('ok', true);
end;
$$;

grant execute on function public.set_active_estudio(int) to authenticated;


-- 8. RPC: remove_estudio_admin_access ------------------------------------

create or replace function public.remove_estudio_admin_access(
  p_estudio_id int,
  p_usuario_id uuid
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id          uuid := auth.uid();
  v_caller_authorized  boolean;
begin
  if v_caller_id is null then
    return json_build_object('ok', false, 'error', 'no_auth');
  end if;

  select exists (
    select 1 from public.estudio_admins
     where estudio_id = p_estudio_id
       and usuario_id = v_caller_id
  ) into v_caller_authorized;

  if not v_caller_authorized then
    return json_build_object('ok', false, 'error', 'forbidden');
  end if;

  delete from public.estudio_admins
   where estudio_id = p_estudio_id
     and usuario_id = p_usuario_id;

  -- Si el target tenia este estudio como activo, mover al primer otro que tenga
  update public.usuarios u
     set estudio_id = (
       select ea.estudio_id from public.estudio_admins ea
        where ea.usuario_id = p_usuario_id
        order by ea.created_at desc
        limit 1
     )
   where u.id = p_usuario_id
     and u.estudio_id = p_estudio_id;

  -- Si no le quedan estudios, bajarlo a rol 'usuario'
  update public.usuarios u
     set rol = 'usuario',
         estudio_id = null
   where u.id = p_usuario_id
     and not exists (
       select 1 from public.estudio_admins
        where usuario_id = p_usuario_id
     );

  return json_build_object('ok', true);
end;
$$;

grant execute on function public.remove_estudio_admin_access(int, uuid)
  to authenticated;


-- 9. RPC: list_my_studios (para el switcher en la app) -------------------

create or replace function public.list_my_studios()
returns table (
  estudio_id   int,
  nombre       text,
  foto_url     text,
  is_active    boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_active int;
begin
  if v_uid is null then
    return;
  end if;

  select estudio_id into v_active
    from public.usuarios where id = v_uid;

  return query
    select e.id,
           e.nombre,
           e.foto_url,
           (e.id = v_active)
      from public.estudio_admins ea
      join public.estudios e on e.id = ea.estudio_id
     where ea.usuario_id = v_uid
     order by e.nombre;
end;
$$;

grant execute on function public.list_my_studios() to authenticated;


-- VERIFICACION ---------------------------------------------------------

select count(*) as admins_migrados from public.estudio_admins;

select tablename, policyname, cmd
  from pg_policies
 where schemaname = 'public'
   and tablename in ('estudio_admins', 'clases', 'notificaciones_estudio_alumnos')
 order by tablename, policyname;

select proname, pg_get_function_arguments(oid)
  from pg_proc
 where proname in (
   'studio_promote_user_to_admin',
   'set_active_estudio',
   'remove_estudio_admin_access',
   'list_my_studios'
 );
