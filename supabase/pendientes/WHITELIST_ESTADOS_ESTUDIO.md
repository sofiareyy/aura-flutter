# Pendiente: whitelist de estados que el estudio puede poner en `reservas`

Fecha de la nota: 2026-08-21. Sale de la auditoría pre-build.
**No es urgente** y es un modelo de amenaza distinto al que ya cerramos.

## Contexto

El 2026-08-21 se cerró la escritura directa del cliente sobre `reservas`
(ver `supabase/FIX_RESERVAS_ESCRITURA_CLIENTE_2026-08-21.sql`): trigger
`trg_reservas_columnas_sensibles` + borrado de la policy `reservas_insert_own`.

Ese fix cierra el agujero **del usuario**: una alumna ya no puede revivir una
reserva cancelada, marcarse presente, inflar `creditos_usados` ni mudarse de
clase, y tampoco puede insertar reservas gratis.

Lo que ese fix **deliberadamente NO toca** es *qué valores* de `estado` puede
poner el estudio. El trigger deja al estudio (cualquier fila en
`estudio_admins` de esa clase) escribir `estado` y `checked_in_at` libremente,
porque lo necesita para el escáner de QR (`asistencia_screen.dart`) y para
`cancelarClase` (`estudio_admin_service.dart:600`).

## El riesgo residual

Un estudio deshonesto puede dar vuelta una reserva `cancelada` -> `presente`.
Como `presente` está en `AppConstants.estadosLiquidables`, esa reserva se
factura. O sea: **el estudio puede inflar su propia liquidación**.

Está acotado, porque `creditos_usados` sí quedó bloqueado para todos (ni la
alumna ni el estudio lo tocan), así que el monto de cada reserva es el que se
fijó al reservar. Lo que el estudio puede manipular es *cuántas* reservas
entran en la liquidación, no cuánto vale cada una.

## Por qué se dejó afuera

Es un modelo de amenaza **distinto**: el agujero que se cerró estaba abierto a
cualquiera con una cuenta (superficie enorme); este requiere ser dueño de un
estudio en la plataforma, que hoy son 9 y todos conocidos. Mezclarlos en el
mismo cambio habría hecho más difícil verificar que no se rompía el escáner.

## Qué hacer cuando se retome

1. Definir la lista de transiciones legítimas del estudio. Borrador:
   - `confirmada` -> `presente` | `ausente`  (asistencia)
   - `confirmada` -> `cancelada`             (cancelarClase)
   - `presente`   <-> `ausente`              (corrección de un error de marcado)
   - **prohibido**: cualquier cosa que salga de `cancelada` /
     `cancelada_por_estudio` hacia un estado liquidable.

2. Agregarlo al trigger existente, en la rama `v_es_estudio` (no hace falta
   un trigger nuevo):

   ```sql
   if v_es_estudio
      and old.estado in ('cancelada', 'cancelada_por_estudio')
      and new.estado not in ('cancelada', 'cancelada_por_estudio') then
     raise exception 'Una reserva cancelada no se puede reactivar';
   end if;
   ```

3. Verificar con rollback **midiendo efecto**, las dos puntas:
   - el estudio ya NO puede pasar `cancelada` -> `presente`;
   - el escáner de QR (`confirmada` -> `presente`) y `cancelarClase`
     (`* -> cancelada`) siguen andando.
   La suite del archivo del fix sirve de base: agregar los casos nuevos y
   confirmar que las pruebas 8 y 9 siguen en verde.

4. Ojo con la corrección legítima: un estudio que marcó `ausente` por error y
   quiere volver a `presente` tiene que poder. No cerrar de más.

## Nota aparte

`reservas` no tiene historial de cambios de `estado`. Si esto llega a
importar para auditar liquidaciones, conviene una tabla de log (o
`admin_activity_logs`) antes que endurecer más el trigger — sin historial no
hay forma de detectar el abuso a posteriori, solo de prevenirlo.
