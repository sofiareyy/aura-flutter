# Tres relevamientos del 2026-08-27 — estado al 28/8

## ✅ CONSTRUIDO el 28/8 (lote de base):
- **A · Comisión congelada**: columnas `comision_aplicada` /
  `valor_credito_aplicado` / `comision_workshop_aplicada` en `liquidaciones`,
  selladas por trigger al marcar PAGADO y nunca re-estampadas. La gracia se
  evalúa con la fecha del pago (Citra pagada el 5/9 sella 0%; el 5/10, 30%).
  La fila ya pagada se rellenó derivando de sus propios montos (8400/12000 ⇒
  30%). Falta SOLO el Dart del build 27: que la pantalla muestre el congelado.
  `FEAT_COMISION_CONGELADA_2026-08-28.sql`.
- **B3 · Aviso de reseña al estudio**: trigger AFTER INSERT en `study_reviews`
  ⇒ campanita a los admins (sin profes, sin la autora) + mail vía la edge
  function nueva `resena-email`. Editar la propia reseña NO re-spamea (medido).
- **B4 · Pedido de reseña post-clase**: cron `pedir-resenas-15min` (*/15) ⇒
  `pedir_resenas_post_clase()`: SOLO quien tiene `checked_in_at`, clase
  terminada hace 15-45 min, dedup por `reservas.resena_pedida_at`, saltea
  lápidas y a quien ya reseñó ese estudio. Campanita tipo
  `recordatorio_resena` (ya ruteado en la app instalada) + mail con botón a
  la pantalla del estudio. Medido: pide a quien asistió; sin check-in o con
  reseña previa, nada; segunda corrida no duplica.
  El push se suma solo cuando APNs esté: la misma fila dispara el trigger de push.

## 🔴 B-UNIQUE · NO se aplicó — bloqueante medido, va al build 27
El plan era `UNIQUE NULLS NOT DISTINCT (estudio_id, usuario_id, clase_id)`.
**Probado el 28/8: rompe la app instalada.** El upsert del build 25/26 manda
`on conflict (estudio_id, usuario_id)`, y sin ese índice exacto Postgres
devuelve **42P10** ⇒ nadie podría crear NI editar reseñas hasta actualizar.
**Va al build 27 como cambio conjunto**: el índice nuevo en base + el Dart
cambiando a `onConflict: 'estudio_id,usuario_id,clase_id'` (y pasando el
`claseId`, que el service ya acepta). Aplicar la base recién con adopción.

---

# El relevamiento original (27/8)

---

# A · Congelar la comisión de los meses ya pagados

**La regla de la usuaria:** cambiar la comisión de un estudio afecta **sólo al
futuro**. Un mes ya pagado queda como constancia con la comisión que tenía.

## Qué hay hoy

`liquidaciones` guarda: `monto_total_reservas`, `monto_a_pagar`,
`cantidad_reservas`, `estado`, `fecha_pago`, `comprobante_nota`.

⚠️ **NO guarda la comisión ni el valor del crédito** que se aplicaron.

## El problema, medido

`admin_liquidaciones_screen.dart` **recalcula todo en vivo** desde `reservas`
cada vez que se abre, con la comisión **actual**. De la liquidación guardada
sólo toma `estado`, `fecha_pago`, `comprobante_nota` e `id`:

```dart
'monto_pagar': montoPagar,          // ← el recalculado, NO liq['monto_a_pagar']
'estado':      liq?['estado'] ?? 'pendiente',
```

⇒ Bajarle hoy la comisión a un estudio cambia lo que la pantalla muestra para
**meses ya pagados**. Medido con Citra (54 créditos): a 30% son **$37.800**, a
20% pasan a **$43.200**, y son reservas del 19/8, 25/8 y 27/8.

## El arreglo — sí es casi tan simple como pensaba, con un matiz

**La idea correcta:** si el mes tiene liquidación con `estado = 'pagado'`,
mostrar el **`monto_a_pagar` guardado**; si no, recalcular con la comisión
actual.

