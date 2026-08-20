-- ============================================================================
-- AURA — Email al estudio en cada reserva: columna opt-out + Vault + trigger
-- ============================================================================
-- Aplicado a mano vía la Management API el 2026-08-19 (NO por `supabase db push`).
-- Documentado acá para el repo, como el resto de los SQL aplicados a mano.
--
-- La edge function vive en supabase/functions/nueva-reserva-estudio-email/.
-- Este archivo es el lado BASE: columna opt-out, secreto en Vault, y el trigger
-- que dispara la function (vía pg_net) cuando una reserva pasa a 'confirmada'.
--
-- Verificado end-to-end el 2026-08-19: reserva real desde la app -> trigger ->
-- pg_net -> function -> Resend -> mail entregado (test:false, status 200).
--
-- Extensiones requeridas (ya activas en el proyecto): pg_net, supabase_vault.
-- ============================================================================


-- ── 1. Columna opt-out por estudio ──────────────────────────────────────────
-- Default TRUE = opt-out (los estudios reciben salvo que se los apague).
-- Durante el rollout se usó default FALSE + todos apagados para probar sin
-- mandar a nadie; en el "encendido" (paso 6) se pasó a TRUE (ver punto 5).
alter table public.estudios
  add column if not exists notif_email_reservas boolean not null default true;


-- ── 2. Secreto compartido en Vault ──────────────────────────────────────────
-- El trigger lee este secreto y lo manda en el header `x-notif-secret`; la
-- function lo compara contra su env NOTIF_TRIGGER_SECRET (mismo valor).
--
-- ⚠️ EL VALOR REAL NO VA EN EL REPO. Se crea una sola vez con el valor real
-- (el mismo que `supabase secrets set NOTIF_TRIGGER_SECRET=...`):
--
--   select vault.create_secret('<VALOR_REAL>', 'notif_trigger_secret',
--     'Auth del trigger de email de reservas');


-- ── 3. Función del trigger ──────────────────────────────────────────────────
create or replace function public.notif_email_nueva_reserva()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_secret text;
  v_url  text := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/nueva-reserva-estudio-email';
  -- anon key (pública — la misma que usa el cliente; solo pasa el gateway).
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk';
begin
  -- Disparar SOLO cuando la reserva PASA a 'confirmada'.
  if NEW.estado is distinct from 'confirmada' then
    return NEW;                                  -- pre_confirmada, cancelada, etc.
  end if;
  if TG_OP = 'UPDATE' and OLD.estado is not distinct from 'confirmada' then
    return NEW;                                  -- ya estaba confirmada -> no re-notificar
  end if;

  v_secret := (select decrypted_secret from vault.decrypted_secrets
                where name = 'notif_trigger_secret');

  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
      'Content-Type',   'application/json',
      'Authorization',  'Bearer ' || v_anon,
      'apikey',         v_anon,
      'x-notif-secret', coalesce(v_secret, '')
    ),
    body    := jsonb_build_object('reserva_id', NEW.id)
  );
  return NEW;
exception when others then
  return NEW;                                    -- nunca romper la reserva por un fallo de aviso
end;
$fn$;


-- ── 4. El trigger ───────────────────────────────────────────────────────────
drop trigger if exists trg_notif_email_nueva_reserva on public.reservas;
create trigger trg_notif_email_nueva_reserva
  after insert or update on public.reservas
  for each row execute function public.notif_email_nueva_reserva();


-- ── 5. Encendido para todos los estudios (paso 6, 2026-08-19) ────────────────
-- update public.estudios set notif_email_reservas = true;
-- alter table public.estudios alter column notif_email_reservas set default true;
