-- ============================================================================
-- BONO DE BIENVENIDA — ARMADO Y APAGADO (14/9/2026)
-- ============================================================================
--
-- Regala créditos por única vez a dos grupos que se miden POR SEPARADO:
--   · 'registradas' — ya tenían cuenta y NUNCA compraron un pack.
--                     Se otorga a mano desde Admin → Config, arrancando por
--                     las más activas recientemente.
--   · 'nuevas'      — se registran DESPUÉS de prender el bono. Se otorga solo,
--                     por trigger en `usuarios`.
--
-- ⚠️ ARRANCA APAGADO: con `bono_activo` en false ninguna función acredita nada
-- ni manda un solo aviso. Aplicar esta migración NO regala créditos.
--
-- Antecedente: en julio de 2026 se armó una feature de bienvenida que se
-- descartó el 29/8 y se borró el 1/9 (commit 8f33f7d). Dos cosas que salieron
-- mal ahí y acá NO se repiten:
--   1. El Dart llamaba al RPC EN CADA LOGIN y fallaba en silencio. Acá las
--      'nuevas' las acredita un TRIGGER en la base: cero llamadas por login,
--      y funciona igual si entra por mail, Google, Apple o desde la web.
--   2. Encender hacía backfill a TODOS los usuarios de una. Acá prender el
--      flag y otorgar son dos acciones distintas, y otorgar respeta un tope.
--
-- Créditos con source 'bono_bienvenida'. NUNCA disparan referido (mismo
-- criterio que gift card y corporativo).
-- ============================================================================


-- ── 1. Flags ────────────────────────────────────────────────────────────────
-- Mismo patrón que valor_credito_ars: configuracion_global (clave, valor).
insert into public.configuracion_global (clave, valor) values
  ('bono_activo',             'false'),
  ('bono_monto',              '16'),
  ('bono_tope_registradas',   '15'),
  ('bono_tope_nuevas',        '15'),
  ('bono_vencimiento_dias',   '60')
on conflict (clave) do nothing;
-- `bono_encendido_at` lo escribe admin_bono_prender: es la línea que separa
-- "ya registrada" de "nueva". Sin esa línea los dos grupos se pisan.


-- ── 2. Candado + auditoría ──────────────────────────────────────────────────
-- Una fila por usuaria: garantiza "una sola vez por cuenta" y guarda el grupo
-- y el lote, que es lo que después permite medir.
create table if not exists public.bono_otorgado (
  usuario_id  uuid primary key references public.usuarios(id) on delete cascade,
  grupo       text        not null check (grupo in ('registradas','nuevas')),
  monto       int         not null,
  lote_id     bigint,     -- fila de creditos_movimientos: el rastro para medir
  otorgado_at timestamptz not null default now()
);

create index if not exists idx_bono_otorgado_grupo on public.bono_otorgado (grupo);

alter table public.bono_otorgado enable row level security;
-- Sin policies: sólo funciones security definer y service_role la tocan.


-- ── 3. Helpers de lectura ───────────────────────────────────────────────────
create or replace function public.bono_esta_activo()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select lower(trim(valor)) = 'true' from public.configuracion_global where clave = 'bono_activo'),
    false);
$$;

grant execute on function public.bono_esta_activo() to authenticated, anon;

create or replace function public.bono_cfg(p_clave text, p_default int)
returns int language sql stable security definer set search_path = public as $$
  select coalesce(
    (select nullif(trim(valor), '')::int from public.configuracion_global where clave = p_clave),
    p_default);
$$;

revoke execute on function public.bono_cfg(text, int) from public, anon;


