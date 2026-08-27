# Reseñas: notificación post-clase + contexto de clase/fecha

Relevado el 2026-08-27 midiendo contra la base. **Nada construido.**

## 1. Cómo funcionan HOY — la buena noticia

**Las reseñas YA van al ESTUDIO, no a la clase.** `study_reviews` existe con:

```
estudio_id  bigint  NOT NULL   -> estudios(id)
usuario_id  uuid    NOT NULL
clase_id    bigint  NULL       -> clases(id) ON DELETE SET NULL   ← el contexto que querés
experiencia_label text NULL
rating      int     NOT NULL   CHECK 1..5
comentario  text    NOT NULL   CHECK largo >= 8
created_at  timestamptz        ← la fecha que querés
updated_at  timestamptz
```

⇒ **El diseño que pediste ya está en el esquema.** `clase_id` y `created_at`
existen. No hay que migrar nada de clase a estudio: nunca estuvo en la clase.

**Lo que falta es llenarlo.** `ReviewsService.upsertStudyReview()` **ya acepta
`claseId`**, pero quien la llama desde la pantalla del estudio no se lo pasa
⇒ las 2 reseñas que existen tienen `clase_id = null`.

**Y falta mostrarlo.** La tarjeta de reseña dibuja inicial, nombre, estrellas y
comentario. **No muestra ni la fecha ni la clase.**

## 2. ⚠️ El nudo: `UNIQUE (estudio_id, usuario_id)`

Hay un índice único: **una reseña por persona por estudio**. El guardado es un
`upsert` con `onConflict: 'estudio_id,usuario_id'`.

Choca con "en el estudio se acumulan todas": **se acumulan entre personas, pero
cada persona tiene UNA sola**, que edita.

**Consecuencia concreta de tu ejemplo:** si Juanita hace Barre hoy y Yoga el mes
que viene, no puede dejar dos reseñas. La segunda **pisa** la primera y el
contexto pasaría de "Barre" a "Yoga".

**Hay que decidir:**
- **(a) Dejar el único.** Una reseña por persona, editable, y el contexto es
  el de la última clase que la motivó. Simple; el rating no se puede inflar.
- **(b) Sacarlo:** una reseña por persona **por clase asistida**. Más material y
  el contexto siempre es fiel, pero una persona muy frecuente pesa más en el
  promedio y hay que pensar el anti-spam.
- **(c) Intermedio:** único por `(estudio, usuario, clase)`. Una reseña por
  clase distinta, no por cada asistencia.

## 3. La notificación: ya existe a medias, pero distinta

`NotificacionesService.scheduleResenaReminder()` ya está construida y en
producción. Es una **notificación LOCAL** (`flutter_local_notifications`), que
el teléfono programa **en el momento de reservar**.

| | Existe hoy | Lo que pediste |
|---|---|---|
| Cuándo | fin de clase **+ 2 horas** | fin de clase **+ 15 min** |
| A quién | **a todo el que reservó** | sólo a quien **asistió** (check-in) |
| Cómo | **local**, programada en el teléfono | **push** desde el servidor |
| Adónde lleva | `/estudio/:id` | a dejar la reseña |
| Contexto de clase | no lo pasa | "Barre · 27 ago" |
| Web | **no funciona** (`if (kIsWeb) return`) | — |

El ruteo del tap ya existe (`main.dart:228`, por `tipo == 'recordatorio_resena'`).

## 4. 🔴 La pregunta del push — y es el punto que decide todo

**Sí, esta feature depende del push roto… pero SÓLO si la hacemos por push.**

Y el problema es peor de lo que parecía. Medido hoy:

- **Los ÚNICOS tokens de push de toda la base son 3 de `aura.hola.app@gmail.com`**
  (tu propia cuenta, iOS). **Ninguna alumna tiene un dispositivo registrado.**
  Juanita incluida.
- Y esos 3 fallan con `401 THIRD_PARTY_AUTH_ERROR` (problema de la clave de
  APNs en Firebase).

⇒ **Un push desde el servidor hoy no le llega absolutamente a nadie.**

**Por eso la notificación LOCAL que ya existe es la que anda**: se programa en
el teléfono, no pasa por Firebase, y **no depende del bug de APNs**.

### El trade-off, en una línea

**Local (lo que hay):** funciona hoy, sin Firebase — pero el teléfono la
programa al reservar, o sea **antes de la clase**, y por eso **no puede saber
si la persona asistió**. Le llega igual a quien faltó.

**Push (lo que pediste):** el servidor sabe quién tiene `checked_in_at`, así
que puede mandarla **sólo a quien fue** — pero **no llega a nadie hasta
arreglar APNs y hasta que las alumnas registren su token**.

## 5. Cómo se dispararía el push (si se va por ahí)

La cadena ya existe: **insertar una fila en `notificaciones_usuario` dispara el
trigger `trg_notif_push_nueva`**, que llama a la edge function `push-enviar`.
Una sola fila da campanita **y** push.

Falta el disparador temporal: un **cron cada 15 minutos** que busque reservas
con `checked_in_at is not null`, de clases terminadas hace entre 15 y 30
minutos, sin aviso previo. Ya hay un cron `*/15` andando
(`cleanup-lista-espera`), así que la cadencia está probada.

⚠️ **`notificaciones_usuario` NO tiene campo de ruta/deeplink** — sólo `tipo`.
El ruteo se hace por `tipo` en el Dart, así que **un `tipo` nuevo necesita
build**. Si se reusa `'recordatorio_resena'`, que ya está ruteado, **no**.

## 6. Base vs Dart

### 🟢 BASE (sin build)
- Cron cada 15 min + la función que arma los avisos (si se va por push).
- Sacar/cambiar el `UNIQUE` de `study_reviews`, si se decide (b) o (c).
- Una RPC que devuelva las reseñas con el nombre de la clase resuelto.

### 🔵 DART (build)
- Pasar `claseId` al abrir la hoja de reseña (el service **ya lo acepta**).
- Mostrar **fecha y clase** en la tarjeta: *"Juanita · Barre · 27 ago 2026"*.
- Cambiar el offset de la local de **+2 h a +15 min**, si se queda local.
- Que el tap lleve a **dejar la reseña**, no a la pantalla del estudio.
- Un `tipo` nuevo, sólo si no se reusa `'recordatorio_resena'`.
- Reseñas en **web**: hoy la local no corre en web (`kIsWeb`).

## 7. Lo que falta decidir

1. **¿Local o push?** Es la decisión de fondo. Local anda hoy pero no distingue
   quién asistió; push distingue pero no llega a nadie hasta arreglar APNs.
2. **¿Qué pasa con el `UNIQUE`?** (a), (b) o (c) de la sección 2.
3. **¿"15 minutos" desde el fin de la clase o desde el check-in?** El check-in
   ya quedó confiable (se sella en el servidor desde el 27/8).
4. **¿Adónde lleva el tap?** Hoy va a `/estudio/:id`. Para abrir la hoja de
   reseña directo hace falta una ruta o un parámetro.
5. **¿Se le pide reseña a quien faltó?** Hoy la local le llega igual.
