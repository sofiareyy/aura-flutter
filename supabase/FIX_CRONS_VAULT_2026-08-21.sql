-- =====================================================================
-- FIX: los 5 crons daban 401 contra las edge functions — 2026-08-21
-- Encontrado MIDIENDO en la auditoría pre-build. Aplicado vía Management
-- API y verificado con ejecución real (HTTP 200 + efecto medido).
-- Solo base, sin Dart => sin build.
-- =====================================================================
--
-- SÍNTOMA
-- `cleanup-lista-espera` devolvía HTTP 401 {"ok":false,"error":"No autorizado"}
-- cada 15 minutos, en toda la ventana que retiene pg_net. Los otros 4 crons
-- que llaman edge functions, igual.
--
-- OJO: `cron.job_run_details` decía "succeeded" para los 192 runs fallidos.
-- Solo reporta que el `net.http_post` se ENCOLÓ, no que el HTTP haya andado.
-- Para saber si un cron ejecuta hay que mirar `net._http_response`.
--
-- CAUSA RAÍZ (probada por hash, NO era un token vencido)
-- El token que mandaban los crons es la legacy service_role del proyecto y
-- es válida (no vence hasta 2036). Lo que cambió es la variable de entorno:
--
--   sha256(token del cron)                       = 81cee101...
--   sha256(legacy service_role actual)           = 81cee101...  <- idéntico
--   sha256(env SUPABASE_SERVICE_ROLE_KEY)        = c76bb568...
--   sha256(sb_secret_ nueva del proyecto)        = c76bb568...  <- idéntico
--
-- O sea: Supabase repuntó `SUPABASE_SERVICE_ROLE_KEY` a la key NUEVA
-- (`sb_secret_...`) al activarse el sistema nuevo de API keys. Las edge
-- functions comparan literal:
--     if (token !== SERVICE_ROLE_KEY) return 401
-- así que la legacy dejó de matchear aunque siga siendo válida.
-- Se verificó además que el código DESPLEGADO es el actual (se bajó el
-- bundle de producción), o sea que no era un deploy viejo.
--
-- DAÑO REAL CONFIRMADO
-- `regenerar-grillas` venía sin correr: Yessi Funes Fitness estaba en 35 días
-- de grilla en vez de 63. Al arreglarlo se generaron las 108 clases faltantes
-- (0 duplicados, verificado antes con rollback).
--
-- FIX
-- El secreto pasa al Vault y los 5 crons lo leen de ahí, en vez de tenerlo
-- hardcodeado en `cron.job.command` x5. Un solo lugar para rotar. Es el mismo
-- patrón que ya usan notif_push_nueva / notif_email_nueva_reserva.
-- =====================================================================


-- ---------------------------------------------------------------------
-- PASO 1: el secreto al Vault
-- ---------------------------------------------------------------------
-- Pegar el valor de la key `secret` (sb_secret_...) del proyecto:
--   Dashboard -> Project Settings -> API Keys -> secret (default)
-- NO commitear el valor. Acá va un placeholder a propósito.
/*
do $$
declare v_id uuid;
begin
  select id into v_id from vault.secrets where name = 'edge_service_key';
  if v_id is null then
    perform vault.create_secret('<<PEGAR sb_secret_... ACA>>', 'edge_service_key',
      'Service key que los crons mandan a las edge functions. Rotar SOLO aca.');
  else
    perform vault.update_secret(v_id, '<<PEGAR sb_secret_... ACA>>', 'edge_service_key',
      'Service key que los crons mandan a las edge functions. Rotar SOLO aca.');
  end if;
end $$;
*/

-- Chequeo: tiene que coincidir con el env var que ven las edge functions.
-- select encode(digest(decrypted_secret,'sha256'),'hex')
--   from vault.decrypted_secrets where name='edge_service_key';


-- ---------------------------------------------------------------------
-- PASO 2: los 5 crons leyendo del Vault
-- ---------------------------------------------------------------------
-- cron.schedule() con el mismo jobname reemplaza el job existente.

select cron.schedule('cleanup-lista-espera-15min', '*/15 * * * *', $cron$
  select net.http_post(
    url     := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/cleanup-lista-espera',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret
                                       from vault.decrypted_secrets
                                      where name = 'edge_service_key')
    ),
    body    := '{}'::jsonb
  );
$cron$);

