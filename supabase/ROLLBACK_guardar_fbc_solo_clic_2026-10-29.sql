-- Vuelta atrás de FIX_guardar_fbc_solo_clic_2026-10-29.sql: la versión que
-- corría en producción el 29/10/2026 (con el envío de CompleteRegistration
-- adentro). Sacada con pg_get_functiondef antes de cambiarla.

CREATE OR REPLACE FUNCTION public.guardar_fbc(p_fbc text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_clic timestamptz;
  v_auth text;
begin
  if v_uid is null or p_fbc is null then
    return;
  end if;

  if length(p_fbc) > 600
     or p_fbc !~ '^fb\.1\.\d{13}\.[A-Za-z0-9_-]{10,}$' then
    return;
  end if;

  v_clic := to_timestamp(split_part(p_fbc, '.', 3)::bigint / 1000.0);
  if v_clic > now() + interval '1 day' then
    v_clic := now();
  end if;

  insert into public.atribucion_meta (usuario_id, fbc, clic_at)
  values (v_uid, p_fbc, v_clic)
  on conflict (usuario_id, fbc) do nothing;

  begin
    v_auth := (coalesce(current_setting('request.headers', true), '{}')::jsonb ->> 'authorization');
    if v_auth is not null and v_auth <> '' then
      perform net.http_post(
        url := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/meta-capi-event',
        body := jsonb_build_object(
          'event_name', 'CompleteRegistration',
          'event_id', 'registration:' || v_uid::text,
          'event_source_url', 'https://somosaurapass.com/#/landing'
        ),
        params := '{}'::jsonb,
        headers := jsonb_build_object(
          'Authorization', v_auth,
          'Content-Type', 'application/json'
        ),
        timeout_milliseconds := 5000
      );
    end if;
  exception when others then
    raise warning 'guardar_fbc: no se pudo encolar CompleteRegistration: %', sqlerrm;
  end;
end;
$function$

;
revoke all on function public.guardar_fbc(text) from public, anon;
grant execute on function public.guardar_fbc(text) to authenticated;
