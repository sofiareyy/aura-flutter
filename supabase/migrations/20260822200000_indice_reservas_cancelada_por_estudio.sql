-- ============================================================================
-- AURA — El indice unico se olvidaba de `cancelada_por_estudio`
-- ============================================================================
-- (2026-08-22) Tanda A, item 4.
--
-- EL BUG
-- `reservas_usuario_clase_uidx` excluia SOLO el estado 'cancelada':
--     WHERE estado <> 'cancelada'
-- Pero hay DOS estados muertos, no uno. El codigo lo sabe y el indice no:
--
--   apply_reservation:  estado not in ('cancelada', 'cancelada_por_estudio')
--   el indice:          WHERE estado <> 'cancelada'
--
-- O sea que si un estudio cancelaba una clase (la reserva queda en
-- 'cancelada_por_estudio') y despues la reabria, la fila muerta seguia
-- ocupando el lugar unico. `apply_reservation` decia "podes volver a
-- reservar", intentaba el insert, el indice lo rechazaba con unique_violation,
-- y el `exception when unique_violation` lo traducia a 'ya_reservaste'.
--
-- Sintoma para la usuaria: "ya reservaste" en una clase que NUNCA pudo
-- reservar, porque se la habian cancelado.
--
-- EL SET COMPLETO DE ESTADOS (relevado en base y en Dart)
--   vivos:   confirmada, pre_confirmada, presente, ausente, completada
--   muertos: cancelada, cancelada_por_estudio
-- Son exactamente dos muertos. Ningun otro estado tiene el mismo problema.
--
-- POR QUE ES SEGURO
-- DROP + CREATE dentro de una transaccion: el DDL en Postgres es
-- transaccional, asi que no hay ni un instante sin el indice. Con 5 filas es
-- instantaneo.
--
-- VERIFICADO (con rollback antes, y contra el indice real despues)
--   * re-reservar tras cancelacion del estudio: ANTES bloqueada, AHORA pasa
--   * doble reserva ACTIVA de la misma clase: sigue bloqueada
--   * una 'cancelada' normal sigue sin estorbar
--   * indice valido, unico y listo. Produccion sin tocar: 5 reservas.
--
-- OJO: `reservas.estado` NO tiene CHECK constraint, o sea que acepta cualquier
-- string. Si algun dia se agrega un tercer estado muerto, hay que acordarse de
-- sumarlo aca. Un CHECK con la whitelist de estados cerraria eso; queda como
-- pendiente de la Tanda A.
-- ============================================================================

begin;

drop index public.reservas_usuario_clase_uidx;

create unique index reservas_usuario_clase_uidx
    on public.reservas (usuario_id, clase_id)
 where estado not in ('cancelada', 'cancelada_por_estudio');

commit;

-- ── VERIFICACION (correr aparte) ────────────────────────────────────────────
-- select indexdef from pg_indexes where indexname = 'reservas_usuario_clase_uidx';
