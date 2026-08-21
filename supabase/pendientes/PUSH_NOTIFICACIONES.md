# Proyecto: notificaciones PUSH (FCM + APNs)

Fecha: 2026-08-20. **Estado: PLANIFICADO.** Proyecto grande, con dependencias
externas (Firebase, Apple) que no se resuelven desde el código.

## Por qué

Hoy el proyecto solo tiene `flutter_local_notifications`: notificaciones
**locales**, que solo puede disparar el propio dispositivo. No hay forma de
avisarle a alguien que no tiene la app abierta.

Se nota sobre todo en la **lista de espera**: cuando se libera un cupo, el
promovido tiene **30 minutos** para confirmar y hoy solo se entera si abre la
app. (Peor todavía: `reservas_service.dart:418` dispara la notificación local en
el teléfono de **quien cancela**, no del promovido — ver Tanda 2 de
`LISTA_ESPERA_arreglar_y_asegurar.md`.)

## Estado del proyecto al planificar (verificado)

```
firebase_core / firebase_messaging ..... NO están
google-services.json ................... no existe
GoogleService-Info.plist ............... no existe
Runner.entitlements .................... existe, SOLO con Sign in with Apple
                                         (falta `aps-environment`)
applicationId Android .................. app.somosaura.aura
namespace Android ...................... com.aura.aura_app   ← OJO, ver trampa
Bundle ID iOS .......................... app.somosaura.aura
Apple DEVELOPMENT_TEAM ................. VN5MLA84RD
versión ................................ 1.0.6+24
```

Base que SÍ se reusa: `NotificacionesService` ya tiene `initialize()`,
`_requestPermissions()`, `getLaunchDetails()` y manejo de tap.

## La decisión de arquitectura: un solo punto de disparo

En vez de cablear push en cada lugar que notifica, se cuelga de la tabla que
**ya** concentra todas las notificaciones in-app:

```
cualquier INSERT en notificaciones_usuario
        ↓ trigger + pg_net (mismo patrón que el email al estudio)
   edge function push-enviar
        ↓
      FCM v1  →  Android + iOS
```

⇒ Todo lo que hoy genera campanita se convierte en push **sin tocar ninguna de
esas funciones**: promoción de lista de espera, aviso a profes, avisos del
estudio, y lo que se agregue después.

---

## PASO 1 — Consolas (lo hace la usuaria)

### Firebase Console — https://console.firebase.google.com

1. **Crear proyecto** → nombre `Aura`. Google Analytics: se puede desactivar.
2. **Añadir app Android** (ícono Android):
   - Nombre del paquete: **`app.somosaura.aura`**
   - ⚠️ **NO** `com.aura.aura_app`. Ese es el `namespace`, que quedó distinto a
     propósito. Firebase se registra con el **applicationId**. Si se pone el
     namespace, los push nunca llegan y **el error es mudo**.
   - SHA-1: no hace falta (el login con Google va por Supabase, no por Firebase Auth).
   - Descargar **`google-services.json`**.
3. **Añadir app iOS** (ícono Apple):
   - Bundle ID: **`app.somosaura.aura`**
   - Descargar **`GoogleService-Info.plist`**.

### Apple Developer — https://developer.apple.com/account

4. **Certificates, Identifiers & Profiles → Identifiers → `app.somosaura.aura`**
   - Tildar **Push Notifications**. Guardar.
5. **Keys → + (nueva key)**
   - Nombre: `Aura APNs`. Tildar **Apple Push Notifications service (APNs)**.
   - Continue → Register → **Download**.
   - ⚠️ El `.p8` **se descarga UNA SOLA VEZ**. Si se pierde, hay que revocar y
     crear otra.
   - Anotar el **Key ID** (10 caracteres). El **Team ID** es `VN5MLA84RD`.

### Volver a Firebase

6. **Project settings → Cloud Messaging → Apple app configuration**
   - **APNs Authentication Key** → Upload: el `.p8` + Key ID + Team ID.
7. **Project settings → Service accounts → Generate new private key** → JSON.
   Ese es el que usa la edge function para enviar.

### Qué va al repo y qué NO

