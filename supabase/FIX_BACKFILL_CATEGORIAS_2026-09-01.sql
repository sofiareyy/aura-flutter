-- =============================================================================
-- BACKFILL de categorías vacías (2026-09-01) — corre UNA VEZ
-- =============================================================================
-- Por qué: 536 clases futuras y 61 grillas no tienen ninguna categoría. Hoy no
-- molesta (el chip de Explorar filtra por el perfil del estudio), pero con la
-- etapa E3 del rediseño —el filtro pasa a mirar la CLASE— esas clases no
-- matchearían ningún chip y quedarían invisibles. Se siembra la etiqueta
-- principal del perfil del estudio (`estudios.categorias[1]`) como punto de
-- partida; después se afina a mano o con etiquetas (E4).
--
-- ⚠️ Incluye `horarios_fijos` a propósito: `generar_clases_estudio` COPIA
-- `categorias` de la grilla a cada clase que crea (medido). Sin esta mitad, el
-- cron de las 03:00 volvería a crear clases sin categoría todas las noches y
-- el backfill se desharía solo.
--
-- Seguridad de precios: corre como `postgres`, y los dos triggers de precio
-- (`clases_fija_precio`, `horarios_fijos_fija_precio`) salen temprano con
-- `current_user not in ('authenticated','anon')`. O sea que NINGÚN precio se
-- recalcula. Se verifica con huellas md5 antes/después.
--
-- Sólo toca filas con el array VACÍO: lo ya cargado no se pisa nunca.
-- Sólo clases FUTURAS y no canceladas: el pasado no se busca ni se muestra.

-- 1) Las grillas primero (son la semilla de lo que se genera cada noche).
update public.horarios_fijos h
   set categorias = array[e.categorias[1]]
  from public.estudios e
 where e.id = h.estudio_id
   and coalesce(array_length(h.categorias, 1), 0) = 0
   and coalesce(array_length(e.categorias, 1), 0) > 0
   -- Nunca sembrar un servicio de precio fijo: la regla A exige que vaya solo
   -- y además movería el precio. Hoy no hay ninguno activo; es un cinturón.
   and not exists (
     select 1 from public.estudio_servicios_precio esp
      where esp.estudio_id = e.id and esp.activo and esp.servicio = e.categorias[1]
   );

-- 2) Y las clases futuras que ya están publicadas.
update public.clases c
   set categorias = array[e.categorias[1]]
  from public.estudios e
 where e.id = c.estudio_id
   and coalesce(array_length(c.categorias, 1), 0) = 0
   and coalesce(array_length(e.categorias, 1), 0) > 0
   and c.fecha > now()
   and c.cancelada = false
   and not exists (
     select 1 from public.estudio_servicios_precio esp
      where esp.estudio_id = e.id and esp.activo and esp.servicio = e.categorias[1]
   );
