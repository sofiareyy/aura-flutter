-- El aviso al celular espera la respuesta 30 s en vez de 5 (3/11/2026).
-- Solo cambia timeout_milliseconds en el net.http_post; el resto es igual a
-- lo que corría en producción. Volver atrás: sacar esa línea y re-aplicar.

CREATE OR REPLACE FUNCTION public.notif_push_nueva()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_secret text;
  v_url  text := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/push-enviar';
  -- anon key (publica: la misma que va en el bundle; solo pasa el gateway)
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk';
begin
  select decrypted_secret into v_secret
    from vault.decrypted_secrets
   where name = 'push_trigger_secret';

  -- INERTE hasta el paso 3.
  if v_secret is null or v_secret = '' then
    return new;
  end if;

  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_anon,
      'apikey',        v_anon,
      'x-push-secret', v_secret
    ),
    body    := jsonb_build_object('notificacion_id', new.id),
    -- 30 s (3/11/2026): con el default de 5 s, cuando salen muchos avisos a la
    -- vez (el regalo a 25) la función tarda en arrancar y la base deja de
    -- esperar: el aviso probablemente sale, pero no queda confirmado.
    timeout_milliseconds := 30000
  );
  return new;
exception when others then
  return new;   -- nunca romper la operacion que genero la notificacion
end
$function$;
