-- 16/11/2026 · "Cancelar reserva" del backoffice (pedido de Sofía).
--
-- La vieja admin_cancel_reserva sólo hacía estado = 'cancelada': no devolvía
-- créditos ni el lugar, no avisaba, y dejaba cancelar reservas pasadas
-- (completada/presente), que además dejaban de liquidarse al estudio.
--
-- admin_cancelar_reserva hace lo mismo que la cancelación del panel del
-- estudio (estudio_cancelar_clase), pero para UNA reserva:
--   · sólo 'confirmada' o 'pre_confirmada' de una clase que todavía no empezó
--   · estado 'cancelada_por_estudio' (no se liquida)
--   · devuelve los créditos con un lote nuevo a 90 días, como el panel
--     (una pre_confirmada todavía no pagó: no hay nada que devolver)
--   · libera el lugar (nunca por encima del total)
--   · campanita + mail (cancelacion-email con alcance 'reserva')
--   · deja registro en el historial del admin
--
-- La vieja queda con la MISMA firma pero frena con un error: no se borra
-- (borrar funciones va con OK de Sofía) y así la web vieja no puede volver a
-- cancelar sin devolver.
--
-- ROLLBACK: drop function public.admin_cancelar_reserva(bigint); y volver a
-- crear admin_cancel_reserva con el cuerpo de supabase/ROLLBACK_admin_cancel_reserva_2026-11-16.sql

create or replace function public.admin_cancelar_reserva(p_reserva_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_r         public.reservas%rowtype;
  v_clase     public.clases%rowtype;
  v_estudio   text;
  v_ahora     timestamp := (now() at time zone 'America/Argentina/Buenos_Aires');
  v_creditos  int := 0;
  v_secret    text;
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk';
begin
  if not public.is_admin() then
    return jsonb_build_object('ok', false, 'error', 'no_autorizado');
  end if;

  select * into v_r from public.reservas where id = p_reserva_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_encontrada');
  end if;

  if v_r.estado not in ('confirmada', 'pre_confirmada') then
    return jsonb_build_object('ok', false, 'error', 'estado_invalido',
                              'estado', v_r.estado);
  end if;

  select * into v_clase from public.clases where id = v_r.clase_id for update;
  if v_clase.id is null or v_clase.fecha is null or v_clase.fecha <= v_ahora then
    return jsonb_build_object('ok', false, 'error', 'clase_pasada');
  end if;

  select e.nombre into v_estudio from public.estudios e where e.id = v_clase.estudio_id;

  -- Sólo una confirmada pagó. Una pre_confirmada (lista de espera) no.
  if v_r.estado = 'confirmada' then
    v_creditos := coalesce(v_r.creditos_usados, 0);
  end if;

  update public.reservas set estado = 'cancelada_por_estudio' where id = v_r.id;

  update public.clases
     set lugares_disponibles = least(
           coalesce(lugares_disponibles, 0) + 1,
           coalesce(lugares_total, coalesce(lugares_disponibles, 0) + 1))
   where id = v_clase.id;

  if v_r.usuario_id is not null then
    if v_creditos > 0 then
      perform public.grant_user_credits(
        v_r.usuario_id, v_creditos, 'devolucion_clase_cancelada',
        (now() + interval '90 days')::text,
        'Devolución por reserva cancelada: ' || coalesce(v_clase.nombre, 'clase'));
    end if;

    insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
    values (v_r.usuario_id, '❌ Reserva cancelada',
            'Cancelamos tu reserva de "' || coalesce(v_clase.nombre, 'la clase') || '".'
            || case when v_creditos > 0 then ' Te devolvimos tus créditos.' else '' end,
            'clase_cancelada', false);

    -- Mail: lo último y lo menos importante, nunca corta la cancelación.
    begin
      v_secret := (select decrypted_secret from vault.decrypted_secrets
                    where name = 'notif_trigger_secret');
      perform net.http_post(
        url := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/cancelacion-email',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_anon,
          'apikey', v_anon,
          'x-notif-secret', coalesce(v_secret, '')),
        body := jsonb_build_object(
          'clase_id', v_clase.id,
          'alcance', 'reserva',
          'clase', jsonb_build_object(
            'nombre', v_clase.nombre,
            'fecha', v_clase.fecha,
            'tipo', coalesce(v_clase.tipo, 'clase'),
            'estudio_nombre', v_estudio),
          'destinatarios', jsonb_build_array(jsonb_build_object(
            'reserva_id', v_r.id,
            'usuario_id', v_r.usuario_id,
            'creditos', v_creditos))));
    exception when others then
      null;
    end;
  end if;

  perform public.log_admin_action(
    'Cancelar reserva',
    'Reserva #' || v_r.id || ' · ' || coalesce(v_clase.nombre, 'clase') ||
      ' · ' || v_creditos || ' créditos devueltos',
    'reservas');

  return jsonb_build_object('ok', true, 'creditos_devueltos', v_creditos,
                            'clase_id', v_clase.id);
end;
$function$;

revoke all on function public.admin_cancelar_reserva(bigint) from public, anon;
grant execute on function public.admin_cancelar_reserva(bigint) to authenticated;

-- La vieja: misma firma, ahora frena.
create or replace function public.admin_cancel_reserva(p_reserva_id bigint)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  raise exception 'Esta versión del backoffice está desactualizada: recargá la página.';
end;
$function$;

-- Listado con la fecha de la clase, para no ofrecer cancelar una pasada.
create or replace function public.admin_list_reservas_v2(p_search text default null)
returns table(id bigint, estado text, creditos_usados integer, usuario_nombre text,
              estudio_nombre text, clase_nombre text, clase_fecha timestamp)
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  return query
  select r.id, r.estado, coalesce(r.creditos_usados, 0)::int,
         coalesce(u.nombre, 'Usuario'), coalesce(e.nombre, 'Estudio'),
         coalesce(c.nombre, 'Clase'), c.fecha::timestamp
    from public.reservas r
    left join public.usuarios u on u.id = r.usuario_id
    left join public.clases c on c.id = r.clase_id
    left join public.estudios e on e.id = c.estudio_id
   where p_search is null
      or coalesce(u.nombre, '') ilike '%' || p_search || '%'
      or coalesce(e.nombre, '') ilike '%' || p_search || '%'
      or coalesce(c.nombre, '') ilike '%' || p_search || '%'
   order by r.created_at desc
   limit 150;
end;
$function$;

revoke all on function public.admin_list_reservas_v2(text) from public, anon;
grant execute on function public.admin_list_reservas_v2(text) to authenticated;
