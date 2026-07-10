-- AURA - Notificar a las profes cuando alguien reserva su clase (2026-07-10).
--
-- FEATURE 6: al reservar, se notifica in-app (campanita) a las profes del
-- estudio cuyo nombre coincide con el instructor de la clase. Cada profe puede
-- desactivar estas notificaciones (usuarios.notifs_reservas_profe).

-- 1. Toggle por profe ------------------------------------------------------
alter table public.usuarios add column if not exists notifs_reservas_profe boolean not null default true;

comment on column public.usuarios.notifs_reservas_profe is 'La profe recibe notificacion cuando alguien reserva una clase donde figura como instructor. Default true.';

-- 2. RPC: notifica a las profes asignadas (por nombre de instructor) --------
-- security definer: el reservante (usuario normal) no puede leer estudio_admins
-- ni insertar notificaciones de otros por RLS, así que esto corre elevado.
create or replace function public.notify_profes_nueva_reserva(
  p_clase_id      int,
  p_reservante_id uuid
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nombre     text;
  v_fecha      timestamp;
  v_estudio_id int;
  v_instructor text;
  v_reservante text;
  v_count      int := 0;
begin
  select c.nombre, c.fecha::timestamp, c.estudio_id, c.instructor
    into v_nombre, v_fecha, v_estudio_id, v_instructor
    from public.clases c
   where c.id = p_clase_id;

  if not found or coalesce(trim(v_instructor), '') = '' then
    return 0;
  end if;

  select coalesce(nullif(trim(nombre), ''), 'Alguien')
    into v_reservante
    from public.usuarios
   where id = p_reservante_id;

  insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
  select u.id,
         'Nueva reserva 🧡',
         coalesce(v_reservante, 'Alguien') || ' se anotó en tu clase de ' ||
           coalesce(v_nombre, 'una clase') || ' el ' ||
           to_char(v_fecha, 'DD/MM') || ' a las ' || to_char(v_fecha, 'HH24:MI'),
         'reserva_profe',
         false
    from public.usuarios u
    join public.estudio_admins ea on ea.usuario_id = u.id
   where ea.estudio_id = v_estudio_id
     and ea.rol = 'profe'
     and lower(trim(u.nombre)) = lower(trim(v_instructor))
     and coalesce(u.notifs_reservas_profe, true) = true;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

grant execute on function public.notify_profes_nueva_reserva(int, uuid)
  to authenticated, service_role;

-- Uso: select public.notify_profes_nueva_reserva(123, '<uuid>');