select cron.schedule('regenerar-grillas-diario', '0 3 * * *', $cron$
  select net.http_post(
    url     := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/regenerar-grillas',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret
                                       from vault.decrypted_secrets
                                      where name = 'edge_service_key')
    ),
    body    := jsonb_build_object('weeks', 9)
  );
$cron$);

select cron.schedule('acreditar-creditos-corporativos-mensual', '0 3 1 * *', $cron$
  select net.http_post(
    url     := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/acreditar-creditos-corporativos',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret
                                       from vault.decrypted_secrets
                                      where name = 'edge_service_key')
    ),
    body    := '{}'::jsonb
  );
$cron$);

select cron.schedule('aviso-cobro-manana', '0 21 4 * *', $cron$
  select net.http_post(
    url     := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/aviso-cobro-manana',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret
                                       from vault.decrypted_secrets
                                      where name = 'edge_service_key')
    ),
    body    := '{}'::jsonb
  );
$cron$);

select cron.schedule('reporte-mensual-estudios', '0 12 1 * *', $cron$
  select net.http_post(
    url     := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/reporte-mensual-estudios',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret
                                       from vault.decrypted_secrets
                                      where name = 'edge_service_key')
    ),
    body    := '{}'::jsonb
  );
$cron$);


-- =====================================================================
-- VERIFICACIÓN — ejecución REAL, no encolado
-- =====================================================================
-- Corrida del 2026-08-21, disparando el comando exacto de cada cron:
--
--   cleanup-lista-espera             HTTP 200  {"ok":true,"liberadas":1,...}
--       fixture: 1 pre_confirmada vencida + cupo descontado en la clase 333.
--       efecto: la reserva se liberó y el cupo volvió de 13 a 14. Neto cero.
--   acreditar-creditos-corporativos  HTTP 200  {"empresas":0,"usuarios":0,"creditos":0}
--       efecto nulo garantizado (0 empresas). Ledger sin cambios: 15 / 353.
--   regenerar-grillas                HTTP 200  {"creadas":108,"omitidas":513}
--       efecto: 777 -> 885 clases. Yessi Funes 35d -> 56d. 0 duplicados.
--   aviso-cobro-manana               NO disparado (manda mails a estudios)
--   reporte-mensual-estudios         NO disparado (manda mails a estudios)
--
-- Estas dos últimas tienen verify_jwt=TRUE en la plataforma, así que el
-- gateway valida el header ANTES de la función y `sb_secret_` no es un JWT.
-- Se comprobó que igual pasa, sin mandar mails: se sondeó `admin-crear-estudio`
-- (también verify_jwt=true) con la sb_secret y SIN el header `x-aura-auth`.
-- La respuesta fue {"error":"Sin autorizacion"} — el 401 de la FUNCIÓN, no del
-- gateway. O sea que el gateway acepta la key nueva. Nada se creó.
--
-- Para chequear un cron a mano (dispara de verdad):
--   do $$ declare cmd text; begin
--     select command into cmd from cron.job where jobname='<nombre>';
--     execute cmd; end $$;
--   select pg_sleep(15);
--   select created, status_code, content from net._http_response
--    order by created desc limit 1;


-- =====================================================================
-- NOTA: la fuga de net.http_request_queue NO se pudo cerrar (ni hace falta)
-- =====================================================================
-- `net.http_request_queue` y `net._http_response` tienen grant de ALL a
-- PUBLIC (`=arwdDxtm/supabase_admin`), y en la cola viaja el header
-- Authorization completo. Se intentó revocar y NO se puede:
--   - el grant lo hizo `supabase_admin`, y `postgres` no es superusuario
--     ni puede `set role supabase_admin` (permission denied);
--   - un REVOKE de un grant ajeno Postgres lo ignora en SILENCIO (dice OK
--     y no cambia nada). Verificado: los privilegios seguían en true.
--   - el SQL editor del dashboard corre como postgres => mismo límite.
--
-- Pero NO es explotable, medido:
--   - PostgREST expone solo `public, graphql_public`; `net` no se alcanza
--     por la API;
--   - anon / authenticated / service_role tienen rolcanlogin = false y sin
--     password: no hay forma de ser esos roles salvo vía PostgREST o con
--     un SET ROLE desde una conexión que ya requiere credenciales de base.
-- O sea: quien pudiera leer esa cola ya entró como postgres y tiene todo.
-- Queda documentado por si algún día se crea un rol de login con menos
-- privilegios (ej. analytics), que ahí sí importaría.

-- (fin)
