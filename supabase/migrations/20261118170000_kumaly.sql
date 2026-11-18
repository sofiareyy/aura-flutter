-- =============================================================================
-- Integración con Kumaly (sistema de turnos de los estudios) — 18/11/2026
-- =============================================================================
--
-- Primer estudio: Pilates House Studio (estudio_id 70). La integración se
-- prende POR ESTUDIO en `kumaly_estudios` y nace APAGADA: hasta que no estén
-- las salas cargadas igual en los dos sistemas, la URL y la clave de Kumaly,
-- no sale ni entra nada.
--
-- AURA → KUMALY (edge function kumaly-enviar, cron cada minuto)
--   Un trigger en `reservas` anota en `kumaly_envios` cada reserva confirmada
--   y cada cancelación de un estudio integrado. La función manda lo pendiente:
--     · 200            → confirmado.
--     · 409 sin_lugar  → cancelamos la reserva, devolvemos créditos, avisamos.
--     · otra cosa      → se reintenta cada 10 min.
--   Límite: lo que pase primero entre el inicio de la clase y 24 h. Si una
--   reserva llega al límite sin confirmar, se cancela, se devuelve y se avisa.
--   Una cancelación se manda sólo si Kumaly había confirmado la reserva.
--
-- KUMALY → AURA (edge function kumaly-webhook → kumaly_recibir)
--   · Ocupación: {estudio_id, inicio, sala, ocupados, cancelada}
--       lugares_disponibles = total − ocupados − nuestras reservas que Kumaly
--       todavía no confirmó. cancelada:true sólo para clases futuras, por el
--       mismo núcleo que usa el panel (_cancelar_clase_y_devolver).
--   · Asistencia: {evento:'asistencia', reserva_id, presente, marcado_at?}
--       Gana el último: se compara marcado_at (o la hora de llegada si no
--       viene) contra el último marcado del estado, sea del panel o de Kumaly.
--
-- Los webhooks corren con service_role, así que los triggers de `reservas`
-- que sólo miran a `authenticated`/`anon` NO corren. Los controles están
-- repetidos acá a mano, en las tres entradas.
--
-- Hora: `clases.fecha` es hora argentina sin huso (así lo compara
-- reservar_clase). Hacia Kumaly sale con el huso escrito; lo que entra se
-- convierte a hora argentina antes de buscar la clase.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Tablas (RLS prendida y sin políticas: sólo el servidor las toca)
-- ---------------------------------------------------------------------------

create table if not exists public.kumaly_estudios (
  estudio_id bigint primary key references public.estudios(id) on delete cascade,
  activo     boolean not null default false,
  nota       text,
  created_at timestamptz not null default now()
);

create table if not exists public.kumaly_envios (
  id              bigserial primary key,
  reserva_id      bigint not null references public.reservas(id) on delete cascade,
  evento          text not null check (evento in ('reserva', 'cancelacion')),
  payload         jsonb not null,
  estado          text not null default 'pendiente'
                  check (estado in ('pendiente', 'confirmado', 'rechazado', 'vencido', 'descartado')),
  intentos        int not null default 0,
  proximo_intento timestamptz not null default now(),
  limite          timestamptz not null,
  ultimo_status   int,
  ultimo_error    text,
  created_at      timestamptz not null default now(),
  resuelto_at     timestamptz,
  unique (reserva_id, evento)
);
create index if not exists kumaly_envios_pendientes_idx
  on public.kumaly_envios (proximo_intento) where estado = 'pendiente';

create table if not exists public.kumaly_eventos (
  id          bigserial primary key,
  recibido_at timestamptz not null default now(),
  payload     jsonb,
  http_status int,
  resultado   jsonb
);

alter table public.kumaly_estudios enable row level security;
alter table public.kumaly_envios   enable row level security;
alter table public.kumaly_eventos  enable row level security;
revoke all on public.kumaly_estudios, public.kumaly_envios, public.kumaly_eventos
  from anon, authenticated;
revoke all on sequence public.kumaly_envios_id_seq, public.kumaly_eventos_id_seq
  from anon, authenticated;

