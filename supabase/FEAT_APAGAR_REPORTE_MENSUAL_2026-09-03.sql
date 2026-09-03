-- ============================================================================
-- APAGAR el reporte mensual a los estudios (reporte-mensual-estudios)
-- APLICADO EN PRODUCCION el 3/9/2026 16:16 ART.
--
-- Mismo criterio que FEAT_APAGAR_AVISO_COBRO_2026-09-02.sql: se DESACTIVA el
-- disparador, no se borra nada.
--   * el job de pg_cron queda en la tabla con active = false
--   * la edge function `reporte-mensual-estudios` queda DEPLOYADA y ACTIVE
--   * el botón manual del backoffice (Liquidaciones → "Enviar reporte mensual")
--     sigue andando, con su diálogo de confirmación
--
-- POR QUÉ DESACTIVAR Y NO `cron.unschedule`:
--   igual que con el aviso de cobro, el comando vivo en el job trae la service
--   key desde `vault.decrypted_secrets`, y la copia del repo
--   (REAGENDAR_CRONS.sql) tiene el placeholder `<PEGAR_SERVICE_ROLE>`. Un
--   unschedule borraría la ÚNICA copia buena del comando.
--
-- ⚠️ CONTEXTO: esta función ya no le mandaba nada a nadie. Filtra
--   `estado === 'presente'`, pero el cron `completar-reservas` mueve todo a
--   `completada` cada hora, así que el día 1 no encuentra ninguna y todos los
--   estudios caen en `sin_reservas`. Apagarla no cambia lo que recibe el
--   estudio: formaliza lo que ya pasaba. Ver la nota en RETOMAR_ACA.
-- ============================================================================

select cron.alter_job(job_id := 2, active := false);

-- Verificación:
--   select jobid, jobname, schedule, active from cron.job order by jobid;
--   ⇒ jobid 1 y 2 en active=false, los otros 6 en true.

-- ── PARA REACTIVARLO algún día ───────────────────────────────────────────────
-- select cron.alter_job(job_id := 2, active := true);
--   ⚠️ Antes de reactivarlo, arreglar el filtro de estado o va a seguir sin
--      mandar nada.

-- ── Probado empíricamente el 3/9 (job de prueba `select 1` cada minuto, ya
--    borrado): ACTIVO corrió a las 16:16:00; INACTIVO, 0 corridas después.
