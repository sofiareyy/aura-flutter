# Pendiente: email al estudio en cada reserva

Fecha del plan: 2026-08-19. Estado: **diseñado y aprobado, sin construir.**
Retomar en una **sesión dedicada** (la parte de valor —confirmar entrega real + SPF/DKIM en Resend— necesita atención, no hacerlo al final de una sesión larga).

Contexto: hoy el aviso al estudio en una reserva es solo in-app (campanita, ya arreglada) + aviso a profes. **No hay push ni email.** Este plan agrega el email, que es el que hace que el estudio se entere en el momento sin depender de que abra la app. Ver también el diagnóstico de las 3 piezas (campanita/push/email) de esta misma fecha.

## Decisiones de producto (confirmadas)

- **Destinatarios: SOLO los admins del estudio (`rol='admin_estudio'`), NO las profes.** Las profes ya tienen su aviso in-app propio (`notify_profes_nueva_reserva`); no las spameamos por mail.
- **Incluir el nombre del alumno** en el mail. ✅

## 1. Edge function `nueva-reserva-estudio-email`

Corre con `service_role` (la llama el trigger, no un usuario) — mismo esquema fail-closed que `aviso-cobro-manana`/`regenerar-grillas`. Copia el patrón de `aviso-alumnos-email/index.ts`.

Resolución de destinatarios (server-side, bypassa RLS):
```
reserva → clase_id
clase   → estudio_id, nombre, fecha, instructor
estudio → nombre, notif_email_reservas (opt-out)
destinatarios: estudio_admins (rol='admin_estudio') → auth.users.email
               (excluyendo los que optaron por apagarlo)
reservante: usuarios.nombre
```
`estudios` no tiene columna de email → el mail sale de los admins vía `estudio_admins → auth.users.email`. Remitente: `Aura <hola@somosaurapass.com>` (env `AURA_FROM_EMAIL`, ya usado). `RESEND_API_KEY` ya configurada.

**La function debe tener un parámetro `test_email` opcional:** si viene, manda a esa casilla en vez de a los admins reales (para probar sin spamear estudios).

### Borrador del mail
```
Asunto:  Nueva reserva en [Estudio] 🧡

Hola [Estudio],

Tenés una nueva reserva:

  🧘 Clase:   [nombre de la clase]
  📅 Día:     [Lunes 22/09]
  🕕 Hora:    [18:00]
  👤 Alumno:  [nombre del reservante]

Podés ver la lista completa de asistentes en la app.

— Aura
```
(El instructor se puede agregar si se decide más adelante.)

## 2. Disparador: trigger + `pg_net`

Trigger en `reservas` que dispara cuando una reserva **pasa a `confirmada`**:
- `AFTER INSERT` con `NEW.estado = 'confirmada'`, y
- `AFTER UPDATE` con `NEW.estado = 'confirmada' AND OLD.estado <> 'confirmada'` (cubre la confirmación desde lista de espera).
- NO dispara con `pre_confirmada`, `cancelada`, etc.

El trigger llama `net.http_post(...)` (extensión `pg_net`, **hay que habilitarla**) a la URL de la function, con el `reserva_id` + un secreto de auth. `pg_net` hace el POST **asincrónico** → no bloquea ni demora la reserva; si Resend falla, la reserva ya quedó hecha.

**Por qué el trigger y no dispararlo desde la app:** corre en la base sobre el dato real, sin depender del celular del usuario (el actual `_notifyStudio` es client-side, fire-and-forget con catch silencioso — por eso a Citra no le llegó). Y atrapa TODOS los caminos (reserva directa, lista de espera, reserva manual del admin), porque todos escriben en `reservas`.

Cuidado: en clases muy demandadas puede haber muchos mails seguidos. Empezamos con uno por reserva (inmediato, que es lo que se quiere); si molesta, evaluar throttle/digest más adelante.

## 3. Opt-out

Columna `estudios.notif_email_reservas boolean not null default true`. La function no manda si está en `false`. Prender/apagar por SQL al inicio; un toggle en Admin → Config es un agregado chico de UI si se quiere después.

## 4. Acceso + trabajo

| Pieza | Necesita | Trabajo |
|---|---|---|
| Edge function | `supabase functions deploy` (token de la CLI, ya logueada) | ~medio día |
| Trigger + `pg_net` + columna opt-out | Token de DB (Management API) | ~medio día |
| Secreto trigger→function | `supabase secrets set` o dashboard | 10 min |
| **Total** | token de DB + deploy | **~1 día** |

No requiere build nativo ni tocar la app (todo server-side).

## 5. Cómo probar que el mail llega de verdad (criterio de "hecho")

1. **Modo test:** function con parámetro `test_email` → manda a mi casilla, sin spamear estudios.
2. **Prueba aislada (nivel function):** `curl` directo a la function con un `clase_id` real + `test_email` = mi mail → **tiene que llegar** con los datos correctos.
3. **Resend dashboard:** confirmar estado **delivered** (no solo *sent*) → atrapa problemas de dominio/SPF/DKIM.
4. **Prueba end-to-end:** reserva de prueba real en un estudio de test (admin = mi mail) → trigger → pg_net → function → **el mail llega**.
5. **Recién ahí prender para estudios reales** (opt-out en `true` por default).

**"Hecho" = yo confirmo que recibí el mail (pasos 2 y 4) Y Resend muestra *delivered*.** Si no llega, no está hecho.

## Orden de ejecución (para retomar tal cual)

1. Escribir la edge function **con modo test** (`test_email`).
2. **Deploy** de la function.
3. **Prueba aislada** a mi mail (curl con `test_email`) + verificar *delivered* en Resend.
4. Crear el **trigger + habilitar `pg_net`** + columna opt-out.
5. **Prueba real** end-to-end (reserva de prueba en estudio de test).
6. **Prender para estudios reales.**
