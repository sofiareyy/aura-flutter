-- ============================================================================
-- El cron del resumen diario: todos los días a las 11 de la mañana (16/9/2026)
-- ============================================================================
--
-- 11 AM argentina = 14:00 UTC. A esa hora los datos de ayer ya están cerrados y
-- es una hora en la que se puede actuar (escribirle a un estudio, por ejemplo);
-- a las 7 el mail se pierde entre lo de la noche.
--
-- El secreto sale del vault, igual que el resto de los avisos que dispara la
-- base. La function es idempotente por día: si el cron corriera dos veces, la
-- segunda no manda nada.
-- ============================================================================

select cron.schedule(
  'resumen-diario',
  '0 14 * * *',
  $cron$
  select net.http_post(
    url := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/resumen-diario',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk',
      'apikey', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk',
      'x-notif-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'notif_trigger_secret')),
    body := '{}'::jsonb);
  $cron$
);