-- PHS queda anotado, APAGADO.
insert into public.kumaly_estudios (estudio_id, activo, nota)
values (70, false, 'Pilates House Studio. Prender cuando estén las salas, la URL y la clave de Kumaly.')
on conflict (estudio_id) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Ayudantes
-- ---------------------------------------------------------------------------

-- Hora argentina sin huso → ISO 8601 con el huso escrito ("…T18:00:00-03:00").
create or replace function public._kumaly_iso(p_fecha timestamp)
returns text
language sql
stable
set timezone to 'America/Argentina/Buenos_Aires'
as $$
  select to_char(p_fecha at time zone 'America/Argentina/Buenos_Aires',
                 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM')
$$;

-- Salas: sin distinguir mayúsculas ni espacios de más.
create or replace function public._kumaly_sala(p_sala text)
returns text
language sql
immutable
as $$
  select nullif(lower(regexp_replace(btrim(coalesce(p_sala, '')), '\s+', ' ', 'g')), '')
$$;

-- ISO 8601 que TIENE que traer el huso. null si no lo trae o no se entiende.
create or replace function public._kumaly_parse_iso(p_txt text)
returns timestamptz
language plpgsql
stable
as $$
begin
  if p_txt is null or p_txt !~ '(Z|[+-]\d{2}(:?\d{2})?)$' then
    return null;
  end if;
  return p_txt::timestamptz;
exception when others then
  return null;
end;
$$;

-- ¿El estudio tiene la integración prendida?
create or replace function public._kumaly_activo(p_estudio_id bigint)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce((select activo from public.kumaly_estudios where estudio_id = p_estudio_id), false)
$$;

-- ---------------------------------------------------------------------------
-- 3. estudio_cancelar_clase partida en dos (aprobado 18/11)
--    · _cancelar_clase_y_devolver: cancela, devuelve, avisa. Sin permisos:
--      sólo la llaman el wrapper del panel y kumaly_recibir.
--    · estudio_cancelar_clase: lo mismo que antes, con su control de permisos.
--    El cuerpo del núcleo es el de producción al 18/11 sin cambios.
-- ---------------------------------------------------------------------------

create or replace function public._cancelar_clase_y_devolver(p_clase_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_clase public.clases%rowtype;
  v_r public.reservas%rowtype;
  v_ahora timestamptz := now();
  v_creditos bigint := 0;
  v_afectadas int := 0;
  v_secret text;
  v_estudio text;
  v_destinatarios jsonb := '[]'::jsonb;
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk';
begin
  select * into v_clase from public.clases where id = p_clase_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'clase_inexistente');
  end if;
  if coalesce(v_clase.cancelada, false) then
    return jsonb_build_object('ok', false, 'error', 'ya_cancelada');
  end if;

  select e.nombre into v_estudio from public.estudios e where e.id = v_clase.estudio_id;

  for v_r in
    select * from public.reservas
     where clase_id = p_clase_id
       and estado in ('confirmada', 'presente', 'pre_confirmada')
     for update
  loop
    -- 2026-08-26: `usuario_id` puede ser NULL (reserva de una cuenta borrada,
    -- conservada como evidencia de cobro). No hay a quién devolverle los
    -- créditos: se saltea la devolución, pero la reserva SÍ se cancela.
    if v_r.usuario_id is not null and coalesce(v_r.creditos_usados, 0) > 0 then
      perform public.grant_user_credits(
        v_r.usuario_id,
        v_r.creditos_usados::int,
        'devolucion_clase_cancelada',
        (v_ahora + interval '90 days')::text,
        'Devolución por clase cancelada: ' || coalesce(v_clase.nombre, 'clase')
      );
      v_creditos := v_creditos + v_r.creditos_usados;
    end if;

    update public.reservas set estado = 'cancelada_por_estudio' where id = v_r.id;
    v_afectadas := v_afectadas + 1;

    if v_r.usuario_id is not null then
      insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
      values (v_r.usuario_id, '❌ Clase cancelada',
              'Se canceló "' || coalesce(v_clase.nombre, 'la clase') ||
              '". Te devolvimos tus créditos.', 'clase_cancelada', false);

      v_destinatarios := v_destinatarios || jsonb_build_object(
        'reserva_id', v_r.id,
        'usuario_id', v_r.usuario_id,
        'creditos', coalesce(v_r.creditos_usados, 0));
    end if;
  end loop;

  update public.clases set cancelada = true where id = p_clase_id;

  if v_afectadas > 0 then
    begin
      v_secret := (select decrypted_secret from vault.decrypted_secrets
                    where name = 'notif_trigger_secret');
      perform net.http_post(
        url := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/cancelacion-email',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_anon,
          'apikey', v_anon,
          'x-notif-secret', coalesce(v_secret, '')),
        body := jsonb_build_object(
          'clase_id', p_clase_id,
          'clase', jsonb_build_object(
            'nombre', v_clase.nombre,
            'fecha', v_clase.fecha,
            'tipo', coalesce(v_clase.tipo, 'clase'),
            'estudio_nombre', v_estudio),
          'destinatarios', v_destinatarios)
      );
    exception when others then
      null; -- el mail es lo último y lo menos importante: nunca corta esto
    end;
  end if;

  return jsonb_build_object('ok', true, 'reservas_afectadas', v_afectadas,
                            'creditos_devueltos', v_creditos);