| Archivo | ¿Al repo? |
|---|---|
| `google-services.json` | **SÍ** (config de cliente, es lo estándar) |
| `GoogleService-Info.plist` | **SÍ** |
| **`.p8` de APNs** | ❌ **NUNCA.** Vive en Firebase y en un backup de la usuaria |
| **Service account JSON** | ❌ **NUNCA.** Va como **secret de Supabase** |

---

## PASO 2 — Base de datos (no depende de Firebase)

### Tabla `dispositivos`

```sql
create table public.dispositivos (
  id          bigserial primary key,
  usuario_id  uuid not null references auth.users(id) on delete cascade,
  token       text not null unique,
  plataforma  text not null check (plataforma in ('android','ios','web')),
  app_version text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index dispositivos_usuario_idx on public.dispositivos(usuario_id);
```

`token` es **unique** a propósito: FCM devuelve el mismo token para el mismo
dispositivo, así que si otra persona se loguea ahí, el token tiene que **cambiar
de dueño**, no duplicarse (si no, le llegan los push de la cuenta anterior).

### El registro va por RPC, no por INSERT directo

**Hallazgo al planificar**: si el cliente hiciera `upsert` directo, la policy de
UPDATE (`usuario_id = auth.uid()`) **bloquearía el traspaso** — la fila todavía
es del usuario anterior. Se rompería justo el caso de logout/login en el mismo
celu.

⇒ El registro va por dos RPC `SECURITY DEFINER`, y la tabla queda **solo de
lectura** para el cliente:

- `registrar_dispositivo(p_token, p_plataforma, p_app_version)` — upsert con
  `usuario_id = auth.uid()`; en conflicto de token, **reasigna el dueño**.
- `borrar_dispositivo(p_token)` — para el logout.

### RLS

- SELECT: solo las propias (`usuario_id = auth.uid()`).
- Sin INSERT/UPDATE/DELETE directos desde el cliente: se fuerza el RPC.
- `anon`: `revoke all`, ni tabla ni RPC.

### Trigger

`AFTER INSERT ON notificaciones_usuario` → `pg_net` → edge `push-enviar`, con:

- `exception when others then return NEW` — **un fallo de push nunca puede
  romper una reserva** (mismo patrón que `notif_email_nueva_reserva`).
- **Inerte hasta el paso 3**: si el secreto `push_trigger_secret` no está en
  Vault todavía, sale sin hacer nada. Así se puede crear el trigger ahora sin
  que dispare llamadas a una edge que no existe.

---

## PASO 3 — Edge function `push-enviar`

Recibe `{notificacion_id}`, valida el secreto del trigger, y:

1. Lee la notificación y su `usuario_id`
2. Busca los tokens en `dispositivos`
3. Firma un JWT con la service account → token OAuth2 de Google
   (la API vieja de "server key" está **discontinuada**; hay que usar **FCM v1**)
4. `POST` a FCM v1 por cada token
5. **Limpia tokens muertos**: si FCM responde `UNREGISTERED` / `INVALID_ARGUMENT`,
   borra esa fila (si no, la tabla se llena de basura)

---

## PASO 4 — App Flutter

Dependencias: `firebase_core`, `firebase_messaging`. Config: los dos archivos de
Firebase + entitlement `aps-environment` + plugin de Gradle.

Se extiende `NotificacionesService`:

| Ya existe | Se agrega |
|---|---|
| `initialize()`, `_requestPermissions()` | init de Firebase + permiso de push (iOS explícito, Android 13+ también) |
| `getLaunchDetails()`, tap handler | `onMessage`, `onMessageOpenedApp`, `onBackgroundMessage` |
| `showImmediate()` | guardar token al loguear + `onTokenRefresh`; **borrarlo al cerrar sesión** |

**Y se arregla el `showImmediate` mal dirigido** de `reservas_service.dart:418`
(Tanda 2 de lista de espera): con push, la promoción le llega a quien
corresponde y esa línea se borra.

---

## Qué se puede probar sin celular, y qué no

**Sin dispositivo (~70%)**: tabla, RLS, RPCs, trigger, secretos, la edge
completa **incluida la autenticación contra FCM** (se prueba con un token
inventado: si FCM responde `NOT_FOUND` en vez de `401`, la firma OAuth2 está
bien — eso valida la parte difícil), todo el Dart, `analyze` y `build web`.

