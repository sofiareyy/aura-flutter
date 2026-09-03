-- ============================================================================
-- APAGAR el mail "mañana cobrás" (aviso-cobro-manana) — 2026-09-02
-- APLICADO EN PRODUCCION el 2/9/2026 21:0x ART.
--
-- Decisión de Sofía: el mail del día 4 no aporta. El estudio ya sabe que cobra
-- el 5 y tiene la pantalla de Cobros, que lee las liquidaciones reales.
--
-- QUÉ SE HIZO: se DESACTIVA el disparador. No se borra nada.
--   * el job de pg_cron queda en la tabla con active = false
--   * la edge function `aviso-cobro-manana` queda DEPLOYADA y ACTIVE
--   * el botón manual del backoffice (Liquidaciones → "Enviar aviso de cobro")
--     sigue andando, con su diálogo de confirmación
--
-- POR QUÉ DESACTIVAR Y NO `cron.unschedule`:
--   el comando que está vivo en el job trae la service key desde
--   `vault.decrypted_secrets`. La copia del repo (REAGENDAR_CRONS.sql) tiene el
--   placeholder `<PEGAR_SERVICE_ROLE>`. Un unschedule borraría la ÚNICA copia
--   buena del comando y reactivarlo obligaría a rearmarlo a mano.
-- ============================================================================

select cron.alter_job(job_id := 1, active := false);

-- Verificación:
--   select jobid, jobname, schedule, active from cron.job order by jobid;
--   ⇒ jobid 1 en active=false, los otros 7 en true.

-- ── PARA REACTIVARLO algún día (un solo renglón, no hace falta nada más) ────
-- select cron.alter_job(job_id := 1, active := true);

-- ── Probado empíricamente el 2/9, porque "inactivo no corre" era una nota y
--    no una medición (job de prueba `select 1`, cada minuto, ya borrado):
--      activo    → corrió a las 21:08:00
--      inactivo  → 0 corridas en los 4 minutos siguientes