end;
$function$;

create or replace function public.estudio_cancelar_clase(p_clase_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_clase public.clases%rowtype;
begin
  select * into v_clase from public.clases where id = p_clase_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'clase_inexistente');
  end if;
  if coalesce(v_clase.cancelada, false) then
    return jsonb_build_object('ok', false, 'error', 'ya_cancelada');
  end if;

  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'sin_sesion');
  end if;

  if not exists (
    select 1 from public.estudio_admins ea
     where ea.estudio_id = v_clase.estudio_id
       and ea.usuario_id = v_uid
       and ea.rol in ('estudio', 'admin_estudio')
  ) then
    return jsonb_build_object('ok', false, 'error', 'sin_permisos');
  end if;

  return public._cancelar_clase_y_devolver(p_clase_id);
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Cancelar UNA reserva porque Kumaly no la tomó (409 sin_lugar, o no
--    contestó hasta el límite). Misma devolución, aviso y mail que
--    admin_cancelar_reserva, sin su chequeo de admin.
-- ---------------------------------------------------------------------------

create or replace function public._kumaly_cancelar_reserva(p_reserva_id bigint, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_r         public.reservas%rowtype;
  v_clase     public.clases%rowtype;
  v_estudio   text;
  v_creditos  int := 0;
  v_secret    text;
  v_mensaje   text;
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk';
begin
  select * into v_r from public.reservas where id = p_reserva_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_encontrada');
  end if;
  -- Sólo una confirmada. Si la alumna ya canceló o ya está marcada, no se toca.
  if v_r.estado <> 'confirmada' then
    return jsonb_build_object('ok', false, 'error', 'estado_invalido', 'estado', v_r.estado);
  end if;

  select * into v_clase from public.clases where id = v_r.clase_id for update;
  select e.nombre into v_estudio from public.estudios e where e.id = v_clase.estudio_id;
  v_creditos := coalesce(v_r.creditos_usados, 0);

  -- Que el trigger de envíos no le mande a Kumaly una cancelación de algo
  -- que Kumaly nunca tomó. La marca vale sólo para este UPDATE.
  perform set_config('aura.origen', 'kumaly', true);
  update public.reservas set estado = 'cancelada_por_estudio' where id = v_r.id;
  perform set_config('aura.origen', '', true);

  -- sin_lugar: Kumaly dice que está llena → 0 lugares (si devolviéramos uno,
  -- la próxima alumna rebotaría igual). vencido: se devuelve el lugar.
  if p_motivo = 'sin_lugar' then
    update public.clases set lugares_disponibles = 0 where id = v_clase.id;
  else
    update public.clases
       set lugares_disponibles = least(
             coalesce(lugares_disponibles, 0) + 1,
             coalesce(lugares_total, coalesce(lugares_disponibles, 0) + 1))
     where id = v_clase.id;
  end if;

  if v_r.usuario_id is not null then
    if v_creditos > 0 then
      perform public.grant_user_credits(
        v_r.usuario_id, v_creditos, 'devolucion_clase_cancelada',
        (now() + interval '90 days')::text,
        'Devolución por reserva cancelada: ' || coalesce(v_clase.nombre, 'clase'));
    end if;

    v_mensaje := case when p_motivo = 'sin_lugar'
      then 'El estudio no tenía más lugar en "' || coalesce(v_clase.nombre, 'la clase') || '" y cancelamos tu reserva.'
      else 'No pudimos confirmar tu lugar en "' || coalesce(v_clase.nombre, 'la clase') || '" con el estudio y cancelamos tu reserva.'
    end || case when v_creditos > 0 then ' Te devolvimos tus créditos.' else '' end;

    insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
    values (v_r.usuario_id, '❌ Reserva cancelada', v_mensaje, 'clase_cancelada', false);

    begin
      v_secret := (select decrypted_secret from vault.decrypted_secrets
                    where name = 'notif_trigger_secret');
      perform net.http_post(
        url := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/cancelacion-email',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_anon,
          'apikey', v_anon,
          'x-notif-secret', coalesce(v_secret, '')),
        body := jsonb_build_object(
          'clase_id', v_clase.id,
          'alcance', 'reserva',
          'clase', jsonb_build_object(
            'nombre', v_clase.nombre,
            'fecha', v_clase.fecha,
            'tipo', coalesce(v_clase.tipo, 'clase'),
            'estudio_nombre', v_estudio),
          'destinatarios', jsonb_build_array(jsonb_build_object(
            'reserva_id', v_r.id,
            'usuario_id', v_r.usuario_id,
            'creditos', v_creditos))));
    exception when others then
      null;
    end;
  end if;

  return jsonb_build_object('ok', true, 'creditos_devueltos', v_creditos, 'motivo', p_motivo);
