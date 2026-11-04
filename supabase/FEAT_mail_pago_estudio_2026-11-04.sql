-- ============================================================================
-- Mail "ya te transferimos" al estudio + nota separada en dos (4/11/2026)
--
-- Pedido de Sofía: cuando marca un pago como hecho, al estudio le llega un
-- mail con monto, mes, número de operación y el link a Cobros. Y la nota del
-- pago se separa en dos:
--   · liquidaciones.numero_operacion: lo ve el estudio (Cobros y el mail).
--   · liquidaciones_notas_internas.nota: solo Aura. Va en una tabla aparte
--     porque el estudio puede leer la fila entera de su liquidación (RLS de
--     fila): una columna privada en la misma fila quedaría a su alcance.
--
-- El mail:
--   · Automático UNA vez, cuando la liquidación pasa a 'pagado' (trigger).
--   · A mano desde el backoffice, las veces que haga falta (botón "Reenviar
--     mail de pago"), con el monto efectivo (fila + correcciones).
--   · Función pago-estudio-email. Registra mail_pago_at/_id/_envios.
--
-- comprobante_nota queda vacía y en desuso (no se borra la columna).
-- Volver atrás: ROLLBACK_mail_pago_estudio_2026-11-04.sql
-- ============================================================================

alter table public.liquidaciones
  add column if not exists numero_operacion text,
  add column if not exists mail_pago_at     timestamptz,
  add column if not exists mail_pago_id     text,
  add column if not exists mail_pago_envios integer not null default 0;

create table if not exists public.liquidaciones_notas_internas (
  liquidacion_id uuid primary key references public.liquidaciones(id) on delete cascade,
  nota           text not null,
  updated_at     timestamptz not null default now()
);
alter table public.liquidaciones_notas_internas enable row level security;
revoke all on public.liquidaciones_notas_internas from anon;
drop policy if exists "solo admin de Aura" on public.liquidaciones_notas_internas;
create policy "solo admin de Aura" on public.liquidaciones_notas_internas
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ── Las notas que ya existen (aprobadas por Sofía antes de aplicar) ─────────
-- Texto completo → nota interna. Número (6+ dígitos) → numero_operacion.
insert into public.liquidaciones_notas_internas (liquidacion_id, nota)
select id, comprobante_nota from public.liquidaciones
 where nullif(trim(comprobante_nota), '') is not null
on conflict (liquidacion_id) do nothing;

update public.liquidaciones l
   set numero_operacion = (regexp_match(l.comprobante_nota, '(\d{6,})'))[1]
 where nullif(trim(l.comprobante_nota), '') is not null
   and l.numero_operacion is null;

-- Citra Barre, octubre: el número cargado (176620185083) estaba mal. El de la
-- transferencia es 186562442137 (Sofía, 4/11/2026). La nota interna lo deja dicho.
update public.liquidaciones
   set numero_operacion = '186562442137'
 where id = '0169bb19-b7ba-44a9-b34e-0c4ee969403a';
update public.liquidaciones_notas_internas
   set nota = nota || ' (número equivocado; el correcto es 186562442137, corregido el 4/11/2026)',
       updated_at = now()
 where liquidacion_id = '0169bb19-b7ba-44a9-b34e-0c4ee969403a'
   and nota not like '%corregido el 4/11/2026%';

update public.liquidaciones
   set comprobante_nota = null
 where id in (select liquidacion_id from public.liquidaciones_notas_internas);

-- ── El número de operación es obligatorio para marcar un pago (4/11) ────────
-- Sin número el estudio no puede verificar la transferencia. Solo se exige al
-- pasar a 'pagado' (los pagos viejos, de agosto y septiembre, no lo tienen) y
-- no se puede borrar de un pago que ya lo tiene.
create or replace function public.liquidaciones_exige_numero()
returns trigger
language plpgsql
as $function$
begin
  if new.estado = 'pagado'
     and (tg_op = 'INSERT' or old.estado <> 'pagado')
     and nullif(trim(coalesce(new.numero_operacion, '')), '') is null then
    raise exception 'Falta el número de operación para marcar el pago'
      using errcode = 'check_violation';
  end if;
  if tg_op = 'UPDATE' and old.estado = 'pagado'
     and nullif(trim(coalesce(old.numero_operacion, '')), '') is not null
     and nullif(trim(coalesce(new.numero_operacion, '')), '') is null then
    raise exception 'No se puede borrar el número de operación de un pago hecho'
      using errcode = 'check_violation';
  end if;
  new.numero_operacion := nullif(trim(coalesce(new.numero_operacion, '')), '');
  return new;
end;
$function$;

drop trigger if exists trg_liquidaciones_exige_numero on public.liquidaciones;
create trigger trg_liquidaciones_exige_numero
  before insert or update on public.liquidaciones
  for each row execute function public.liquidaciones_exige_numero();

-- ── El disparo automático ───────────────────────────────────────────────────
create or replace function public.liquidacion_pagada_mail()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_secret text;
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk';
begin
  if new.estado <> 'pagado' then return new; end if;
  if tg_op = 'UPDATE' and old.estado = 'pagado' then return new; end if;
  if new.mail_pago_at is not null then return new; end if;

  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'notif_trigger_secret';
  if coalesce(v_secret, '') = '' then return new; end if;

  perform net.http_post(
    url     := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/pago-estudio-email',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_anon,
      'apikey', v_anon,
      'x-notif-secret', v_secret),
    body    := jsonb_build_object('liquidacion_id', new.id),
    timeout_milliseconds := 30000);
  return new;
exception when others then
  return new; -- el mail nunca voltea el pago
end;
$function$;

drop trigger if exists trg_liquidacion_pagada_mail on public.liquidaciones;
create trigger trg_liquidacion_pagada_mail
  after insert or update of estado on public.liquidaciones
  for each row execute function public.liquidacion_pagada_mail();