-- ── 4. Acreditar el bono a UNA usuaria ──────────────────────────────────────
-- Idempotente (bono_otorgado como candado, incluso contra carreras), gateada
-- por el flag y por el tope del grupo. Avisa por los tres canales:
-- campanita (que dispara el push sola, por trg_notif_push_nueva) y mail.
create or replace function public.acreditar_bono(p_user_id uuid, p_grupo text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_monto     int;
  v_tope      int;
  v_dados     int;
  v_dias      int;
  v_lote_id   bigint;
  v_vence     date;
  v_secret    text;
  v_url  text := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/bono-email';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk';
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'error', 'no_user');
  end if;
  if p_grupo is null or p_grupo not in ('registradas','nuevas') then
    return jsonb_build_object('ok', false, 'error', 'grupo_invalido');
  end if;

  -- Apagado → no hace absolutamente nada.
  if not public.bono_esta_activo() then
    return jsonb_build_object('ok', true, 'otorgado', false, 'motivo', 'apagado');
  end if;

  if exists (select 1 from public.bono_otorgado where usuario_id = p_user_id) then
    return jsonb_build_object('ok', true, 'otorgado', false, 'motivo', 'ya_otorgado');
  end if;

  -- Sólo usuarias finales: ni estudios, ni profes, ni admin.
  if not exists (
    select 1 from public.usuarios u
     where u.id = p_user_id and coalesce(u.rol, 'usuario') = 'usuario'
  ) then
    return jsonb_build_object('ok', true, 'otorgado', false, 'motivo', 'no_es_usuaria');
  end if;

  -- El grupo 'registradas' es, por definición, quien NUNCA compró un pack.
  -- Se miran los dos lados (pagos y ledger) porque un pago manual confirmado
  -- acredita por el ledger sin dejar el mismo rastro.
  if p_grupo = 'registradas' and (
       exists (select 1 from public.pagos pg
                where pg.user_id = p_user_id and pg.status = 'approved'
                  and coalesce(pg.type,'') = 'pack')
    or exists (select 1 from public.creditos_movimientos cm
                where cm.user_id = p_user_id and cm.source = 'pack')
  ) then
    return jsonb_build_object('ok', true, 'otorgado', false, 'motivo', 'ya_compro_pack');
  end if;

  -- Tope por grupo, contado sobre lo ya otorgado.
  v_tope := public.bono_cfg('bono_tope_' || p_grupo, 0);
  select count(*) into v_dados from public.bono_otorgado where grupo = p_grupo;
  if v_dados >= v_tope then
    return jsonb_build_object('ok', true, 'otorgado', false, 'motivo', 'tope_alcanzado',
                              'tope', v_tope, 'dados', v_dados);
  end if;

  v_monto := public.bono_cfg('bono_monto', 16);
  v_dias  := public.bono_cfg('bono_vencimiento_dias', 60);
  if v_monto <= 0 then
    return jsonb_build_object('ok', false, 'error', 'monto_invalido');
  end if;
  v_vence := current_date + (v_dias || ' days')::interval;

  -- El candado va ANTES de acreditar: si dos procesos entran juntos, el
  -- segundo encuentra la fila y se va sin regalar dos veces.
  insert into public.bono_otorgado (usuario_id, grupo, monto)
  values (p_user_id, p_grupo, v_monto)
  on conflict (usuario_id) do nothing;
  if not found then
    return jsonb_build_object('ok', true, 'otorgado', false, 'motivo', 'carrera');
  end if;

  perform public.grant_user_credits(
    p_user_id    => p_user_id,
    p_amount     => v_monto,
    p_source     => 'bono_bienvenida',
    p_expires_at => v_vence::text,
    p_description=> 'Bono de bienvenida'
  );

  -- El lote recién creado: es el rastro que después permite saber si ESTOS
  -- créditos se usaron en una clase (reservas.creditos_lotes los referencia).
  select id into v_lote_id
    from public.creditos_movimientos
   where user_id = p_user_id and source = 'bono_bienvenida'
   order by id desc limit 1;

  update public.bono_otorgado set lote_id = v_lote_id where usuario_id = p_user_id;

  -- Canal 1 y 2: campanita + push (el trigger trg_notif_push_nueva la espeja).
  insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
  values (
    p_user_id,
    '🧡 Te regalamos ' || v_monto || ' créditos',
    'Ya están en tu cuenta y alcanzan para una clase. Usalos antes del ' ||
      to_char(v_vence, 'DD/MM') || '.',
    'bono_bienvenida',
    false
  );

  -- Canal 3: mail. Fire-and-forget; si falla, el bono ya está acreditado.
  begin
    select decrypted_secret into v_secret
      from vault.decrypted_secrets where name = 'notif_trigger_secret';
    if coalesce(v_secret, '') <> '' then
      perform net.http_post(
        url     := v_url,
        headers := jsonb_build_object(
          'Content-Type',   'application/json',
          'Authorization',  'Bearer ' || v_anon,
          'apikey',         v_anon,
          'x-notif-secret', v_secret),
        body    := jsonb_build_object('user_id', p_user_id, 'kind', 'otorgado')
      );
    end if;
  exception when others then
    null; -- el mail nunca puede voltear la acreditación
  end;

  return jsonb_build_object('ok', true, 'otorgado', true, 'grupo', p_grupo,
                            'monto', v_monto, 'lote_id', v_lote_id, 'vence', v_vence);
