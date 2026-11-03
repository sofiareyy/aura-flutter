-- ============================================================================
-- Baja de mails + regalo de créditos por sorteo (3/11/2026)
--
-- 1. public.mail_bajas: quién pidió no recibir más mails de Aura que no sean
--    avisos de reservas/pagos. La escribe la edge function `mail-baja`.
-- 2. public.regalo_campana: el sorteo y todo lo que pasó con cada persona
--    (créditos, mail, push, recordatorio). Es el registro para medir.
-- 3. Funciones: regalo_sortear, regalo_otorgar, regalo_recordatorios.
-- 4. Cron diario `regalo-recordatorios` (10:00 de Argentina).
-- 5. Schema `metricas` con dos vistas para consultar desde el dashboard:
--    metricas.regalo_resumen y metricas.regalo_detalle.
--
-- Nada de esto regala ni manda nada solo: el sorteo y el regalo se corren a
-- mano (`select public.regalo_sortear(...)`, `select public.regalo_otorgar(...)`).
-- Volver atrás: ROLLBACK_baja_mails_y_regalo_2026-11-03.sql
-- ============================================================================

-- ── 1. Bajas ────────────────────────────────────────────────────────────────
create table if not exists public.mail_bajas (
  email       text primary key,           -- en minúsculas; la baja es por mail
  usuario_id  uuid,
  origen      text not null check (origen in ('link', 'gmail', 'manual')),
  created_at  timestamptz not null default now()
);
alter table public.mail_bajas enable row level security;
revoke all on public.mail_bajas from anon, authenticated;

create or replace function public.mail_dado_de_baja(p_email text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.mail_bajas where email = lower(trim(p_email)));
$$;
revoke all on function public.mail_dado_de_baja(text) from public, anon, authenticated;

-- ── 2. Registro del regalo ──────────────────────────────────────────────────
create table if not exists public.regalo_campana (
  campana                  text not null,
  usuario_id               uuid not null,   -- sin FK: si borran la cuenta, la fila queda para medir
  email                    text not null,
  grupo                    text not null check (grupo in ('regalo', 'sin_regalo')),
  sorteado_at              timestamptz not null default now(),
  salteado                 text,            -- por qué no se le dio (compró antes, cuenta borrada)
  monto                    int,
  lote_id                  bigint,          -- el lote en creditos_movimientos
  otorgado_at              timestamptz,
  vence                    date,
  mail_regalo_at           timestamptz,
  mail_regalo_estado       text,            -- enviado | omitido_baja | error: ...
  mail_regalo_id           text,            -- id de Resend
  intentos_regalo          int not null default 0,
  recordatorio_at          timestamptz,     -- cuándo se decidió recordarle (campanita + push)
  mail_recordatorio_at     timestamptz,
  mail_recordatorio_estado text,
  mail_recordatorio_id     text,
  intentos_recordatorio    int not null default 0,
  primary key (campana, usuario_id)
);
alter table public.regalo_campana enable row level security;
revoke all on public.regalo_campana from anon, authenticated;

-- Quién compró alguna vez: pagos aprobados (o suscripción cancelada, que
-- estuvo activa) o un lote de pack en el ledger (pago manual confirmado).
create or replace function public._compro_alguna_vez(p_uid uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.pagos p
                  where p.user_id = p_uid and p.status in ('approved', 'cancelled'))
      or exists (select 1 from public.creditos_movimientos cm
                  where cm.user_id = p_uid and cm.source = 'pack');
$$;
revoke all on function public._compro_alguna_vez(uuid) from public, anon, authenticated;

-- ── 3a. Sorteo ──────────────────────────────────────────────────────────────
-- Entre las alumnas que nunca compraron, con más de p_dias_minimos días de
-- cuenta, sin las internas ni las dadas de baja, elige p_cantidad al azar.
-- Anota a TODAS: las elegidas como 'regalo' y el resto como 'sin_regalo'
-- (sirve para comparar). No da créditos ni manda nada.
create or replace function public.regalo_sortear(p_campana text, p_cantidad int, p_dias_minimos int)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_total int;
begin
  if exists (select 1 from public.regalo_campana where campana = p_campana) then
    return jsonb_build_object('ok', false, 'error', 'ya_sorteada');
  end if;

  insert into public.regalo_campana (campana, usuario_id, email, grupo)
  select p_campana, e.id, e.email,
         case when row_number() over (order by random()) <= p_cantidad
              then 'regalo' else 'sin_regalo' end
    from (
      select u.id, lower(trim(u.email)) as email
        from public.usuarios u
        join auth.users au on au.id = u.id
       where coalesce(u.rol, 'usuario') = 'usuario'
         and coalesce(trim(u.email), '') <> ''
         and not public.es_cuenta_interna(u.email)
         and not public.mail_dado_de_baja(u.email)
         and not public._compro_alguna_vez(u.id)
         and au.created_at < now() - make_interval(days => p_dias_minimos)
    ) e;
  get diagnostics v_total = row_count;

  return jsonb_build_object('ok', true, 'elegibles', v_total,
    'regalo', (select count(*) from public.regalo_campana where campana = p_campana and grupo = 'regalo'),
    'sin_regalo', (select count(*) from public.regalo_campana where campana = p_campana and grupo = 'sin_regalo'));
