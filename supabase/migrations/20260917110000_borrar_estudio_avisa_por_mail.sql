-- ============================================================================
-- Borrar un estudio también manda el mail de cancelación (17/9/2026)
-- ============================================================================
--
-- Mismo agujero que el del 17/9 en `estudio_cancelar_clase`, en el otro
-- camino: `admin_delete_estudio` cancela las reservas futuras, devuelve los
-- créditos y deja la campanita, pero **nunca mandaba mail**. Y es el caso
-- donde más falta hace: el estudio desaparece de Aura, la alumna tenía una
-- clase reservada y el push sólo llega a 13 de 82 personas.
--
-- Acá el mail NO PUEDE leer la base después: tres líneas más abajo se borran
-- las clases, las reservas y el estudio entero. Va la misma solución: una FOTO
-- en el body, tomada antes de la cascada. Se manda una llamada por clase
-- afectada, que es el formato que ya entiende `cancelacion-email`.
-- ============================================================================

create or replace function public.admin_delete_estudio(
  p_estudio_id bigint,
  p_nombre_confirmacion text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_ahora_ar  timestamp   := (now() at time zone 'America/Argentina/Buenos_Aires');
  v_ahora     timestamptz := now();
  v_nombre    text;
  v_r         record;
  v_clases    int := 0;
  v_reservas  int := 0;
  v_liq       int := 0;
  v_devueltas int := 0;
  v_creditos  bigint := 0;
  v_avisadas  int := 0;
  v_mails     jsonb := '{}'::jsonb;   -- clase_id -> {clase, destinatarios}
  v_clave     text;
  v_entrada   jsonb;
  v_secret    text;
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk';
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  select nombre into v_nombre from public.estudios where id = p_estudio_id;
  if v_nombre is null then
    raise exception 'El estudio no existe';
  end if;

  -- LA LLAVE: el nombre exacto (sin distinguir mayúsculas ni espacios de más).
  if lower(trim(coalesce(p_nombre_confirmacion, ''))) <> lower(trim(v_nombre)) then
    raise exception 'Para eliminar "%" hay que escribir su nombre exacto.', v_nombre;
  end if;

  select count(*) into v_clases from public.clases where estudio_id = p_estudio_id;
  select count(*) into v_reservas
    from public.reservas r join public.clases c on c.id = r.clase_id
   where c.estudio_id = p_estudio_id;
  select count(*) into v_liq from public.liquidaciones where estudio_id = p_estudio_id;

  -- 3a · Las reservas FUTURAS vivas se cancelan como una clase cancelada:
  --      créditos de vuelta al ledger + campanita. Mismos parámetros que
  --      estudio_cancelar_clase (vencimiento a 90 días, misma fuente).
  for v_r in
    select r.id, r.usuario_id, r.creditos_usados,
           c.id as clase_id, c.nombre as clase, c.fecha, coalesce(c.tipo,'clase') as tipo
      from public.reservas r join public.clases c on c.id = r.clase_id
     where c.estudio_id = p_estudio_id
       and c.fecha >= v_ahora_ar
       and r.estado in ('confirmada', 'presente', 'pre_confirmada')
     for update of r
  loop
    if v_r.usuario_id is not null and coalesce(v_r.creditos_usados, 0) > 0 then
      perform public.grant_user_credits(
        v_r.usuario_id,
        v_r.creditos_usados::int,
        'devolucion_clase_cancelada',
        (v_ahora + interval '90 days')::text,
        'Devolución: ' || v_nombre || ' ya no está en Aura (' || coalesce(v_r.clase, 'clase') || ')'
      );
      v_creditos := v_creditos + v_r.creditos_usados;
    end if;
    update public.reservas set estado = 'cancelada_por_estudio' where id = v_r.id;
    v_devueltas := v_devueltas + 1;
    if v_r.usuario_id is not null then
      insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
      values (v_r.usuario_id, '❌ Clase cancelada',
              'Se canceló "' || coalesce(v_r.clase, 'la clase') || '" del ' ||
              to_char(v_r.fecha, 'DD/MM') || ': ' || v_nombre ||
              ' ya no está en Aura. Te devolvimos tus créditos.',
              'clase_cancelada', false);
      v_avisadas := v_avisadas + 1;

      -- La FOTO para el mail, agrupada por clase. Se arma ACÁ porque abajo
      -- se borra todo y después no habría de dónde leerla.
      v_clave := v_r.clase_id::text;
      v_entrada := coalesce(
        v_mails -> v_clave,
        jsonb_build_object(
          'clase', jsonb_build_object(
            'nombre', v_r.clase,
            'fecha', v_r.fecha,
            'tipo', v_r.tipo,
            'estudio_nombre', v_nombre),
          'destinatarios', '[]'::jsonb));
      v_entrada := jsonb_set(
        v_entrada, '{destinatarios}',
        (v_entrada -> 'destinatarios') || jsonb_build_object(
          'reserva_id', v_r.id,
          'usuario_id', v_r.usuario_id,
          'creditos', coalesce(v_r.creditos_usados, 0)));
      v_mails := jsonb_set(v_mails, array[v_clave], v_entrada);
    end if;
  end loop;

  -- 3b · Cascada, en el orden que las FK exigen (clases y liquidaciones son
  --      NO ACTION sobre estudios). reservas y lista_espera caen con clases.
  delete from public.clases where estudio_id = p_estudio_id;
  delete from public.liquidaciones where estudio_id = p_estudio_id;
  update public.usuarios set estudio_id = null where estudio_id = p_estudio_id;
  delete from public.estudios where id = p_estudio_id;

  -- 3c · Los mails, una llamada por clase. Va al final y envuelto: el borrado
  --      ya está hecho y un fallo de red no puede tumbarlo.
  begin
    select decrypted_secret into v_secret
      from vault.decrypted_secrets where name = 'notif_trigger_secret';
    if coalesce(v_secret, '') <> '' then
      for v_clave, v_entrada in select * from jsonb_each(v_mails) loop
        perform net.http_post(
          url := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/cancelacion-email',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_anon,
            'apikey', v_anon,
            'x-notif-secret', v_secret),
          body := jsonb_build_object(
            'clase_id', v_clave::bigint,
            'clase', v_entrada -> 'clase',
            'destinatarios', v_entrada -> 'destinatarios'));
      end loop;
    end if;
  exception when others then
    null; -- el mail nunca puede voltear el borrado
  end;

  perform public.log_admin_action(
    'Eliminar estudio',
    v_nombre || ' (#' || p_estudio_id || ') · ' || v_clases || ' clases, ' ||
      v_reservas || ' reservas, ' || v_liq || ' liquidaciones, ' ||
      v_creditos || ' créditos devueltos a ' || v_avisadas || ' alumna(s)',
    'estudios'
  );

  return jsonb_build_object(
    'ok',                  true,
    'nombre',              v_nombre,
    'clases',              v_clases,
    'reservas',            v_reservas,
    'liquidaciones',       v_liq,
    'reservas_canceladas', v_devueltas,
    'creditos_devueltos',  v_creditos,
    'alumnas_avisadas',    v_avisadas
  );
end;
$function$;