end;
$$;

revoke execute on function public.acreditar_bono(uuid, text) from public, anon, authenticated;
grant execute on function public.acreditar_bono(uuid, text) to service_role;


-- ── 5. Las nuevas se acreditan solas ────────────────────────────────────────
-- Por trigger y no desde el Dart: es el único punto por el que pasan TODOS
-- los caminos de alta (mail, Google, Apple, web) y no cuesta una llamada por
-- login. Con el bono apagado, `acreditar_bono` corta en la primera línea.
create or replace function public.bono_alta_usuaria()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.bono_esta_activo() then
    perform public.acreditar_bono(new.id, 'nuevas');
  end if;
  return new;
exception when others then
  return new;  -- jamás romper el alta de una cuenta por el bono
end;
$$;

drop trigger if exists trg_bono_alta_usuaria on public.usuarios;
create trigger trg_bono_alta_usuaria
  after insert on public.usuarios
  for each row execute function public.bono_alta_usuaria();


-- ── 6. Lo que ve la usuaria (para el cartel de la app) ──────────────────────
create or replace function public.mi_bono()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(
    (select jsonb_build_object(
       'tiene',     true,
       'monto',     cm.amount_total,
       'restante',  cm.amount_remaining,
       'vence_el',  cm.expires_at,
       'vencido',   cm.expires_at < current_date)
       from public.creditos_movimientos cm
      where cm.user_id = auth.uid() and cm.source = 'bono_bienvenida'
      order by cm.id desc limit 1),
    jsonb_build_object('tiene', false));
$$;

grant execute on function public.mi_bono() to authenticated;


