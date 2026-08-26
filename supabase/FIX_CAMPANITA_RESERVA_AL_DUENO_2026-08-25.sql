-- ═══════════════════════════════════════════════════════════════════════════
-- FIX · la campanita de nueva reserva le llega al DUEÑO, no solo a la profe
-- 2026-08-25 · reportado por Citra Barre
--
-- EL BUG
-- `_notify_profes_nueva_reserva_interno` insertaba la campanita SOLO para
-- usuarios con `estudio_admins.rol = 'profe'` cuyo NOMBRE coincidiera con
-- `clases.instructor`. Un dueño (`admin_estudio`) nunca recibia aviso de una
-- reserva en su estudio. No es que fallara: la feature no lo incluia.
-- Ademas salia con 0 si la clase no tenia instructor -- 277 de las 1797
-- clases futuras estan asi, o sea que esas no avisaban a NADIE.
-- Medido para la reserva 552 de Citra: 0 campanitas creadas, y Citra no
-- tiene ninguna profe cargada.
--
-- Se conserva intacto el camino de la profe. El dueño se suma por `union`
-- (deduplica si alguien es las dos cosas) y no depende del instructor.
-- Se excluye a quien hizo la reserva, para que la dueña que reserva en su
-- propia clase no se avise a si misma.
--
-- ⚠️ Insertar en `notificaciones_usuario` dispara `trg_notif_push_nueva`,
-- que encola un push real. Verificado el 24/8 que el encolado vive dentro de
-- la transaccion y el rollback lo borra, asi que probar con rollback es
-- seguro.
--
-- El guard del 20/8 en la RPC publica `notify_profes_nueva_reserva` (solo por
-- TU propia reserva) queda intacto: esto cambia unicamente el interno.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._notify_profes_nueva_reserva_interno(p_clase_id integer, p_reservante_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_nombre     text;
  v_fecha      timestamp;
  v_estudio_id int;
  v_instructor text;
  v_reservante text;
  v_count      int := 0;
begin
  -- Sin guard de identidad: lo llaman funciones SECURITY DEFINER que ya
  -- validaron permisos. La verificacion de que la reserva EXISTE se conserva,
  -- ahora contra p_reservante_id (antes iba contra auth.uid()).
  if p_reservante_id is null then
    return 0;
  end if;

  if not exists (
    select 1 from public.reservas r
     where r.clase_id = p_clase_id
       and r.usuario_id = p_reservante_id
  ) then
    return 0;
  end if;

  select c.nombre, c.fecha::timestamp, c.estudio_id, c.instructor
    into v_nombre, v_fecha, v_estudio_id, v_instructor
    from public.clases c
   where c.id = p_clase_id;

  -- 2026-08-25: antes salia con 0 si la clase no tenia instructor. Eso dejaba
  -- SIN AVISO a 277 de las 1797 clases futuras -- y de paso al dueño, que no
  -- depende del instructor. Ahora solo se corta si la clase no existe.
  if not found then
    return 0;
  end if;

  select coalesce(nullif(trim(nombre), ''), 'Alguien')
    into v_reservante
    from public.usuarios
   where id = p_reservante_id;

  -- 2026-08-25: el aviso va al DUEÑO ademas de a la profe.
  -- Antes solo insertaba para `rol = 'profe'` cuyo NOMBRE coincidiera con
  -- `clases.instructor`, asi que un dueño (admin_estudio) nunca recibia
  -- campanita por una reserva en su estudio: no es que fallara, es que la
  -- feature no lo incluia. Reportado por Citra Barre el 25/8.
  --   * profe: se conserva igual -- rol 'profe' + nombre == instructor.
  --   * dueño: cualquier 'estudio'/'admin_estudio' del estudio, sin depender
  --     del instructor.
  -- `union` (no `union all`) deduplica a quien entre por los dos caminos.
  -- Se excluye a quien hizo la reserva: si la dueña reserva en su propia
  -- clase, no se avisa a si misma.
  -- El interruptor sigue siendo `notifs_reservas_profe` (default true, sin
  -- UI hoy): es el de los avisos de reserva del lado estudio.
  insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
  select destino.id,
         'Nueva reserva 🧡',
         coalesce(v_reservante, 'Alguien') || ' se anotó en tu clase de ' ||
           coalesce(v_nombre, 'una clase') || ' el ' ||
           to_char(v_fecha, 'DD/MM') || ' a las ' || to_char(v_fecha, 'HH24:MI'),
         'reserva_profe',
         false
    from (
      select u.id
        from public.usuarios u
        join public.estudio_admins ea on ea.usuario_id = u.id
       where ea.estudio_id = v_estudio_id
         and ea.rol = 'profe'
         and coalesce(trim(v_instructor), '') <> ''
         and lower(trim(u.nombre)) = lower(trim(v_instructor))
         and coalesce(u.notifs_reservas_profe, true) = true
      union
      select u.id
        from public.usuarios u
        join public.estudio_admins ea on ea.usuario_id = u.id
       where ea.estudio_id = v_estudio_id
         and ea.rol in ('estudio', 'admin_estudio')
         and coalesce(u.notifs_reservas_profe, true) = true
    ) destino
   where destino.id is distinct from p_reservante_id;

  get diagnostics v_count = row_count;
  return v_count;
end $function$
;