**El matiz:** hoy `monto_a_pagar` se guarda al registrar la liquidación, así
que para los meses ya pagados **el número congelado ya existe** y alcanza con
mostrarlo. Pero **la comisión no se guarda**, así que la pantalla no puede
*explicar* el número viejo ("se pagó al 30%") ni recomponerlo si hiciera falta.

**Recomendado:** sumar a `liquidaciones` tres columnas de constancia —
`comision_aplicada`, `valor_credito_aplicado` y, opcionalmente,
`comision_workshop_aplicada`— que se llenen al registrar el pago. Barato ahora
que hay **1 sola fila**; carísimo de reconstruir dentro de un año.

## Base vs Dart

**🟢 Base:** las 3 columnas nuevas en `liquidaciones` + que la RPC/insert que
registra el pago las complete con los valores del momento.
**🔵 Dart:** que la pantalla muestre el congelado cuando `estado = 'pagado'`, y
que el detalle diga "pagado al 30%". También el panel del estudio, para que las
dos vistas cuenten lo mismo.

---

# B · Reseñas: dónde se ven y qué falta

## Lo que YA existe

- **La alumna SÍ las ve.** `detalle_estudio_screen` y `detalle_clase_screen`
  cargan `getReviewsForStudy()`, muestran el promedio de estrellas y un
  preview de 2 reseñas. **Ya generan confianza donde más vale.**
- **La policy es `SELECT using (true)`**: las reseñas son públicas. Verificado:
  Citra **puede** leer la de Juanita — no es un problema de permisos.
- El promedio del estudio se recalcula solo con
  `trg_study_reviews_refresh_rating_*`.

## Lo que FALTA

1. 🔴 **El panel del estudio no tiene NINGUNA pantalla de reseñas.** Cero.
   Por eso Citra no la ve: no es que esté escondida, es que no existe la
   pantalla. Los datos ya están y ya son legibles para ella.
2. 🔴 **No hay ninguna notificación al estudio por una reseña nueva.** Los tres
   triggers de `study_reviews` sólo recalculan el rating; ninguno escribe en
   `notificaciones_usuario`.

## Qué hace falta para cada cosa

**(a) Que Citra vea sus reseñas** → **sólo Dart**. Una pantalla nueva en el
panel + su ítem en el sidebar. No hace falta nada de base: la policy ya se lo
permite y los datos están.

**(b) Que los usuarios las vean** → **ya funciona**. Nada que hacer.

**(c) Que le llegue aviso al estudio** → **base** (un trigger sobre
`study_reviews` que inserte en `notificaciones_usuario`, que es lo que dispara
campanita + push) **+ Dart** sólo si se quiere un `tipo` nuevo ruteado a la
pantalla nueva.
⚠️ Con la salvedad de siempre: **el push no llega a nadie** (ver el
relevamiento de reseñas: los únicos tokens son los de la propia usuaria y
fallan con `THIRD_PARTY_AUTH_ERROR`). La **campanita dentro de la app sí
funciona**.

---

# C · `valor_credito` en null — la causa raíz

## La causa, encontrada

Al crear un estudio, el trigger `trg_estudios_datos_cobro` inserta la fila de
cobro con **una sola columna**:

```sql
insert into public.estudios_datos_cobro (estudio_id) values (new.id)
on conflict (estudio_id) do nothing;
```

Todo lo demás cae a los defaults de columna:

| Columna | Default | Resultado |
|---|---|---|
| `comision_aura` | 30 | ✅ |
| `comision_workshop` | 15 | ✅ |
| `dia_pago` | 5 | ✅ |
| **`valor_credito`** | **ninguno** | ❌ **NULL** |

⇒ **La usuaria tenía razón: TODO estudio nuevo nace con `valor_credito` NULL.**
No es un olvido puntual con Tiwar y YN; es estructural. Y `admin_upsert_estudio`
tampoco lo setea (no tiene parámetro para eso).

## ⚠️ PERO: null NO está roto, y llenarlo sería el error

