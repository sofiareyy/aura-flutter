-- AURA - Soporte para los crons de lista de espera y regeneración de grillas
-- (2026-07-09).
--
-- PARTE A (RPC + grants): correr siempre. Es idempotente.
-- PARTE B (scheduling con pg_cron): correr DESPUÉS de deployar las Edge
--   Functions y de setear el secret CRON_SECRET. Reemplazar los placeholders.


-- ══════════════════════════════════════════════════════════════════════════
-- PARTE A — RPC agregada + permisos para el service role
-- ══════════════════════════════════════════════════════════════════════════

-- Regenera las clases de TODOS los estudios con horarios fijos activos.
-- Reutiliza generar_clases_estudio (idempotente, no duplica ±1h).
create or replace function public.generar_clases_todos_estudios(
  p_weeks int default 4
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estudio_id     int;
  v_res            json;
  v_estudios       int := 0;
  v_total_creadas  int := 0;
  v_total_omitidas int := 0;
begin
  for v_estudio_id in
    select distinct estudio_id
      from public.horarios_fijos
     where coalesce(activo, true) = true
  loop
    v_res := public.generar_clases_estudio(v_estudio_id, p_weeks);
    v_total_creadas  := v_total_creadas  + coalesce((v_res->>'creadas')::int, 0);
    v_total_omitidas := v_total_omitidas + coalesce((v_res->>'omitidas')::int, 0);
    v_estudios := v_estudios + 1;
  end loop;

  return json_build_object(
    'estudios', v_estudios,
    'creadas',  v_total_creadas,
    'omitidas', v_total_omitidas
  );
end;
$$;

-- El service role (que usan las Edge Functions) necesita poder ejecutar
-- estas funciones. Las de lista de espera ya tienen grant a service_role
-- (ver FIX_WAITLIST_FLOW.sql).
grant execute on function public.generar_clases_estudio(int, int)
  to authenticated, service_role;
grant execute on function public.generar_clases_todos_estudios(int)
  to authenticated, service_role;

-- Uso manual de prueba:
--   select public.generar_clases_todos_estudios(4);


-- ══════════════════════════════════════════════════════════════════════════
-- PARTE B — Scheduling con pg_cron (correr al final, con placeholders)
-- ══════════════════════════════════════════════════════════════════════════
--
-- Requisitos previos:
--   1. Deployá las Edge Functions:
--        supabase functions deploy cleanup-lista-espera --no-verify-jwt
--        supabase functions deploy regenerar-grillas    --no-verify-jwt
--   2. Seteá el secret CRON_SECRET (un string random tuyo) para las funciones:
--        supabase secrets set CRON_SECRET=algo-largo-y-secreto
--   3. Reemplazá abajo:
--        <PROJECT_REF>  -> el ref de tu proyecto (xxxx en xxxx.supabase.co)
--        <ANON_KEY>     -> tu anon/public key (solo sirve para pasar el gateway)
--        <CRON_SECRET>  -> el MISMO valor que seteaste en el paso 2
--
-- Nota: pg_cron corre en horario UTC. Argentina es UTC-3 (sin DST), así que
-- 00:00 ART = 03:00 UTC.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- (Re)crear los jobs de forma idempotente.
select cron.unschedule('cleanup-lista-espera-15min')
  where exists (select 1 from cron.job where jobname = 'cleanup-lista-espera-15min');
select cron.unschedule('regenerar-grillas-diario')
  where exists (select 1 from cron.job where jobname = 'regenerar-grillas-diario');

-- CRÍTICO 2 — lista de espera: cada 15 minutos.
select cron.schedule(
  'cleanup-lista-espera-15min',
  '*/15 * * * *',
  $$
  select net.http_post(
    url     := 'https://<PROJECT_REF>.supabase.co/functions/v1/cleanup-lista-espera',
    headers := jsonb_build_object(
      'Content-Type',   'application/json',
      'Authorization',  'Bearer <ANON_KEY>',
      'x-cron-secret',  '<CRON_SECRET>'
    ),
    body    := '{}'::jsonb
  );
  $$
);

-- CRÍTICO 3 — regeneración de grillas: 00:00 ART = 03:00 UTC.
select cron.schedule(
  'regenerar-grillas-diario',
  '0 3 * * *',
  $$
  select net.http_post(
    url     := 'https://<PROJECT_REF>.supabase.co/functions/v1/regenerar-grillas',
    headers := jsonb_build_object(
      'Content-Type',   'application/json',
      'Authorization',  'Bearer <ANON_KEY>',
      'x-cron-secret',  '<CRON_SECRET>'
    ),
    body    := jsonb_build_object('weeks', 4)
  );
  $$
);

-- Verificación:
--   select jobname, schedule, active from cron.job order by jobname;
