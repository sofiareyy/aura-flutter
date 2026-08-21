-- ============================================================================
-- AURA — PUSH, paso 2: base de datos
-- ============================================================================
-- Aplicado a mano vía la Management API el 2026-08-20.
-- Plan: supabase/pendientes/PUSH_NOTIFICACIONES.md
--
-- El secreto `push_trigger_secret` se creó en Vault en el paso 3 (valor real
-- NO incluido acá). El mismo valor está como env PUSH_TRIGGER_SECRET de la
-- edge push-enviar. Hasta que existió, el trigger estuvo INERTE a propósito.
-- ============================================================================

-- ===========================================================================
-- PUSH — Paso 2: base de datos (no depende de Firebase)
-- Plan: supabase/pendientes/PUSH_NOTIFICACIONES.md
-- ===========================================================================

-- ── Tabla de dispositivos ──────────────────────────────────────────────────
-- `token` es UNIQUE a proposito: FCM devuelve el MISMO token para el mismo
-- aparato. Si otra persona se loguea ahi, el token tiene que CAMBIAR DE DUENO,
-- no duplicarse; si no, le llegarian los push de la cuenta anterior.
create table if not exists public.dispositivos (
  id          bigserial primary key,
  usuario_id  uuid not null references auth.users(id) on delete cascade,
  token       text not null unique,
  plataforma  text not null check (plataforma in ('android','ios','web')),
  app_version text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists dispositivos_usuario_idx on public.dispositivos(usuario_id);

alter table public.dispositivos enable row level security;

-- El cliente SOLO lee. Escribir va por los RPC de abajo (ver por que).
revoke all on public.dispositivos from anon;
revoke all on public.dispositivos from authenticated;
grant select on public.dispositivos to authenticated;
grant all on public.dispositivos to service_role;

drop policy if exists dispositivos_select_own on public.dispositivos;
create policy dispositivos_select_own on public.dispositivos
  for select to authenticated
  using (usuario_id = auth.uid());


-- ── RPC de registro ────────────────────────────────────────────────────────
-- POR QUE UN RPC Y NO UN UPSERT DEL CLIENTE:
-- con upsert directo, la policy de UPDATE (usuario_id = auth.uid()) BLOQUEARIA
-- el traspaso, porque en ese momento la fila todavia es del usuario anterior.
-- Se romperia justo el caso de cerrar sesion y entrar con otra cuenta en el
-- mismo celular. Aca es security definer: reasigna el dueno sin pelearse con RLS.
create or replace function public.registrar_dispositivo(
  p_token       text,
  p_plataforma  text,
  p_app_version text default null)
returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_uid   uuid := auth.uid();
  v_token text := trim(coalesce(p_token, ''));
begin
  if v_uid is null then
    raise exception 'No autorizado';
  end if;
  if v_token = '' then
    raise exception 'token_requerido';
  end if;
  if p_plataforma is null or p_plataforma not in ('android','ios','web') then
    raise exception 'plataforma_invalida';
  end if;

  insert into public.dispositivos (usuario_id, token, plataforma, app_version)
  values (v_uid, v_token, p_plataforma, p_app_version)
  on conflict (token) do update
     set usuario_id  = v_uid,                    -- <- EL TRASPASO
         plataforma  = excluded.plataforma,
         app_version = excluded.app_version,
         updated_at  = now();
end
$fn$;

-- ── RPC de baja (logout) ───────────────────────────────────────────────────
-- Sin esto, al cerrar sesion le seguirian llegando los push de esa cuenta.
create or replace function public.borrar_dispositivo(p_token text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'No autorizado';
  end if;
  -- Solo el propio: no se puede desregistrar el dispositivo de otra persona.
  delete from public.dispositivos
   where token = trim(coalesce(p_token, ''))
     and usuario_id = v_uid;
end
$fn$;

revoke all on function public.registrar_dispositivo(text, text, text) from public, anon;
revoke all on function public.borrar_dispositivo(text) from public, anon;
grant execute on function public.registrar_dispositivo(text, text, text) to authenticated, service_role;
grant execute on function public.borrar_dispositivo(text) to authenticated, service_role;


-- ── Trigger: un solo punto de disparo ──────────────────────────────────────
-- Todo lo que hoy genera campanita (promocion de lista de espera, aviso a
-- profes, avisos del estudio) se convierte en push sin tocar esas funciones.
--
-- DOS CUIDADOS:
--  1. `exception when others then return new`: un fallo de push NUNCA puede
--     tumbar una reserva. Mismo patron que notif_email_nueva_reserva.
--  2. NACE INERTE: si el secreto `push_trigger_secret` no esta en Vault todavia
--     (se crea en el paso 3, junto con la edge), sale sin hacer nada. Asi el
--     trigger puede existir desde ahora sin golpear una edge inexistente.
create or replace function public.notif_push_nueva()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $fn$
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
    body    := jsonb_build_object('notificacion_id', new.id)
  );
  return new;
exception when others then
  return new;   -- nunca romper la operacion que genero la notificacion
end
$fn$;

drop trigger if exists trg_notif_push_nueva on public.notificaciones_usuario;
create trigger trg_notif_push_nueva
  after insert on public.notificaciones_usuario
  for each row execute function public.notif_push_nueva();
