-- El mail de confirmación a la ALUMNA, cableado por BASE (decisión 29/8):
-- sale hoy para todas, sin esperar el build 27.
--
-- Dispara SOLO en los dos caminos reales de confirmación:
--   · INSERT con estado 'confirmada' (reservar_clase directo), o
--   · UPDATE pre_confirmada -> confirmada (confirm_pre_reserva, lista de espera).
-- ⚠️ NO dispara en cualquier transición a 'confirmada': "deshacer el check-in"
-- en Asistencia vuelve presente -> confirmada, y eso re-mandaría el mail.
create or replace function public.notif_email_confirmacion_alumna()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_secret text;
  v_url  text := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/email-confirmacion';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk';
begin
  if new.estado is distinct from 'confirmada' then return new; end if;
  if tg_op = 'UPDATE' and coalesce(old.estado,'') <> 'pre_confirmada' then return new; end if;

  v_secret := (select decrypted_secret from vault.decrypted_secrets where name='notif_trigger_secret');
  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object('Content-Type','application/json',
      'Authorization','Bearer '||v_anon,'apikey',v_anon,
      'x-notif-secret',coalesce(v_secret,'')),
    body := jsonb_build_object('reserva_id', new.id)
  );
  return new;
exception when others then return new;
end;
$$;

drop trigger if exists trg_notif_email_confirmacion_alumna on public.reservas;
create trigger trg_notif_email_confirmacion_alumna
  after insert or update on public.reservas
  for each row execute function public.notif_email_confirmacion_alumna();