end;
$function$;

-- ---------------------------------------------------------------------------
-- 5. Trigger: anotar lo que hay que mandarle a Kumaly
-- ---------------------------------------------------------------------------

create or replace function public.kumaly_encolar()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_clase   public.clases%rowtype;
  v_nombre  text;
  v_mail    text;
  v_base    jsonb;
  v_res     public.kumaly_envios%rowtype;
  v_motivo  text;
  v_limite  timestamptz;
begin
  -- Lo que vino de Kumaly (o lo que cancelamos porque Kumaly no lo tomó) no
  -- vuelve a Kumaly.
  if coalesce(current_setting('aura.origen', true), '') = 'kumaly' then
    return new;
  end if;

  select * into v_clase from public.clases where id = new.clase_id;
  if not found or not public._kumaly_activo(v_clase.estudio_id) then
    return new;
  end if;

  select coalesce(nullif(btrim(u.nombre), ''), ''), coalesce(au.email, u.email)
    into v_nombre, v_mail
    from (select 1) x
    left join public.usuarios u on u.id = new.usuario_id
    left join auth.users au on au.id = new.usuario_id;

  v_base := jsonb_build_object(
    'reserva_id',   new.id,
    'estudio',      v_clase.estudio_id,
    'clase',        v_clase.nombre,
    'sala',         v_clase.sala,
    'inicio',       public._kumaly_iso(v_clase.fecha),
    'duracion_min', v_clase.duracion_min,
    'alumna',       v_nombre,
    'mail',         v_mail);

  -- RESERVA: nace confirmada, o sale de la lista de espera.
  if new.estado = 'confirmada'
     and (tg_op = 'INSERT' or old.estado = 'pre_confirmada') then
    v_limite := least(v_clase.fecha at time zone 'America/Argentina/Buenos_Aires',
                      now() + interval '24 hours');
    insert into public.kumaly_envios (reserva_id, evento, payload, limite)
    values (new.id, 'reserva',
            v_base || jsonb_build_object('evento', 'reserva', 'motivo', null),
            v_limite)
    on conflict (reserva_id, evento) do nothing;
    return new;
  end if;

  -- CANCELACIÓN de algo que estaba tomado.
  if tg_op = 'UPDATE'
     and old.estado in ('confirmada', 'presente')
     and new.estado in ('cancelada', 'cancelada_por_estudio') then

    select * into v_res from public.kumaly_envios
     where reserva_id = new.id and evento = 'reserva' for update;
    if not found then
      return new;  -- reserva de antes de prender la integración
    end if;

    -- Nunca salió: se descarta la reserva y no hace falta cancelar nada.
    if v_res.estado = 'pendiente' and v_res.intentos = 0 then
      update public.kumaly_envios
         set estado = 'descartado', resuelto_at = now(),
             ultimo_error = 'la reserva se canceló antes de mandarse'
       where id = v_res.id;
      return new;
    end if;
    -- Kumaly no la tomó: no hay nada que cancelarle.
    if v_res.estado in ('rechazado', 'vencido', 'descartado') then
      return new;
    end if;

    v_motivo := case when new.estado = 'cancelada' then 'alumna' else 'estudio' end;
    insert into public.kumaly_envios (reserva_id, evento, payload, limite)
    values (new.id, 'cancelacion',
            v_base || jsonb_build_object('evento', 'cancelacion', 'motivo', v_motivo),
            now() + interval '24 hours')
    on conflict (reserva_id, evento) do nothing;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_kumaly_encolar on public.reservas;
