-- MANTENIMIENTO: las dos tablas internas que crecían sin límite.
-- APLICADO EN PRODUCCIÓN el 2026-09-22. Este archivo es la copia de lo
-- que se corrió, para poder repetirlo o revisarlo. No es una migración
-- pendiente.
--
-- Contexto: Supabase avisó por Disk IO Budget. El diagnóstico del 22/9
-- descartó la app (base de 35 MB, 100% de aciertos en caché, crons de
-- menos de 0,2 s, Explorar/Inicio por índice). Lo único que crecía sin
-- freno eran estos dos historiales internos, que juntos ocupaban 14 de
-- los 35 MB de la base. Limpiarlos NO resuelve el aviso —el piso de IO
-- del plan free es el que manda—, es higiene.

-- 1. Historial de corridas de los crons: 11.236 filas desde mayo, sin
--    retención. Se borró todo lo anterior a 7 días (9.704 filas).
--    Las 30 fallidas eran de julio o antes, de bugs ya arreglados:
--    el make_interval de completar-reservas (21/7) y los dos avisos por
--    mail, hoy apagados, con la URL mal armada.
delete from cron.job_run_details
where start_time < now() - interval '7 days';

-- 2. Compactar. VACUUM a secas no devuelve el espacio: hay que FULL.
--    Son tablas de decenas de filas, así que el lock dura milisegundos.
--    job_run_details: 8432 kB -> 568 kB
--    _http_response:  6128 kB ->  72 kB
vacuum full cron.job_run_details;
vacuum full net._http_response;

-- 3. Que no vuelvan a inflarse. Corre 3:20 UTC = 00:20 de Argentina,
--    entre regenerar-grillas (3:00) y sync-vidriera (3:30).
--    Guarda 7 días de corridas exitosas y 30 días de las fallidas,
--    que son las que sirven para diagnosticar.
--    Probado en vivo el 22/9 poniéndolo cada minuto: corre en 0,06 s.
select cron.schedule(
  'purgar-historial-crons',
  '20 3 * * *',
  $$delete from cron.job_run_details where start_time < now() - interval '7 days' and status = 'succeeded'; delete from cron.job_run_details where start_time < now() - interval '30 days';$$
);

-- net._http_response NO necesita cron: pg_net ya se limpia solo y guarda
-- unas 6 horas (verificado: 24 filas, de 14:30 a 20:15). Lo suyo era
-- sólo el inflado, que el VACUUM FULL de arriba ya resolvió.