end;
$$;
revoke all on function public.regalo_sortear(text, int, int) from public, anon, authenticated;

-- Pide a la edge function que mande los mails pendientes de una campaña.
-- Fire-and-forget: los créditos ya están dados; si el mail falla, queda
-- pendiente y el cron diario lo reintenta (hasta 3 veces).
create or replace function public._regalo_disparar_mails(p_campana text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_secret text;
  v_url  text := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/regalo-email';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk';
begin
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'notif_trigger_secret';
  if coalesce(v_secret, '') = '' then return; end if;
  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
      'Content-Type',   'application/json',
      'Authorization',  'Bearer ' || v_anon,
      'apikey',         v_anon,
      'x-notif-secret', v_secret),
    body    := jsonb_build_object('campana', p_campana),
    timeout_milliseconds := 120000);
exception when others then
  null; -- el mail nunca voltea el regalo
end;
$$;
revoke all on function public._regalo_disparar_mails(text) from public, anon, authenticated;

-- ── 3b. Regalo ──────────────────────────────────────────────────────────────
-- A las del grupo 'regalo' que todavía no lo recibieron: acredita, avisa por
-- campanita (el trigger la manda como push) y dispara el mail.
create or replace function public.regalo_otorgar(p_campana text, p_monto int, p_dias int)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_row     record;
  v_vence   date := (now() at time zone 'America/Argentina/Buenos_Aires')::date + p_dias;
  v_lote    bigint;
  v_dados   int := 0;
  v_salt    int := 0;
begin
  if p_monto is null or p_monto <= 0 or p_dias is null or p_dias <= 0 then
    return jsonb_build_object('ok', false, 'error', 'parametros_invalidos');
  end if;

  for v_row in
    select c.usuario_id
      from public.regalo_campana c
     where c.campana = p_campana and c.grupo = 'regalo'
       and c.otorgado_at is null and c.salteado is null
     for update
  loop
    if not exists (select 1 from public.usuarios where id = v_row.usuario_id) then
      update public.regalo_campana set salteado = 'cuenta_borrada'
       where campana = p_campana and usuario_id = v_row.usuario_id;
      v_salt := v_salt + 1;
      continue;
    end if;
    if public._compro_alguna_vez(v_row.usuario_id) then
      update public.regalo_campana set salteado = 'compro_antes_del_regalo'
       where campana = p_campana and usuario_id = v_row.usuario_id;
      v_salt := v_salt + 1;
      continue;
    end if;

    perform public.grant_user_credits(
      p_user_id     => v_row.usuario_id,
      p_amount      => p_monto,
      p_source      => 'regalo_campana',
      p_expires_at  => v_vence::text,
      p_description => 'Regalo de Aura (' || p_campana || ')');

    select id into v_lote
      from public.creditos_movimientos
     where user_id = v_row.usuario_id and source = 'regalo_campana'
     order by id desc limit 1;

    update public.regalo_campana
       set monto = p_monto, lote_id = v_lote, otorgado_at = now(), vence = v_vence
     where campana = p_campana and usuario_id = v_row.usuario_id;

    insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
    values (v_row.usuario_id,
            '🧡 Te regalamos ' || p_monto || ' créditos',
            'Ya están en tu cuenta y alcanzan para una clase. Usalos antes del '
              || to_char(v_vence, 'DD/MM') || '.',
            'regalo_creditos', false);
    v_dados := v_dados + 1;
  end loop;

  if v_dados > 0 then
    perform public._regalo_disparar_mails(p_campana);
  end if;

  return jsonb_build_object('ok', true, 'otorgados', v_dados, 'salteados', v_salt, 'vence', v_vence);
end;
$$;
revoke all on function public.regalo_otorgar(text, int, int) from public, anon, authenticated;

-- ── 3c. Recordatorio (lo corre el cron todos los días) ──────────────────────
-- A los 10 días de recibido, si el regalo está entero y no venció: campanita
-- + push y mail. Una sola vez por persona. También reintenta mails pendientes.
create or replace function public.regalo_recordatorios()
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_hoy  date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_row  record;
  v_n    int := 0;
  v_camp text;
