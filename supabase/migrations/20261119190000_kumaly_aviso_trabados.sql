-- Kumaly: aviso diario de envíos trabados (19/11/2026).
--
-- Todos los días a las 10:00 de Argentina el cron mira si hay algo trabado y,
-- SÓLO si hay, llama a la edge function `kumaly-aviso`, que manda un mail a
-- la casilla del resumen diario (aura.hola.app@gmail.com). Si no hay nada,
-- no se llama a la función y no sale ningún mail.
--
-- "Trabado":
--   · Pendiente que ya falló 3 veces o más (media hora larga sin que Kumaly
--     lo tome): 404, 400, 401, 5xx o sin respuesta.
--   · Reserva que se cayó en las últimas 24 h porque Kumaly nunca la
--     confirmó (estado 'vencido'): ya se le devolvió a la alumna, pero el
--     estudio no la tuvo.
-- No cuenta como trabado un 409 sin_lugar: es una respuesta normal.

create or replace function public.kumaly_trabados()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select jsonb_build_object(
    'pendientes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', e.id, 'evento', e.evento,
               'estudio', e.payload->>'estudio', 'clase', e.payload->>'clase',
               'inicio', e.payload->>'inicio', 'alumna', e.payload->>'alumna',
               'intentos', e.intentos, 'ultimo_status', e.ultimo_status,
               'ultimo_error', left(coalesce(e.ultimo_error, ''), 200),
               'desde', e.created_at, 'limite', e.limite)
             order by e.created_at)
        from public.kumaly_envios e
       where e.estado = 'pendiente'
         and e.intentos >= 3
         and coalesce(e.ultimo_status, 0) not between 200 and 299), '[]'::jsonb),
    'vencidos_24h', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', e.id, 'evento', e.evento,
               'estudio', e.payload->>'estudio', 'clase', e.payload->>'clase',
               'inicio', e.payload->>'inicio', 'alumna', e.payload->>'alumna',
               'intentos', e.intentos, 'ultimo_status', e.ultimo_status,
               'ultimo_error', left(coalesce(e.ultimo_error, ''), 200),
               'resuelto_at', e.resuelto_at)
             order by e.resuelto_at)
        from public.kumaly_envios e
       where e.estado = 'vencido'
         and e.resuelto_at > now() - interval '24 hours'), '[]'::jsonb)
  )
$$;

create or replace function public.kumaly_hay_trabados()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select jsonb_array_length(t->'pendientes') + jsonb_array_length(t->'vencidos_24h') > 0
    from (select public.kumaly_trabados() t) x
$$;

revoke execute on function public.kumaly_trabados(), public.kumaly_hay_trabados()
  from public, anon, authenticated;
grant execute on function public.kumaly_trabados() to service_role;

select cron.schedule('kumaly-aviso-trabados', '0 13 * * *', $cron$
  select net.http_post(
    url     := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/kumaly-aviso',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret
                                       from vault.decrypted_secrets
                                      where name = 'edge_service_key')),
    body    := '{}'::jsonb,
    timeout_milliseconds := 30000)
  where public.kumaly_hay_trabados()
$cron$);
