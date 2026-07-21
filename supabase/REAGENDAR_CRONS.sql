-- ============================================================================
-- Reagendar los cron jobs que llaman Edge Functions
-- ============================================================================
--
-- Correr ESTO ANTES de re-deployar las 3 funciones cron (cleanup, regenerar,
-- acreditar). Orden:
--   1. Este SQL  → los crons pasan a mandar el service_role.
--   2. db functions deploy → las funciones nuevas ya lo validan.
-- Así no hay ventana rota.
--
-- ⚠️ Reemplazá <PEGAR_SERVICE_ROLE> por el service_role key real, que sacás
-- de: Dashboard → Project Settings → API → `service_role` (botón Reveal).
-- NO lo pegues en ningún chat ni lo commitees: este archivo con el key
-- reemplazado NO debe subirse al repo.
--
-- Qué corrige respecto de lo que había:
--   * aviso-cobro-manana y reporte-mensual mandaban 'Bearer TU_SERVICE_ROLE_KEY'
--     (placeholder literal) y tenían la URL cortada con un salto de línea →
--     hoy fallan. Se reescriben enteros.
--   * cleanup y regenerar mandaban el anon key → dejaban de pasar con el auth
--     nuevo. Ahora mandan el service_role.
--   * regenerar-grillas: weeks 4 → 9.
--
-- cron.schedule() hace UPSERT por jobname: re-emitir con el mismo nombre
-- reemplaza el job, no lo duplica.
-- ============================================================================

-- cada 15 min
select cron.schedule(
  'cleanup-lista-espera-15min',
  '*/15 * * * *',
  $$
  select net.http_post(
    url     := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/cleanup-lista-espera',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer <PEGAR_SERVICE_ROLE>'
    ),
    body    := '{}'::jsonb
  );
  $$
);

-- diario 00:00 ART (03:00 UTC) — weeks ahora 9
select cron.schedule(
  'regenerar-grillas-diario',
  '0 3 * * *',
  $$
  select net.http_post(
    url     := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/regenerar-grillas',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer <PEGAR_SERVICE_ROLE>'
    ),
    body    := jsonb_build_object('weeks', 9)
  );
  $$
);

-- día 1 de cada mes, 00:00 ART (03:00 UTC)
select cron.schedule(
  'acreditar-creditos-corporativos-mensual',
  '0 3 1 * *',
  $$
  select net.http_post(
    url     := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/acreditar-creditos-corporativos',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer <PEGAR_SERVICE_ROLE>'
    ),
    body    := '{}'::jsonb
  );
  $$
);

-- día 4, 18:00 ART (21:00 UTC) — URL en UNA línea (antes venía cortada)
select cron.schedule(
  'aviso-cobro-manana',
  '0 21 4 * *',
  $$
  select net.http_post(
    url     := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/aviso-cobro-manana',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer <PEGAR_SERVICE_ROLE>'
    ),
    body    := '{}'::jsonb
  );
  $$
);

-- día 1, 09:00 ART (12:00 UTC) — URL en UNA línea (antes venía cortada)
select cron.schedule(
  'reporte-mensual-estudios',
  '0 12 1 * *',
  $$
  select net.http_post(
    url     := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/reporte-mensual-estudios',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer <PEGAR_SERVICE_ROLE>'
    ),
    body    := '{}'::jsonb
  );
  $$
);

-- 'completar-reservas' NO se toca: es SQL puro (select completar_reservas_
-- vencidas()), no llama HTTP ni necesita auth.

-- ── VERIFICACION ────────────────────────────────────────────────────────────
-- select jobname, schedule, active from cron.job order by jobname;
--
-- Ejecuciones recientes y su estado (después de que corran):
-- select jobid, status, return_message, start_time
--   from cron.job_run_details order by start_time desc limit 20;
