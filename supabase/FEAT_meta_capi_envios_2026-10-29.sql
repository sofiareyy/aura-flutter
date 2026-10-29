-- 29/10/2026: los eventos a Meta no frenan nunca un pago, y sólo se mandan
-- las compras web.
--
--   · meta_capi_eventos.payload: todo lo necesario para mandar (o reintentar)
--     el evento. Lo anotan las funciones de pago; meta-capi-event lo manda.
--   · pagos.plataforma: 'web' o 'app', según desde dónde se armó el checkout.
--     Sólo los 'web' se mandan a Meta. Los pagos viejos quedan en null: no se
--     mandan.
--   · Cron meta-capi-reintentos: cada 10 minutos manda lo pendiente o fallido
--     (hasta 5 intentos, eventos de menos de 6 días). Sin token cargado, no
--     hace nada y los eventos esperan.
--
-- ORDEN AL APLICAR: este SQL ANTES de deployar mp-webhook. El webhook nuevo
-- lee pagos.plataforma: sin la columna, falla al buscar el pago y no acredita.
--
-- Para volver atrás: ROLLBACK_meta_capi_envios_2026-10-29.sql

alter table public.meta_capi_eventos
  add column if not exists payload jsonb;

alter table public.pagos
  add column if not exists plataforma text
  check (plataforma is null or plataforma in ('web', 'app'));

-- Para que el cron encuentre rápido lo que falta mandar.
create index if not exists meta_capi_eventos_por_mandar
  on public.meta_capi_eventos (created_at)
  where status in ('pending', 'failed');

-- Misma clave que los otros crons que llaman funciones (edge_service_key del
-- Vault): meta-capi-event la compara con su clave de servidor.
select cron.schedule(
  'meta-capi-reintentos',
  '*/10 * * * *',
  $cron$
  select net.http_post(
    url     := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/meta-capi-event',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret
                                       from vault.decrypted_secrets
                                      where name = 'edge_service_key')
    ),
    body    := '{"reintentar": true}'::jsonb,
    timeout_milliseconds := 60000
  );
  $cron$
);