create trigger trg_kumaly_encolar
  after insert or update of estado on public.reservas
  for each row execute function public.kumaly_encolar();

-- ---------------------------------------------------------------------------
-- 6. Envío: tomar lo pendiente y registrar la respuesta
-- ---------------------------------------------------------------------------

-- Devuelve lo que hay que mandar ahora y lo deja reservado 10 min (el
-- próximo reintento). Antes, cierra lo que llegó al límite.
create or replace function public.kumaly_tomar_envios(p_lote int default 20)
returns table (id bigint, evento text, payload jsonb)
language plpgsql
security definer
set search_path to 'public'
as $function$
#variable_conflict use_column
declare
  v_e public.kumaly_envios%rowtype;
begin
  -- Reservas que llegaron al límite sin confirmar: se caen.
  for v_e in
    select * from public.kumaly_envios e
     where e.estado = 'pendiente' and e.evento = 'reserva' and e.limite <= now()
     for update skip locked
  loop
    perform public._kumaly_cancelar_reserva(v_e.reserva_id, 'vencido');
    update public.kumaly_envios
       set estado = 'vencido', resuelto_at = now()
     where kumaly_envios.id = v_e.id;
  end loop;

  -- Cancelaciones cuyo aviso de reserva nunca llegó a Kumaly: nada que cancelar.
  update public.kumaly_envios c
     set estado = 'descartado', resuelto_at = now(),
         ultimo_error = 'Kumaly nunca tomó la reserva'
    from public.kumaly_envios r
   where c.estado = 'pendiente' and c.evento = 'cancelacion'
     and r.reserva_id = c.reserva_id and r.evento = 'reserva'
     and r.estado in ('rechazado', 'vencido', 'descartado');

  -- Cancelaciones vencidas (24 h sin respuesta).
  update public.kumaly_envios
     set estado = 'vencido', resuelto_at = now()
   where estado = 'pendiente' and evento = 'cancelacion' and limite <= now();

  return query
  with elegidos as (
    select e.id
      from public.kumaly_envios e
     where e.estado = 'pendiente'
       and e.proximo_intento <= now()
       -- una cancelación sale sólo cuando Kumaly ya confirmó la reserva
       and (e.evento = 'reserva' or exists (
             select 1 from public.kumaly_envios r
              where r.reserva_id = e.reserva_id and r.evento = 'reserva'
                and r.estado = 'confirmado'))
     order by e.id
     limit p_lote
     for update skip locked
  )
  update public.kumaly_envios e
     set intentos = e.intentos + 1,
         proximo_intento = now() + interval '10 minutes'
    from elegidos
   where e.id = elegidos.id
  returning e.id, e.evento, e.payload;
end;
$function$;

