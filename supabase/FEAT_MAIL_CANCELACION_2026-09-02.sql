-- =============================================================================
-- Mail de clase/experiencia cancelada (2026-09-02)
-- =============================================================================
-- Hasta hoy, cancelar una clase avisaba SOLO por campanita + push. Una alumna
-- sin push (o que usa la web) se enteraba recién al abrir la app. Para una
-- experiencia, que se reserva con anticipación y mueve plata, es poco.
--
-- Se suma el mail con el mismo patrón que los otros 5 (secreto del vault +
-- net.http_post), con dos decisiones propias de que es el PRIMER envío en LOTE:
--
--   · UNA sola llamada por clase, al final y fuera del loop. La edge function
--     `cancelacion-email` lee las reservas ya canceladas y manda un mail por
--     persona. Así 12 anotadas son 1 http_post y 12 mails individuales, en vez
--     de 12 http_post; y el manejo de un fallo parcial vive en TypeScript.
--   · Sólo si hubo reservas afectadas: cancelar una clase vacía no llama a nada.
--
-- El envío es fire-and-forget dentro de un bloque que traga cualquier error:
-- si el mail falla, la cancelación y la devolución de créditos igual se
-- completan. Nunca al revés.

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
    end if;
  end loop;

  update public.clases set cancelada = true where id = p_clase_id;

  -- MAIL (2026-09-02). Fuera del loop: una llamada, la function manda uno por
  -- persona. Envuelto para que un fallo de red no tumbe la cancelación.
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
        body := jsonb_build_object('clase_id', p_clase_id)
      );
    exception when others then
      null; -- el mail es lo último y lo menos importante: nunca corta esto
    end;
  end if;

  return jsonb_build_object('ok', true, 'reservas_afectadas', v_afectadas,
                            'creditos_devueltos', v_creditos);
end;
$function$;
