-- ============================================================================
-- AURA — Limpieza de las reservas de prueba de Hot Clic
-- ============================================================================
-- (2026-08-22) APLICADO. Tanda 0, ítem 2.
--
-- QUÉ PASABA
-- El panel de cobros de Hot Clic mostraba $32.900 a cobrar que no existían:
-- 47 créditos de 4 reservas de prueba. `cobros_screen.dart:949` cuenta todo lo
-- que no está en estado 'cancelada', así que figuraban como plata real.
--
-- LAS 4 RESERVAS
--   id 6, 7, 8  · Hot Clic · tutiacotilla@gmail.com · junio · 15+10+10 cr
--   id 410      · Hot Clic · test@aura.com (rol admin_estudio) · 18/8 · 12 cr
-- Hot Clic es un estudio de prueba, así que nada de lo que figure ahí a cobrar
-- es real, venga de la cuenta que venga.
--
-- LO QUE NO SE TOCÓ
--   id 411 · Citra Barre · malekuipers@gmail.com · 18 cr · $12.600
-- Citra Barre es un estudio real y la reserva también (confirmado con la
-- usuaria). Citra empieza a pagar comisión el 13/9, así que esos $12.600 le
-- corresponden.
--
-- POR QUÉ CANCELAR Y NO BORRAR
-- Cancelar las saca del panel de cobros sin destruir historial, y se revierte
-- con un UPDATE. Borrar no aportaba nada: se verificó que NADA cuelga de
-- `reservas` (cero FKs hijas), o sea que la fila puede quedarse sin molestar.
--
-- EFECTOS SECUNDARIOS VERIFICADOS ANTES DE APLICAR
-- `reservas` tiene dos triggers y ninguno se activa con este cambio:
--   * `trg_reservas_columnas_sensibles` (BEFORE UPDATE) sale en la primera
--     línea con `current_user not in ('authenticated','anon')`. Desde el
--     editor SQL corre como postgres, así que no frena.
--   * `trg_notif_email_nueva_reserva` (AFTER INSERT OR UPDATE) sale con
--     `if NEW.estado is distinct from 'confirmada' then return NEW`. Como el
--     estado nuevo es 'cancelada', NO se dispara ningún mail al estudio.
-- Verificado también con un ensayo en transacción + rollback antes de aplicar.
-- ============================================================================

update public.reservas
   set estado = 'cancelada'
 where id in (6, 7, 8, 410);


-- ── RESULTADO (verificado tras aplicar) ─────────────────────────────────────
--   Hot Clic      0 reservas ·  0 cr · a cobrar $0        (antes: 4 / 47 / $32.900)
--   Citra Barre   1 reserva  · 18 cr · a cobrar $12.600   (intacta)
--   Las 5 filas siguen existiendo; sólo cambió el estado de 4.
--
-- ── PARA REVERTIR ───────────────────────────────────────────────────────────
-- update public.reservas set estado = 'completada' where id in (6,7,8,410);
--
-- ── VERIFICACIÓN (correr aparte) ────────────────────────────────────────────
-- select e.nombre,
--        count(*) filter (where r.estado <> 'cancelada') as cuentan,
--        coalesce(sum(r.creditos_usados) filter (where r.estado <> 'cancelada'),0) as creditos
--   from public.reservas r
--   join public.clases c on c.id = r.clase_id
--   join public.estudios e on e.id = c.estudio_id
--  group by 1 order by 1;