`ValorCredito.deEstudio()` hace: *el del estudio si lo tiene y es > 0; si no,
**el global***. Y el global (`configuracion_global.valor_credito_ars`) es
**1000**, que es exactamente lo que tienen los otros 9 en duro.

Los **tres** caminos aplican el mismo fallback, verificado: la app
(`valor_credito.dart`), el reporte mensual (`reporte-mensual-estudios`,
`valorCred(estudio, valorGlobal)`) y la base (`valor_credito_global()`, que
además devuelve 1000 ante cualquier error).

⇒ **Tiwar y YN se liquidan a 1000, igual que todos. No hay ni un peso mal.**

## El riesgo real es el OPUESTO al que se temía

`valor_credito` por estudio es un **override** del global. NULL significa
"seguí al global", que es lo correcto para un estudio a tarifa estándar.

**Los raros son los 9 con 1000 en duro.** Simulado: si mañana se sube el
crédito global a 1200, **Tiwar y YN acompañan a 1200 y los otros 9 quedan
clavados en 1000.**

| | hoy | si el global sube a 1200 |
|---|---|---|
| Citra (1000 explícito) | 1000 | **1000** ← se queda |
| Tiwar (null) | 1000 | **1200** ← acompaña |
| YN (null) | 1000 | **1200** ← acompaña |

## ✅ RESUELTO el 27/8 — opción (a), aplicada

**Decisión de la usuaria: NULL = seguí el global; el valor propio es SÓLO para
una excepción negociada.**

Aplicado (`FIX_VALOR_CREDITO_SIGUE_AL_GLOBAL_2026-08-27.sql`):
- Tiwar y YN se dejaron en NULL: estaban bien.
- Los 9 que tenían **1000 en duro** se limpiaron a NULL. **Verificado antes de
  tocar: los 11 eran 2 en NULL + 9 en exactamente 1000, y CERO con un valor
  negociado distinto**, así que no se pisó ninguna excepción. El `= global` del
  WHERE es el seguro por si alguno tuviera otro número.
- La columna quedó **documentada en la base** con `comment on column`, para que
  el próximo que lea un NULL sepa que es intencional y no un alta incompleta.

Tres puntas medidas:
- **Hoy liquidan igual:** los 11 dan 1000. Citra sigue en 54 créditos =
  $54.000 bruto = **$37.800** al 30%, el mismo número que antes.
- **Si el global sube a 1200: los 11 acompañan** (antes sólo lo hacían 2).
- **El override sigue funcionando:** con un valor negociado de 1500, Citra
  ignora el global y los demás lo siguen.

### ⚠️ Lo que queda pendiente de esto

El trigger `crear_datos_cobro_estudio` sigue insertando sólo `estudio_id`, o
sea que **un estudio nuevo sigue naciendo con `valor_credito` NULL — y ahora
eso es exactamente lo correcto**. No hay que "arreglarlo".
Lo que SÍ conviene, si alguna vez se negocia un valor distinto: que el
backoffice tenga dónde cargarlo. Hoy `admin_upsert_estudio` **no tiene
parámetro para `valor_credito`**, así que una excepción negociada sólo se puede
cargar por SQL.

## La decisión de fondo (era de negocio, no técnica)

**(a) NULL = "tarifa estándar", override sólo para excepciones.** Es el diseño
actual y funciona. Entonces **no hay que tocar Tiwar ni YN**, y lo que conviene
es **limpiar los 9 explícitos a NULL** para que todos acompañen al global.

**(b) Cada estudio con su valor explícito.** Entonces sí hay que ponérselo a
Tiwar y YN, **y** hacer que el alta lo exija: darle `default 1000` a la columna
o que el trigger lo complete con `valor_credito_global()`.

**En los dos casos, el arreglo de causa raíz es el mismo y es de BASE:** que la
fila de cobro nazca con un valor sensato en vez de NULL, o que quede
documentado que NULL es intencional.

**Resuelto arriba.** Se aplicó la opción (a) el 27/8.