**Sí o sí en celular físico**: obtener un token FCM real, que el push llegue con
la app cerrada, que el tap abra la pantalla correcta, y el diálogo de permiso de
iOS.
⚠️ El **simulador de iOS NO recibe push nunca**. Hace falta un iPhone real. El
emulador de Android sí sirve, si tiene Google Play services.

## Orden

| Paso | Quién | ¿Celular? |
|---|---|---|
| 1. Firebase + APNs + capability | **usuaria** | no |
| 2. Base: tabla, RLS, RPCs, trigger, secretos | asistente | no |
| 3. Edge `push-enviar` + validar auth FCM | asistente | no |
| 4. Dart | asistente | no |
| 5. `analyze` + build web | asistente | no |
| 6. **Build Android → primer push real** | los dos | **sí** |
| 7. Build iOS (TestFlight) | los dos | **sí** |
| 8. Release a tiendas | usuaria | — |

---

# 🖥️ PARA LA MAC — lo que hay que hacer ANTES de buildear

**Los archivos de Firebase NO están en el repo** (`.gitignore` líneas 67-68, desde
julio) porque **el repo es público** y `google-services.json` trae la API key.
Viven solo en la máquina de la usuaria. Al clonar/pullear en la Mac hay que
copiarlos a mano desde el backup:

```
google-services.json      →  android/app/
GoogleService-Info.plist  →  ios/Runner/
```

### ⚠️ El .plist NO alcanza con copiarlo

Hay que **agregarlo al proyecto DESDE XCODE**, de modo que quede en
**Build Phases → Copy Bundle Resources**. Si solo se copia a la carpeta:

- compila igual, sin ningún error,
- pero Firebase no lo encuentra en runtime,
- y **el push nunca llega, sin mensaje claro que lo explique**.

Es la falla silenciosa más típica de este setup.

### ⚠️ Verificar `aps-environment` al archivar

`ios/Runner/Runner.entitlements` quedó con:

```xml
<key>aps-environment</key>
<string>development</string>
```

Sirve para builds locales. **Para TestFlight / App Store puede necesitar
`production`.** No se pudo confirmar desde Windows: **verificarlo en Xcode al
hacer el Archive**. Si queda mal, APNs entrega al servidor equivocado (sandbox
vs producción) y el push no llega.

### Recordatorio del entorno

- iOS deployment target **15.0** y Android minSdk **24**: ambos ya por encima de
  lo que pide Firebase (13.0 / 23). **No hay que subir nada.**
- El **simulador de iOS NO recibe push nunca**. Hace falta un iPhone físico.
- El emulador de Android sí sirve, si tiene Google Play services.

---

## 🔴 BLOQUEANTE DEL BUILD: la Tanda 2 de lista de espera

**Decidido: NO se buildea para las tiendas hasta cerrarla.** Si saliera un build
hoy, se llevaría:

| | |
|---|---|
| ✅ Backoffice de precios arreglado | se destraba lo que reportó Sofia |
| ✅ Push funcionando | |
| ❌ **Sección "En espera" rota** | los 6 usos de `posicion` dan **HTTP 400** |
| ❌ **Contador de lista de espera en 0** | `getCount()` cuenta filas y esa policy se cerró |

Detalle en `LISTA_ESPERA_arreglar_y_asegurar.md` (Tanda 2). Del lado base ya está
todo listo: `waitlist_mis_posiciones()` y `waitlist_count()` existen y funcionan.

## ⚠️ Este build lleva más que push

No sacar dos releases seguidos. En el mismo build tienen que entrar:

- **Push** (este proyecto)
- **Tanda 2 de lista de espera**: los 6 usos de `posicion` + `getCount` →
  `waitlist_mis_posiciones()` / `waitlist_count()`. Ver
  `LISTA_ESPERA_arreglar_y_asegurar.md`
- **El `showImmediate` mal dirigido** (`reservas_service.dart:418`)
- Con eso se destraba además el **backoffice de precios en la app instalada**,
  que hoy da HTTP 400 porque el build viejo pide columnas que se movieron a
  `estudios_datos_cobro`.
