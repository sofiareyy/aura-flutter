-- ============================================================================
-- El mail de cancelación deja de depender de que la clase siga existiendo
-- (17/9/2026)
-- ============================================================================
--
-- Bug: el mail sólo llegaba si la clase se CANCELABA. Si se BORRABA —"eliminar
-- clase", "eliminar horario fijo", "eliminar en lote" y "despublicar al apagar
-- un horario"— la app cancela y acto seguido borra la clase. El aviso sale por
-- `net.http_post`, que es asíncrono y dispara DESPUÉS del commit: para cuando
-- la edge function iba a buscar los datos, la clase ya no estaba (y por el
-- CASCADE, sus reservas tampoco).
--
-- Medido el 16/9 llamando a la función real con dry_run:
--   clase inexistente          -> 404 {"error":"Clase no encontrada"}, 0 mails
--   clase sin reservas vivas   -> 200 {"reservas":0,"enviados":0}
-- La campanita sí llegaba siempre, porque se escribe dentro de la transacción.
--
-- Arreglo: la RPC manda en el body TODO lo que el mail necesita —una foto de
-- la clase y la lista de destinatarios— tomada ANTES de que nada se borre. La
-- edge function ya no tiene que ir a buscar nada a `clases` ni a `reservas`.
-- Lo único que sigue leyendo de la base son los mails de las cuentas, que no
-- se borran con la clase.
-- ============================================================================

create or replace function public.estudio_cancelar_clase(p_clase_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_clase public.clases%rowtype;
  v_r public.reservas%rowtype;
  v_ahora timestamptz := now();
  v_creditos bigint := 0;
  v_afectadas int := 0;
  v_secret text;
  v_estudio text;
  v_destinatarios jsonb := '[]'::jsonb;
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk';
begin
  select * into v_clase from public.clases where id = p_clase_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'clase_inexistente');
  end if;
  if coalesce(v_clase.cancelada, false) then
    return jsonb_build_object('ok', false, 'error', 'ya_cancelada');
  end if;

  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'sin_sesion');
  end if;

  if not exists (
    select 1 from public.estudio_admins ea
     where ea.estudio_id = v_clase.estudio_id
       and ea.usuario_id = v_uid
       and ea.rol in ('estudio', 'admin_estudio')
  ) then
    return jsonb_build_object('ok', false, 'error', 'sin_permisos');
  end if;

  select e.nombre into v_estudio from public.estudios e where e.id = v_clase.estudio_id;

  for v_r in
    select * from public.reservas
     where clase_id = p_clase_id
       and estado in ('confirmada', 'presente', 'pre_confirmada')
     for update
  loop
    -- 2026-08-26: `usuario_id` puede ser NULL (reserva de una cuenta borrada,
    -- conservada como evidencia de cobro). No hay a quién devolverle los
    -- créditos: se saltea la devolución, pero la reserva SÍ se cancela.
    -- Sin este guard, grant_user_credits tira "p_user_id es null" y se cae la
    -- cancelación entera.
    if v_r.usuario_id is not null and coalesce(v_r.creditos_usados, 0) > 0 then
      perform public.grant_user_credits(
        v_r.usuario_id,
        v_r.creditos_usados::int,
        'devolucion_clase_cancelada',
        (v_ahora + interval '90 days')::text,
        'Devolución por clase cancelada: ' || coalesce(v_clase.nombre, 'clase')
      );
      v_creditos := v_creditos + v_r.creditos_usados;
    end if;

    update public.reservas set estado = 'cancelada_por_estudio' where id = v_r.id;
    v_afectadas := v_afectadas + 1;

    if v_r.usuario_id is not null then
      insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
      values (v_r.usuario_id, '❌ Clase cancelada',
              'Se canceló "' || coalesce(v_clase.nombre, 'la clase') ||
              '". Te devolvimos tus créditos.', 'clase_cancelada', false);

      -- La FOTO del destinatario, tomada ahora: si después borran la clase,
      -- el mail sale igual porque ya no depende de la base.
      v_destinatarios := v_destinatarios || jsonb_build_object(
        'reserva_id', v_r.id,
        'usuario_id', v_r.usuario_id,
        'creditos', coalesce(v_r.creditos_usados, 0));
    end if;
  end loop;

  update public.clases set cancelada = true where id = p_clase_id;

  -- MAIL (2026-09-02, con foto desde el 17/9). Fuera del loop: una llamada, la
  -- function manda uno por persona. Envuelto para que un fallo de red no tumbe
  -- la cancelación.
  if v_afectadas > 0 then
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
          'clase_id', p_clase_id,
          -- La foto: con esto la edge function no necesita leer `clases` ni
          -- `reservas`, que pueden estar borradas para cuando ella corra.
          'clase', jsonb_build_object(
            'nombre', v_clase.nombre,
            'fecha', v_clase.fecha,
            'tipo', coalesce(v_clase.tipo, 'clase'),
            'estudio_nombre', v_estudio),
          'destinatarios', v_destinatarios)
      );
    exception when others then
      null; -- el mail es lo último y lo menos importante: nunca corta esto
    end;
  end if;

  return jsonb_build_object('ok', true, 'reservas_afectadas', v_afectadas,
                            'creditos_devueltos', v_creditos);
end;
$function$;
