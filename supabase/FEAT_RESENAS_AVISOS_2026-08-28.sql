-- ============================================================================
-- 3 · AVISO AL ESTUDIO cuando llega una reseña nueva
-- 4 · PEDIDO DE RESEÑA a quien ASISTIÓ, 15 min después de la clase
--
-- Campanita + mail hoy; el push se suma solo cuando APNs esté arreglado,
-- porque la misma fila de notificaciones_usuario dispara trg_notif_push_nueva.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 3 · Trigger AFTER INSERT en study_reviews. Sólo INSERT: editar la propia
--     reseña (el upsert de la app) no re-spamea al estudio.
-- ----------------------------------------------------------------------------
create or replace function public.notif_resena_nueva()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_secret  text;
  v_url     text := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/resena-email';
  v_anon    text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk';
  v_estudio text;
  v_autora  text;
begin
  select e.nombre into v_estudio from public.estudios e where e.id = new.estudio_id;

  -- Cuenta borrada (lápida): "Anónimo", como en las pantallas.
  select case when u.rol = 'eliminado' then 'Anónimo'
              else coalesce(nullif(trim(u.nombre),''), 'Una alumna') end
    into v_autora
    from public.usuarios u where u.id = new.usuario_id;

  -- Campanita para cada admin (sin profes), salteando a la autora si es admin.
  insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
  select ea.usuario_id,
         '⭐ Nueva reseña',
         coalesce(v_autora,'Una alumna') || ' dejó una reseña de ' ||
         repeat('⭐', greatest(1, least(5, coalesce(new.rating,0)))) ||
         ' en ' || coalesce(v_estudio,'tu estudio'),
         'resena_nueva',
         false
    from public.estudio_admins ea
   where ea.estudio_id = new.estudio_id
     and ea.rol in ('estudio','admin_estudio')
     and ea.usuario_id <> new.usuario_id;

  -- Mail, fire-and-forget (mismo patrón que notif_email_nueva_reserva).
  v_secret := (select decrypted_secret from vault.decrypted_secrets where name='notif_trigger_secret');
  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object('Content-Type','application/json',
      'Authorization','Bearer '||v_anon,'apikey',v_anon,
      'x-notif-secret',coalesce(v_secret,'')),
    body := jsonb_build_object('kind','nueva','review_id', new.id)
  );
  return new;
exception when others then
  -- Un fallo del aviso jamás frena la reseña.
  return new;
end;
$$;

drop trigger if exists trg_notif_resena_nueva on public.study_reviews;
create trigger trg_notif_resena_nueva
  after insert on public.study_reviews
  for each row execute function public.notif_resena_nueva();

-- ----------------------------------------------------------------------------
-- 4 · El pedido post-clase.
--     Dedup por marca en la reserva: el cron corre cada 15 min con una ventana
--     de 15-45 min (más ancha que la cadencia para no perder el borde), así
--     que sin marca podría pedir dos veces.
-- ----------------------------------------------------------------------------
alter table public.reservas add column if not exists resena_pedida_at timestamptz;
comment on column public.reservas.resena_pedida_at is
  'Cuándo se le pidió la reseña post-clase (cron pedir_resenas_post_clase). NULL = todavía no. Es la marca de dedup del cron.';

create or replace function public.pedir_resenas_post_clase()
returns json
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_r        record;
  v_pedidas  int := 0;
  v_secret   text;
  v_url      text := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/resena-email';
  v_anon     text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk';
  v_ahora    timestamp := (now() at time zone 'America/Argentina/Buenos_Aires');
begin
  v_secret := (select decrypted_secret from vault.decrypted_secrets where name='notif_trigger_secret');

  for v_r in
    select r.id as reserva_id, r.usuario_id, c.id as clase_id, c.nombre as clase_nombre,
           c.estudio_id, e.nombre as estudio_nombre
      from public.reservas r
      join public.clases c on c.id = r.clase_id
      join public.estudios e on e.id = c.estudio_id
      join public.usuarios u on u.id = r.usuario_id
     where r.checked_in_at is not null                       -- SOLO quien asistió
       and r.resena_pedida_at is null                        -- dedup
       and coalesce(r.estado,'') in ('presente','completada')
       and u.rol is distinct from 'eliminado'                -- lápidas no
       -- la clase terminó hace entre 15 y 45 minutos
       -- duracion_min es bigint y make_interval exige int: sin el cast, 42883.
       and (c.fecha + make_interval(mins => coalesce(c.duracion_min,60)::int))
             between v_ahora - interval '45 minutes'
                 and v_ahora - interval '15 minutes'
       -- si ya reseñó este estudio, no molestamos
       and not exists (select 1 from public.study_reviews sr
                        where sr.estudio_id = c.estudio_id
                          and sr.usuario_id = r.usuario_id)
  loop
    -- Campanita. El tipo 'recordatorio_resena' YA está ruteado en la app:
    -- al tocarla va al detalle del estudio, donde se deja la reseña.
    insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
    values (v_r.usuario_id,
            '¿Cómo estuvo ' || coalesce(v_r.clase_nombre,'tu clase') || '?',
            'Contanos qué te pareció tu clase en ' || coalesce(v_r.estudio_nombre,'el estudio') ||
            '. Tu reseña ayuda a otras personas a descubrirlo 🧡',
            'recordatorio_resena',
            false);

    -- Mail, fire-and-forget.
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object('Content-Type','application/json',
        'Authorization','Bearer '||v_anon,'apikey',v_anon,
        'x-notif-secret',coalesce(v_secret,'')),
      body := jsonb_build_object('kind','pedido',
        'usuario_id', v_r.usuario_id, 'estudio_id', v_r.estudio_id,
        'clase_nombre', v_r.clase_nombre)
    );

    update public.reservas set resena_pedida_at = now() where id = v_r.reserva_id;
    v_pedidas := v_pedidas + 1;
  end loop;

  return json_build_object('ok', true, 'pedidas', v_pedidas);
end;
$$;

revoke execute on function public.pedir_resenas_post_clase() from public, anon, authenticated;
grant  execute on function public.pedir_resenas_post_clase() to service_role;

-- ----------------------------------------------------------------------------
-- El cron: cada 15 minutos, mismo patrón que completar-reservas (SQL directo,
-- sin edge function en el medio). La ventana de la función es 15-45 min y la
-- marca resena_pedida_at deduplica, así que la cadencia no puede duplicar.
-- ----------------------------------------------------------------------------
select cron.schedule('pedir-resenas-15min', '*/15 * * * *',
                     'select public.pedir_resenas_post_clase();');