-- ── 7. Admin: prender, apagar, otorgar ──────────────────────────────────────
create or replace function public.admin_bono_prender(
  p_monto int default null,
  p_tope_registradas int default null,
  p_tope_nuevas int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  if p_monto is not null and p_monto > 0 then
    insert into public.configuracion_global (clave, valor, updated_at)
    values ('bono_monto', p_monto::text, now())
    on conflict (clave) do update set valor = excluded.valor, updated_at = now();
  end if;
  if p_tope_registradas is not null and p_tope_registradas >= 0 then
    insert into public.configuracion_global (clave, valor, updated_at)
    values ('bono_tope_registradas', p_tope_registradas::text, now())
    on conflict (clave) do update set valor = excluded.valor, updated_at = now();
  end if;
  if p_tope_nuevas is not null and p_tope_nuevas >= 0 then
    insert into public.configuracion_global (clave, valor, updated_at)
    values ('bono_tope_nuevas', p_tope_nuevas::text, now())
    on conflict (clave) do update set valor = excluded.valor, updated_at = now();
  end if;

  -- La línea que separa los dos grupos. Sólo se escribe la PRIMERA vez que se
  -- prende: si se apaga y se vuelve a prender, las que entraron en el medio
  -- siguen contando como 'nuevas'.
  insert into public.configuracion_global (clave, valor, updated_at)
  values ('bono_encendido_at', now()::text, now())
  on conflict (clave) do nothing;

  insert into public.configuracion_global (clave, valor, updated_at)
  values ('bono_activo', 'true', now())
  on conflict (clave) do update set valor = 'true', updated_at = now();

  return jsonb_build_object('ok', true, 'activo', true);
end;
$$;

grant execute on function public.admin_bono_prender(int, int, int) to authenticated;

create or replace function public.admin_bono_apagar()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  insert into public.configuracion_global (clave, valor, updated_at)
  values ('bono_activo', 'false', now())
  on conflict (clave) do update set valor = 'false', updated_at = now();
  return jsonb_build_object('ok', true, 'activo', false);
end;
$$;

grant execute on function public.admin_bono_apagar() to authenticated;

-- Otorgar a las YA REGISTRADAS. Acción deliberada y separada de prender.
-- Orden: las más activas recientemente primero (último ingreso; a igualdad,
-- las que dieron alguna señal de vida y las más nuevas). Respeta el tope.
create or replace function public.admin_bono_otorgar_registradas(p_limite int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_row       record;
  v_otorgados int := 0;
  v_intentos  int := 0;
  v_corte     timestamptz;
  v_cupo      int;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if not public.bono_esta_activo() then
    return jsonb_build_object('ok', false, 'error', 'bono_apagado');
  end if;

  v_corte := coalesce(
    (select nullif(trim(valor),'')::timestamptz from public.configuracion_global
      where clave = 'bono_encendido_at'), now());

  v_cupo := public.bono_cfg('bono_tope_registradas', 0)
            - (select count(*) from public.bono_otorgado where grupo = 'registradas');
  if p_limite is not null and p_limite >= 0 then
    v_cupo := least(v_cupo, p_limite);
  end if;
  if v_cupo <= 0 then
    return jsonb_build_object('ok', true, 'otorgados', 0, 'motivo', 'sin_cupo');
  end if;

  for v_row in
    select u.id
      from public.usuarios u
      join auth.users au on au.id = u.id
      left join public.bono_otorgado b on b.usuario_id = u.id
     where b.usuario_id is null
       and coalesce(u.rol, 'usuario') = 'usuario'
       and au.created_at <= v_corte
       and not exists (select 1 from public.pagos pg
                        where pg.user_id = u.id and pg.status = 'approved'
                          and coalesce(pg.type,'') = 'pack')
       and not exists (select 1 from public.creditos_movimientos cm
                        where cm.user_id = u.id and cm.source = 'pack')
     order by au.last_sign_in_at desc nulls last, au.created_at desc
     limit v_cupo
  loop
    v_intentos := v_intentos + 1;
    if (public.acreditar_bono(v_row.id, 'registradas')->>'otorgado') = 'true' then
      v_otorgados := v_otorgados + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'otorgados', v_otorgados, 'evaluadas', v_intentos);
end;
$$;

grant execute on function public.admin_bono_otorgar_registradas(int) to authenticated;


-- ── 8. Medición ─────────────────────────────────────────────────────────────
-- Por grupo: cuántas lo recibieron, cuántas lo USARON en una clase y cuántas
-- COMPRARON un pack después.
--
-- El uso se mide por el rastro real: `reservas.creditos_lotes` guarda de qué
-- lote salió cada crédito, así que se sabe qué clase se pagó con el bono. Las
-- reservas canceladas no cuentan: devuelven los créditos al mismo lote.
--
-- Ojo con "créditos perdidos": al vencer un lote, refresh_user_credit_balance
-- pone `amount_remaining` en 0, así que ese campo NO distingue usado de
-- vencido. Por eso lo consumido se suma desde las reservas, no desde el lote.
create or replace function public.admin_bono_metricas()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_out jsonb;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  with usos as (
    select b.usuario_id,
           b.grupo,
           sum((e->>'taken')::int)             as creditos_usados,
           min(r.created_at)                   as primer_uso
      from public.bono_otorgado b
      join public.reservas r
        on r.usuario_id = b.usuario_id
       and r.creditos_lotes is not null
       and r.estado in ('pre_confirmada','confirmada','presente','completada')
      cross join lateral jsonb_array_elements(r.creditos_lotes) e
     where (e->>'id')::bigint = b.lote_id
     group by b.usuario_id, b.grupo
  ),
  compras as (
    select distinct b.usuario_id, b.grupo
      from public.bono_otorgado b
      join public.pagos pg
        on pg.user_id = b.usuario_id
       and pg.status = 'approved'
       and coalesce(pg.type,'') = 'pack'
       and pg.created_at > b.otorgado_at
  ),
  base as (
    select b.grupo,
           count(*)                                     as otorgadas,
           sum(b.monto)                                 as creditos_otorgados,
           count(*) filter (where cm.expires_at < current_date) as lotes_vencidos
      from public.bono_otorgado b
      left join public.creditos_movimientos cm on cm.id = b.lote_id
     group by b.grupo
  )
  select jsonb_object_agg(g.grupo, jsonb_build_object(
           'otorgadas',            coalesce(b.otorgadas, 0),
           'creditos_otorgados',   coalesce(b.creditos_otorgados, 0),
           'usaron_en_clase',      (select count(*) from usos u where u.grupo = g.grupo and u.creditos_usados > 0),
           'creditos_usados',      (select coalesce(sum(u.creditos_usados),0) from usos u where u.grupo = g.grupo),
           'compraron_pack',       (select count(*) from compras c where c.grupo = g.grupo),
           'lotes_vencidos',       coalesce(b.lotes_vencidos, 0),
           'dias_al_primer_uso',   (select round(avg(extract(epoch from (u.primer_uso - bo.otorgado_at)) / 86400)::numeric, 1)
                                      from usos u join public.bono_otorgado bo on bo.usuario_id = u.usuario_id
                                     where u.grupo = g.grupo)
         ))
    into v_out
    from (select unnest(array['registradas','nuevas']) as grupo) g
    left join base b on b.grupo = g.grupo;

  return jsonb_build_object(
    'ok', true,
    'activo', public.bono_esta_activo(),
    'monto', public.bono_cfg('bono_monto', 16),
    'tope_registradas', public.bono_cfg('bono_tope_registradas', 0),
    'tope_nuevas', public.bono_cfg('bono_tope_nuevas', 0),
    'vencimiento_dias', public.bono_cfg('bono_vencimiento_dias', 60),
    'grupos', v_out);
end;
$$;

grant execute on function public.admin_bono_metricas() to authenticated;

-- Config para la pantalla de admin (lo mismo, sin las métricas pesadas).
create or replace function public.admin_bono_config()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return jsonb_build_object(
    'activo', public.bono_esta_activo(),
    'monto', public.bono_cfg('bono_monto', 16),
    'tope_registradas', public.bono_cfg('bono_tope_registradas', 0),
    'tope_nuevas', public.bono_cfg('bono_tope_nuevas', 0),
    'vencimiento_dias', public.bono_cfg('bono_vencimiento_dias', 60),
    'dados_registradas', (select count(*) from public.bono_otorgado where grupo = 'registradas'),
    'dados_nuevas', (select count(*) from public.bono_otorgado where grupo = 'nuevas'),
    'candidatas_registradas', (
      select count(*) from public.usuarios u
       left join public.bono_otorgado b on b.usuario_id = u.id
       where b.usuario_id is null and coalesce(u.rol,'usuario') = 'usuario'
         and not exists (select 1 from public.pagos pg where pg.user_id = u.id
                          and pg.status = 'approved' and coalesce(pg.type,'') = 'pack')
         and not exists (select 1 from public.creditos_movimientos cm
                          where cm.user_id = u.id and cm.source = 'pack')));
end;
$$;

grant execute on function public.admin_bono_config() to authenticated;


-- ── 9. Recordatorios ────────────────────────────────────────────────────────
-- Dos, y nada más: a los 7 días de otorgado sin usarlo, y 5 días antes de que
-- venza. Mismos canales (campanita + push + mail).
--
-- ⚠️ NO se crea ningún cron acá: esta función existe pero no la llama nadie.
-- Cuando se prenda el bono, agendarla con:
--   select cron.schedule('bono-recordatorios', '0 14 * * *',
--          $cron$ select public.bono_recordatorios(); $cron$);
create or replace function public.bono_recordatorios()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_row    record;
  v_n      int := 0;
  v_secret text;
  v_url  text := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/bono-email';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk';
begin
  if not public.bono_esta_activo() then
    return jsonb_build_object('ok', true, 'enviados', 0, 'motivo', 'apagado');
  end if;

  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'notif_trigger_secret';

  for v_row in
    select b.usuario_id, cm.amount_remaining, cm.expires_at,
           case when cm.expires_at - current_date <= 5 then 'vence' else 'siete_dias' end as motivo
      from public.bono_otorgado b
      join public.creditos_movimientos cm on cm.id = b.lote_id
     where cm.amount_remaining > 0
       and cm.expires_at >= current_date
       and (
         -- 7 días de otorgado y todavía entero
         (b.otorgado_at::date = current_date - 7 and cm.amount_remaining = cm.amount_total)
         -- o faltan 5 días para que venza
         or (cm.expires_at - current_date = 5)
       )
  loop
    insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
    values (
      v_row.usuario_id,
      case when v_row.motivo = 'vence'
           then '⏳ Tus créditos vencen pronto'
           else '🧡 Tenés ' || v_row.amount_remaining || ' créditos esperándote' end,
      'Alcanzan para una clase. Se vencen el ' || to_char(v_row.expires_at, 'DD/MM') || '.',
      'bono_bienvenida',
      false);

    begin
      if coalesce(v_secret,'') <> '' then
        perform net.http_post(
          url     := v_url,
          headers := jsonb_build_object(
            'Content-Type','application/json',
            'Authorization','Bearer ' || v_anon,
            'apikey', v_anon,
            'x-notif-secret', v_secret),
          body    := jsonb_build_object('user_id', v_row.usuario_id, 'kind', 'recordatorio'));
      end if;
    exception when others then null;
    end;

    v_n := v_n + 1;
  end loop;

  return jsonb_build_object('ok', true, 'enviados', v_n);
end;
$$;

revoke execute on function public.bono_recordatorios() from public, anon, authenticated;
grant execute on function public.bono_recordatorios() to service_role;