begin
  for v_row in
    select c.campana, c.usuario_id, cm.amount_remaining, cm.expires_at
      from public.regalo_campana c
      join public.creditos_movimientos cm on cm.id = c.lote_id
     where c.otorgado_at is not null
       and c.recordatorio_at is null
       and (c.otorgado_at at time zone 'America/Argentina/Buenos_Aires')::date + 10 <= v_hoy
       and cm.amount_remaining > 0
       and cm.amount_remaining = cm.amount_total      -- no usó nada del regalo
       and cm.expires_at >= v_hoy
       and exists (select 1 from public.usuarios u where u.id = c.usuario_id)
     for update of c
  loop
    update public.regalo_campana set recordatorio_at = now()
     where campana = v_row.campana and usuario_id = v_row.usuario_id;

    insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
    values (v_row.usuario_id,
            '⏳ Tus ' || v_row.amount_remaining || ' créditos vencen el ' || to_char(v_row.expires_at, 'DD/MM'),
            'Todavía no los usaste. Alcanzan para una clase: elegí la que quieras.',
            'regalo_creditos', false);
    v_n := v_n + 1;
  end loop;

  -- Mails pendientes (los nuevos recordatorios y los que fallaron antes).
  for v_camp in
    select distinct campana from public.regalo_campana
     where (otorgado_at is not null and mail_regalo_at is null and intentos_regalo < 3)
        or (recordatorio_at is not null and mail_recordatorio_at is null and intentos_recordatorio < 3)
  loop
    perform public._regalo_disparar_mails(v_camp);
  end loop;

  return jsonb_build_object('ok', true, 'recordatorios', v_n);
end;
$$;
revoke all on function public.regalo_recordatorios() from public, anon, authenticated;

-- ── 4. Cron: todos los días a las 10:00 de Argentina (13:00 UTC) ───────────
select cron.unschedule('regalo-recordatorios')
 where exists (select 1 from cron.job where jobname = 'regalo-recordatorios');
select cron.schedule('regalo-recordatorios', '0 13 * * *', $$select public.regalo_recordatorios()$$);

-- ── 5. Para medir: schema `metricas` (no lo expone la API) ──────────────────
create schema if not exists metricas;
revoke all on schema metricas from public, anon, authenticated;

-- Una fila por persona sorteada. "Reservó" = alguna reserva hecha DESPUÉS del
-- regalo (o del sorteo, para el grupo sin regalo) que no se canceló.
create or replace view metricas.regalo_detalle as
with r as (
  select c.campana, c.usuario_id,
         count(*) filter (where re.estado in ('confirmada', 'presente', 'completada')) as reservas,
         count(*) filter (where re.estado like 'cancelada%')                           as canceladas,
         min(re.created_at) filter (where re.estado in ('confirmada', 'presente', 'completada')) as primera_reserva_at
    from public.regalo_campana c
    join public.reservas re
      on re.usuario_id = c.usuario_id
     and re.created_at >= coalesce(c.otorgado_at, c.sorteado_at)
   group by c.campana, c.usuario_id
),
uso as (
  select c.campana, c.usuario_id, sum((e->>'taken')::int) as creditos_regalo_usados
    from public.regalo_campana c
    join public.reservas re
      on re.usuario_id = c.usuario_id
     and re.creditos_lotes is not null
     and re.estado in ('confirmada', 'presente', 'completada')
    cross join lateral jsonb_array_elements(re.creditos_lotes) e
   where c.lote_id is not null and (e->>'id')::bigint = c.lote_id
   group by c.campana, c.usuario_id
)
select c.campana,
       c.grupo,
       split_part(coalesce(u.nombre, ''), ' ', 1)           as nombre,
       c.email,
       c.sorteado_at::date                                  as sorteada,
       c.salteado,
       c.otorgado_at,
       c.vence,
       coalesce(r.reservas, 0) > 0                          as reservo,
       coalesce(r.reservas, 0)                              as reservas,
       coalesce(r.canceladas, 0)                            as canceladas,
       r.primera_reserva_at,
       coalesce(uso.creditos_regalo_usados, 0)              as creditos_regalo_usados,
       exists (select 1 from public.pagos p
                where p.user_id = c.usuario_id and p.status = 'approved'
                  and p.created_at >= coalesce(c.otorgado_at, c.sorteado_at)) as compro_despues,
       c.mail_regalo_estado,
       c.recordatorio_at is not null                        as se_le_recordo,
       c.mail_recordatorio_estado,
       public.mail_dado_de_baja(c.email)                    as dada_de_baja,
       u.id is null                                         as cuenta_borrada
  from public.regalo_campana c
  left join public.usuarios u on u.id = c.usuario_id
  left join r   on r.campana = c.campana and r.usuario_id = c.usuario_id
  left join uso on uso.campana = c.campana and uso.usuario_id = c.usuario_id;

create or replace view metricas.regalo_resumen as
select campana,
       grupo,
       count(*)                                              as personas,
       count(*) filter (where otorgado_at is not null)       as recibieron_regalo,
       count(*) filter (where reservo)                       as reservaron,
       round(100.0 * count(*) filter (where reservo) / nullif(count(*), 0), 1) as pct_reservaron,
       count(*) filter (where creditos_regalo_usados > 0)    as usaron_creditos_regalo,
       count(*) filter (where compro_despues)                as compraron,
       count(*) filter (where mail_regalo_estado = 'enviado') as mail_regalo_enviado,
       count(*) filter (where se_le_recordo)                 as se_les_recordo,
       count(*) filter (where dada_de_baja)                  as se_dieron_de_baja
  from metricas.regalo_detalle
 group by campana, grupo
 order by campana, grupo;

revoke all on all tables in schema metricas from public, anon, authenticated;