create or replace function public.kumaly_registrar_respuesta(
  p_id bigint, p_status int, p_cuerpo text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_e public.kumaly_envios%rowtype;
begin
  select * into v_e from public.kumaly_envios where id = p_id for update;
  if not found or v_e.estado <> 'pendiente' then
    return jsonb_build_object('ok', false, 'error', 'no_pendiente');
  end if;

  if p_status between 200 and 299 then
    update public.kumaly_envios
       set estado = 'confirmado', ultimo_status = p_status, ultimo_error = null,
           resuelto_at = now()
     where id = p_id;
    return jsonb_build_object('ok', true, 'estado', 'confirmado');
  end if;

  -- 409 sin_lugar a una reserva: se cae acá mismo, sin esperar al límite.
  -- Un 409 que no dice sin_lugar se trata como error y se reintenta.
  if p_status = 409 and v_e.evento = 'reserva'
     and coalesce(p_cuerpo, '') ilike '%sin_lugar%' then
    perform public._kumaly_cancelar_reserva(v_e.reserva_id, 'sin_lugar');
    update public.kumaly_envios
       set estado = 'rechazado', ultimo_status = p_status,
           ultimo_error = left(p_cuerpo, 500), resuelto_at = now()
     where id = p_id;
    return jsonb_build_object('ok', true, 'estado', 'rechazado');
  end if;

  update public.kumaly_envios
     set ultimo_status = p_status, ultimo_error = left(coalesce(p_cuerpo, ''), 500)
   where id = p_id;
  return jsonb_build_object('ok', true, 'estado', 'pendiente');
end;
$function$;

-- ---------------------------------------------------------------------------
-- 7. Entrada: lo que manda Kumaly
--    Devuelve {http, ...}: la edge function contesta con ese código.
-- ---------------------------------------------------------------------------

create or replace function public._kumaly_ocupacion(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_estudio    bigint;
  v_inicio     timestamptz;
  v_fecha      timestamp;
  v_sala       text;
  v_ids        bigint[];
  v_clase      public.clases%rowtype;
  v_ahora      timestamp := (now() at time zone 'America/Argentina/Buenos_Aires');
  v_ocupados   int;
  v_pendientes int;
  v_libres     int;
  v_cancelacion jsonb;
begin
  if jsonb_typeof(p->'estudio_id') is distinct from 'number' then
    return jsonb_build_object('http', 400, 'error', 'falta_estudio_id');
  end if;
  v_estudio := (p->>'estudio_id')::bigint;
  if not public._kumaly_activo(v_estudio) then
    return jsonb_build_object('http', 403, 'error', 'estudio_no_integrado');
  end if;

  v_inicio := public._kumaly_parse_iso(p->>'inicio');
  if v_inicio is null then
    return jsonb_build_object('http', 400, 'error', 'inicio_invalido',
      'detalle', 'ISO 8601 con el huso escrito, por ejemplo 2026-11-19T18:00:00-03:00');
  end if;
  v_fecha := v_inicio at time zone 'America/Argentina/Buenos_Aires';
  v_sala := public._kumaly_sala(p->>'sala');

  select array_agg(c.id) into v_ids
    from public.clases c
   where c.estudio_id = v_estudio
     and c.fecha = v_fecha
     and public._kumaly_sala(c.sala) is not distinct from v_sala;

  if v_ids is null then
    return jsonb_build_object('http', 404, 'error', 'clase_no_encontrada',
      'fecha', v_fecha, 'sala', p->>'sala');
  end if;
  if array_length(v_ids, 1) > 1 then
    return jsonb_build_object('http', 409, 'error', 'clase_ambigua', 'clases', v_ids);
  end if;

  select * into v_clase from public.clases where id = v_ids[1] for update;

  -- Clase suspendida por el estudio.
  if coalesce((p->>'cancelada')::boolean, false) then
    if coalesce(v_clase.cancelada, false) then
      return jsonb_build_object('http', 200, 'ok', true, 'clase_id', v_clase.id, 'ya_cancelada', true);
    end if;
    if v_clase.fecha <= v_ahora then
      return jsonb_build_object('http', 422, 'error', 'clase_ya_empezo', 'clase_id', v_clase.id);
    end if;
    perform set_config('aura.origen', 'kumaly', true);
    v_cancelacion := public._cancelar_clase_y_devolver(v_clase.id);
    perform set_config('aura.origen', '', true);
    return jsonb_build_object('http', 200, 'clase_id', v_clase.id) || v_cancelacion;
  end if;

  if jsonb_typeof(p->'ocupados') is distinct from 'number'
     or (p->>'ocupados')::numeric <> floor((p->>'ocupados')::numeric)
     or (p->>'ocupados')::numeric < 0 then
    return jsonb_build_object('http', 400, 'error', 'ocupados_invalido');
  end if;
  v_ocupados := (p->>'ocupados')::int;

  if coalesce(v_clase.cancelada, false) then
    return jsonb_build_object('http', 200, 'ok', true, 'clase_id', v_clase.id,
                              'ignorado', 'clase_cancelada');
  end if;

  -- Nuestras reservas que Kumaly todavía no confirmó: no están en su total.
  select count(*) into v_pendientes
    from public.reservas r
    join public.kumaly_envios e
      on e.reserva_id = r.id and e.evento = 'reserva' and e.estado = 'pendiente'
   where r.clase_id = v_clase.id and r.estado = 'confirmada';

  v_libres := greatest(0, coalesce(v_clase.lugares_total, 0)::int - v_ocupados - v_pendientes);
  update public.clases set lugares_disponibles = v_libres where id = v_clase.id;

  return jsonb_build_object('http', 200, 'ok', true, 'clase_id', v_clase.id,
    'lugares_total', v_clase.lugares_total, 'ocupados', v_ocupados,
    'pendientes', v_pendientes, 'lugares_disponibles', v_libres);
end;
$function$;

create or replace function public._kumaly_asistencia(p jsonb, p_recibido timestamptz)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_r       public.reservas%rowtype;
  v_clase   public.clases%rowtype;
  v_estudio public.estudios%rowtype;
  v_ahora   timestamp := (p_recibido at time zone 'America/Argentina/Buenos_Aires');
  v_marcado timestamptz;
  v_ultimo  timestamptz;
  v_nuevo   text;
  v_desde   timestamp;
  v_hasta   timestamp;
begin
  if jsonb_typeof(p->'reserva_id') is distinct from 'number' then
    return jsonb_build_object('http', 400, 'error', 'falta_reserva_id');
  end if;
  if jsonb_typeof(p->'presente') is distinct from 'boolean' then
    return jsonb_build_object('http', 400, 'error', 'falta_presente');
  end if;

  -- La hora en que se marcó, si Kumaly la manda. Si no, la de llegada.
  if p ? 'marcado_at' and jsonb_typeof(p->'marcado_at') <> 'null' then
    v_marcado := public._kumaly_parse_iso(p->>'marcado_at');
    if v_marcado is null then
      return jsonb_build_object('http', 400, 'error', 'marcado_at_invalido',
        'detalle', 'ISO 8601 con el huso escrito');
    end if;
    v_marcado := least(v_marcado, p_recibido);  -- nada en el futuro
  else
    v_marcado := p_recibido;
  end if;

  select * into v_r from public.reservas where id = (p->>'reserva_id')::bigint for update;
  if found then
    select * into v_clase from public.clases where id = v_r.clase_id;
  end if;
  -- Una reserva de un estudio no integrado contesta igual que una que no
  -- existe: con la clave de Kumaly no se averigua nada de otros estudios.
  if v_r.id is null or v_clase.id is null or not public._kumaly_activo(v_clase.estudio_id) then
    return jsonb_build_object('http', 404, 'error', 'reserva_no_encontrada');
  end if;

  if v_r.estado not in ('confirmada', 'presente', 'ausente', 'completada') then
    return jsonb_build_object('http', 409, 'error', 'estado_invalido', 'estado', v_r.estado);
  end if;

  -- Ventana: desde donde la deja el panel (reservas_no_marcar_antes_de_tiempo:
  -- cuando la alumna ya no puede cancelar, con 10 min de tolerancia) hasta
  -- 24 h después de que termina la clase.
  select * into v_estudio from public.estudios where id = v_clase.estudio_id;
  v_desde := v_clase.fecha - make_interval(mins => greatest(coalesce(
               v_clase.cancelacion_cierre_minutos, v_estudio.cancelacion_cierre_minutos, 720), 10));
  v_hasta := v_clase.fecha + make_interval(mins => coalesce(v_clase.duracion_min, 0)::int)
             + interval '24 hours';
  if v_ahora < v_desde then
    return jsonb_build_object('http', 422, 'error', 'todavia_no',
      'desde', public._kumaly_iso(v_desde));
  end if;
  if v_ahora > v_hasta then
    return jsonb_build_object('http', 422, 'error', 'fuera_de_plazo',
      'hasta', public._kumaly_iso(v_hasta));
  end if;

  -- Gana el último: el último marcado (panel o Kumaly) queda en el log.
  -- No cuenta el paso a 'completada' del cron, que no es un marcado.
  select max(l.created_at) into v_ultimo
    from public.reservas_estado_log l
   where l.reserva_id = v_r.id
     and l.accion = 'estado'
     and l.estado_nuevo in ('presente', 'ausente', 'confirmada');
  if v_ultimo is not null and v_marcado < v_ultimo then
    return jsonb_build_object('http', 200, 'ok', true, 'aplicado', false,
      'motivo', 'hay_un_marcado_posterior', 'estado', v_r.estado);
  end if;

  v_nuevo := case when (p->>'presente')::boolean then 'presente' else 'ausente' end;
  if v_r.estado = v_nuevo then
    return jsonb_build_object('http', 200, 'ok', true, 'aplicado', false,
      'motivo', 'sin_cambios', 'estado', v_nuevo);
  end if;

  perform set_config('aura.origen', 'kumaly', true);
  -- checked_in_at igual que el panel: hora del marcado en presente, null en ausente.
  update public.reservas
     set estado = v_nuevo,
         checked_in_at = case when v_nuevo = 'presente' then v_marcado else null end
   where id = v_r.id;
  perform set_config('aura.origen', '', true);

  return jsonb_build_object('http', 200, 'ok', true, 'aplicado', true,
    'estado_anterior', v_r.estado, 'estado', v_nuevo);
end;
$function$;

create or replace function public.kumaly_recibir(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_res jsonb;
  v_recibido timestamptz := now();
begin
  begin
    if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
      v_res := jsonb_build_object('http', 400, 'error', 'cuerpo_invalido');
    elsif p_payload->>'evento' = 'asistencia' then
      v_res := public._kumaly_asistencia(p_payload, v_recibido);
    elsif p_payload ? 'estudio_id' and (p_payload ? 'ocupados' or p_payload ? 'cancelada') then
      v_res := public._kumaly_ocupacion(p_payload);
    else
      v_res := jsonb_build_object('http', 400, 'error', 'evento_desconocido');
    end if;
  exception when others then
    -- Lo que haya hecho a medias se deshace (subtransacción). Queda anotado.
    v_res := jsonb_build_object('http', 500, 'error', 'error_interno',
                                'detalle', sqlstate || ' ' || sqlerrm);
  end;

  insert into public.kumaly_eventos (recibido_at, payload, http_status, resultado)
  values (v_recibido, p_payload, (v_res->>'http')::int, v_res);
  return v_res;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 8. Permisos: nada de esto se llama desde la app
-- ---------------------------------------------------------------------------

revoke execute on function
  public._cancelar_clase_y_devolver(bigint),
  public._kumaly_cancelar_reserva(bigint, text),
  public._kumaly_activo(bigint),
  public.kumaly_tomar_envios(int),
  public.kumaly_registrar_respuesta(bigint, int, text),
  public._kumaly_ocupacion(jsonb),
  public._kumaly_asistencia(jsonb, timestamptz),
  public.kumaly_recibir(jsonb),
  public.kumaly_encolar()
from public, anon, authenticated;

grant execute on function
  public.kumaly_tomar_envios(int),
  public.kumaly_registrar_respuesta(bigint, int, text),
  public.kumaly_recibir(jsonb)
to service_role;

-- ---------------------------------------------------------------------------
-- 9. Cron: cada minuto, y sólo llama a la función si hay algo para hacer.
--    El comando lee la clave del Vault: no hay ninguna clave en este archivo.
-- ---------------------------------------------------------------------------

select cron.schedule('kumaly-enviar', '* * * * *', $cron$
  select net.http_post(
    url     := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/kumaly-enviar',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret
                                       from vault.decrypted_secrets
                                      where name = 'edge_service_key')),
    body    := '{}'::jsonb,
    timeout_milliseconds := 60000)
  where exists (
    select 1 from public.kumaly_envios
     where estado = 'pendiente' and (proximo_intento <= now() or limite <= now()))
$cron$);
