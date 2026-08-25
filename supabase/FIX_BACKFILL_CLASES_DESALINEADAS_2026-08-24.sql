-- ═══════════════════════════════════════════════════════════════════════════
-- BACKFILL · clases futuras publicadas a una hora que no es la de su grilla
-- 2026-08-24
--
-- QUE PASABA
-- 41 clases futuras de Citra Barre y Yessi Funes estaban publicadas a una hora
-- distinta de la que dice su horario_fijo. Son dano ANTERIOR al arreglo del
-- 24/8 (`FIX_GRILLA_MOVER_CLASES`), que evita casos nuevos pero no reparo los
-- viejos. El chequeo de existencia de `generar_clases_estudio` usa una ventana
-- de +/- 1 hora INCLUSIVA por grilla, asi que una vez corridas, el generador
-- las daba por "ya creadas" y no reponia las que faltaban.
--
-- POR QUE NO SE BORRAN (esto es lo importante)
-- A simple vista parecian 37 "duplicados": dos clases en el mismo minuto.
-- No lo eran. Medido: en los 13 grupos, el horario CORRECTO de cada clase
-- estaba LIBRE (destino_ocupado = 0, misma grilla y otras grillas).
--
-- Lo que pasaba es que dos grillas DISTINTAS chocaban en la hora equivocada:
--   Citra, lunes: grilla 18 = 08:30, grilla 20 = 09:30
--     31/08 al 28/09 -> las dos clases a las 08:30, el slot 09:30 VACIO
--     05/10 y 12/10  -> las dos a las 09:30, el slot 08:30 VACIO
--     19/10          -> correcto
-- O sea: cada fila es una clase LEGITIMA puesta a la hora equivocada.
-- Borrar "la duplicada" le habria sacado a Citra y Yessi 41 clases reales
-- que si dictan. La operacion correcta es MOVER: resuelve la colision y
-- repone la clase faltante en un solo paso.
--
-- SEGURIDAD DE LA OPERACION
--   * Solo clases FUTURAS. Las pasadas son historia (asistencias, liquidacion).
--   * `not exists (reserva viva)` como red de seguridad, aunque las 41 tenian
--     0 reservas: si alguna hubiera entrado entre la medicion y la aplicacion,
--     esa fila se saltea sola.
--   * El destino esta libre en los 13 grupos => no se crean colisiones nuevas.
--   * El precio no cambia: Citra y Yessi son `tipo_precio = 'fijo'` (18 y 11),
--     asi que la hora no entra en el calculo. Verificado despues: 0 desvios en
--     toda la base. (Corriendo como `postgres`, `clases_fija_precio` sale
--     temprano por la guarda de `current_user`; para un estudio en modo rango
--     este backfill habria que correrlo como `authenticated`.)
--   * `clases_resync_cupo` solo acota disponibles a [0, total]: sin efecto.
--   * `trg_clases_bloquear_borrado` es BEFORE DELETE: no interviene.
--
-- RESULTADO MEDIDO (dry run con rollback, despues aplicado)
--   41 clases movidas · 0 borradas · total futuro de Citra+Yessi 397 -> 397
--   colisiones 37 -> 1 · desalineadas 41 -> 0 · precios desviados 0
--   isodow != dia_semana 0 · cupos fuera de rango 0
--   Lunes de Citra: cada semana vuelve a tener 08:30 Y 09:30.
--
-- ⚠️ LA COLISION QUE QUEDA (1) NO ES DE ESTE CASO y no se toca aca:
-- YN Pilates, 31/08 11:00, dos clases identicas -- id 2441 de la grilla 239
-- (correcta) e id 2439 huerfana (horario_fijo_id null). Es un duplicado REAL,
-- con 0 reservas. Requiere un DELETE, no un move, y es decision aparte.
-- ═══════════════════════════════════════════════════════════════════════════

update public.clases c
   set fecha = (c.fecha::date + h.hora_inicio)::timestamp
  from public.horarios_fijos h
 where h.id = c.horario_fijo_id
   and c.fecha >= now()
   and to_char(c.fecha, 'HH24:MI') <> to_char(h.hora_inicio, 'HH24:MI')
   and not exists (
     select 1 from public.reservas r
      where r.clase_id = c.id
        and coalesce(r.estado, '') not in ('cancelada', 'cancelada_por_estudio')
   );
