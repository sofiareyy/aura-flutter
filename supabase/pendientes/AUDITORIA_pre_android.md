# Auditoría pre-lanzamiento de Android

Fecha: 2026-08-19. Estado del repo auditado: `adeafac` + build `1.0.6+24`.

Método: cruce automático del código de `lib/` contra el esquema real de la base
(31 tablas, 284 columnas, 98 funciones, 35 FKs). 183 queries y 65 llamadas RPC
analizadas con scripts, no a ojo.

**Decisiones tomadas (2026-08-19, irreversibles):**

- `applicationId` de Android → **`app.somosaura.aura`** (igual que el bundle de iOS).
- Se activa **Play App Signing** al subir.

---

## 🔴 Bloqueantes para publicar en Play

### 1. Release firmado con la clave de debug

`android/app/build.gradle.kts`, con el TODO del template todavía puesto:

```kotlin
buildTypes {
    release {
        // TODO: Add your own signing config for the release build.
        signingConfig = signingConfigs.getByName("debug")
    }
}
```

No existía `android/key.properties` ni keystore. Play rechaza cualquier AAB
firmado con la debug key. Bloquea también el punto 3.

> ⚠️ El keystore hay que respaldarlo igual que el `.p12` del certificado de
> iOS. Si se pierde, no se puede volver a actualizar la app (salvo con Play
> App Signing activado).

### 2. `applicationId` del template

Era `com.aura.aura_app` mientras iOS usa `app.somosaura.aura`. Es permanente
una vez publicado: cambiarlo después es una app nueva, sin reseñas ni usuarios.
Al cambiarlo hay que actualizar los `assetlinks.json`, que lo declaran.

---

## 🟠 Antes de lanzar — afectan a usuarios

### 3. `assetlinks.json` con un placeholder sin reemplazar

Los dos dominios servían literalmente:

```json
"sha256_cert_fingerprints": ["REEMPLAZAR_CON_SHA256_DEL_KEYSTORE"]
```

Con eso la verificación de App Links falla siempre y `android:autoVerify="true"`
no sirve. Depende del punto 1 (el SHA sale del keystore).

**Impacto acotado:** los flujos críticos usan el scheme propio `aura://`
(`payment-result`, `login-callback`, `reset-password`), que no requiere
verificación. Lo que no anda es abrir la app desde un link `https://`.

### 4. App Link al dominio viejo

`AndroidManifest.xml` declaraba `android:host="somosauraar.netlify.app"`. El
sitio real es **somosaurapass.com** (GitHub Pages). Los dos responden 200 y
sirven `assetlinks.json`, así que el de Netlify sigue vivo por inercia.

En iOS esto no existe: `Runner.entitlements` no tiene `associated-domains`, o
sea que iOS no tiene Universal Links, solo los schemes `aura` y
`app.somosaura.aura`. Asimetría a resolver a propósito.

### 5. Apple Sign-In en Android: código correcto, config por verificar

El gateo por plataforma está bien:

```dart
if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
  await _authService.signInWithAppleNative();   // nativo
} else {
  ...signInWithOAuth(OAuthProvider.apple)       // flujo web -> Android
}
```

El camino web necesita un **Service ID** de Apple y la redirect URL cargada en
Supabase. Si se armó solo para iOS nativo, el botón de Apple falla en Android.
No se puede verificar desde el código.

### 6. Packs hardcodeados: bloquean subir precios

`getPacks()` (`pricing_service.dart`) **calcula** el precio desde `_packsBase`
en vez de leer `pricing_credit_packs`. `getPlanes()` sí lee la tabla.

Hoy coincide de casualidad, porque `valor_credito_ars` está en 1000:

| pack | app calcula | tabla | |
|---|---|---|---|
| Prueba (20 × 1,10) | 22.000 | 22.000 | coincide |
| Esencial (50 × 1,05) | 52.500 | 52.500 | coincide |
| Popular (100 × 1,00) | 100.000 | 100.000 | coincide |
| Full (200 × 0,95) | 190.000 | 190.000 | coincide |

Con `valor_credito_ars = 1200` el servidor rechaza **las cuatro** compras
(`crear-checkout-pack/index.ts:67` → `precio_desactualizado`, *"Los precios
cambiaron. Actualizá la app"*). Ningún build lo arregla: el precio calculado se
mueve igual.

---

## 🟡 Deuda — no bloquea

### 7. El toggle de bienvenida tira excepción

De 65 llamadas RPC, solo 4 apuntan a funciones inexistentes y las cuatro son de
bienvenida (migración pendiente a propósito). Dos están protegidas:

- `acreditar_bienvenida` (`main.dart:147`) ✅ try/catch
- `bienvenida_esta_activa` (`home_screen.dart:98`) ✅ try/catch

Las otras dos **no**: `admin_service.dart:410` (`admin_encender_bienvenida`) y
`:419` (`admin_apagar_bienvenida`). El switch de Admin → Config revienta si
alguien lo toca.

### 8. `lista_espera.posicion` no existe

En `reservas_service.dart` y `mis_reservas_screen.dart`. Decisión tomada:
calcular el puesto por `created_at`.

### 9. Catch silenciosos: 76 en 24 archivos

54 vacíos (`catch (_) {}`) y 22 que devuelven `null`/`[]`/`false`. Concentrados
en `mis_clases_screen.dart` (13), `estudio_admin_service.dart` (12),
`main.dart` (10), `asistencia_screen.dart` (7).

Muchos son fire-and-forget legítimos. Pero **es la razón estructural por la que
los bugs de agosto fueron invisibles durante un mes**: el de `home_screen`
tragaba un 42703 y asumía "tiene historial". Priorizar los que envuelven una
escritura o una decisión de negocio, no los de UI.

---

## ✅ Lo que salió limpio

- **Filtros de postgrest descartados: cero.** Los 5 sitios que guardan un
  builder en variable reasignan bien (`asistencia_screen.dart:464`,
  `estudio_admin_service.dart:284` y `:307`, `estudios_service.dart:45`,
  `reviews_service.dart:49`). Los dos rotos de agosto eran los únicos.
- **Embeds y FKs: los 9 resuelven.** Dato no advertido antes: la FK
  `clases → estudios` no solo destrabó las reservas — también estaban rotas las
  queries de explorar/recomendados (`clases_service.dart:122` y `:151`, esta
  última con `estudios!inner`), caídas desde el 2026-07-20.
- **RPCs: 62 distintas, 65 llamadas, todos los nombres de parámetro coinciden**
  con las firmas reales. Cero desajustes.
- **Columnas: 183 queries, un solo problema real** (`lista_espera.posicion`).
- **Multiplataforma bien resuelto:** notificaciones locales con settings por
  plataforma y permisos branchados; cámara y ubicación declaradas; el pago abre
  MercadoPago con `LaunchMode.externalApplication` y vuelve por
  `aura://payment-result` **con polling de respaldo**, así que aunque falle el
  deep link la compra se acredita igual.

---

## Orden de resolución

| | Qué | Por qué ahí |
|---|---|---|
| **1** | Keystore de release + `signingConfig` | Sin esto no hay AAB válido. Bloquea el 3 |
| **2** | `applicationId` → `app.somosaura.aura` | Irreversible una vez publicado |
| **3** | `assetlinks.json` con el SHA real, en somosaurapass.com | Depende del 1 y del 2 |
| **4** | Verificar Apple Sign-In en Android | Config externa, puede tardar |
| **5** | Packs desde la tabla | Cliente; entra en el build de Android |
| **6** | `try/catch` en el toggle de bienvenida | Dos líneas |
| **7** | Lista de espera por `created_at` | Cliente + RPC |
| **8** | Catch silenciosos que envuelven escrituras | Deuda continua |

Los puntos 5, 6 y 7 son de Dart: van juntos al build de Android y al próximo de
iOS, sin gastar dos revisiones.

---

# ESTADO AL 2026-08-19 — dónde retomar

## ✅ Hecho y pusheado (Grupo A, config de Android)

| | Qué | Dónde |
|---|---|---|
| A1 | Keystore de release + `signingConfig` | `android/app/build.gradle.kts` |
| A2 | `applicationId` → `app.somosaura.aura` | `android/app/build.gradle.kts` |
| A3 | App Links a `somosaurapass.com` + `assetlinks.json` con el SHA real de subida | `AndroidManifest.xml`, `web/.well-known/` |
| A4 | Diagnóstico del login de Apple en Android (sin cambios de código) | ver abajo |

### ⚠️ Para compilar desde OTRA computadora — leer esto primero

El keystore y sus credenciales **no están en el repo** (a propósito). Un
`git pull` solo **no alcanza** para generar un AAB firmado. En la máquina nueva
hay que:

1. Copiar el keystore `aura-upload.jks` desde el backup.
2. Crear `android/key.properties` (está en `.gitignore`, no viene del pull) con:

```properties
storePassword=<la del gestor de contraseñas>
keyPassword=<la misma>
keyAlias=aura-upload
storeFile=<RUTA ABSOLUTA al .jks EN ESA MAQUINA>
```

   👉 `storeFile` es una **ruta absoluta**: en la máquina original es
   `/Users/reyfer/keys/aura-upload.jks`. Si el usuario o la carpeta cambian,
   hay que ajustarla o Gradle no encuentra el keystore.

3. Verificar antes de compilar:

```bash
cd android && ./gradlew :app:signingReport | grep -A5 "Variant: release"
# tiene que mostrar Store: <tu ruta>/aura-upload.jks y Alias: aura-upload
```

Si falta `key.properties`, el release sale **sin firmar** a propósito (no cae a
la clave de debug). Falla al subir a Play, que es lo que se quiere: nunca un
AAB mal firmado que parezca bueno.

## 🔜 Grupo B — 4 fixes de Dart (pendiente)

Van todos juntos: entran en el build de Android **y** en el próximo de iOS.

| # | Fix | Archivo | Por qué |
|---|-----|---------|---------|
| **B1** | `getPacks()` que lea `pricing_credit_packs` en vez de calcular desde `_packsBase` | `services/pricing_service.dart` | **El importante.** Hoy el precio se calcula (`créditos × valor_credito_ars × multiplicador`) y coincide con la tabla solo porque `valor_credito_ars` está en 1000. Al subirlo por inflación, `crear-checkout-pack` rechaza **las cuatro** compras con "Los precios cambiaron". Que `getPlanes()` ya lee la tabla sirve de modelo |
| **B2** | `try/catch` en el toggle de bienvenida | `services/admin_service.dart:410` y `:419` | Los RPC `admin_encender_bienvenida` / `admin_apagar_bienvenida` no existen (migración pendiente a propósito). Hoy el switch de Admin → Config revienta si alguien lo toca |
| **B3** | Lista de espera: calcular el puesto por `created_at` | `services/reservas_service.dart`, `screens/reservas/mis_reservas_screen.dart` | `lista_espera.posicion` no existe → 400. **Decidido: NO se agrega la columna.** Derivar con `row_number() over (partition by clase_id order by created_at)` vía vista/RPC, o en Dart sobre la lista ya ordenada |
| **B4** | `LaunchMode.inAppWebView` → `inAppBrowserView` en los 4 sitios de OAuth | `screens/auth/login_screen.dart` (Google ~165, Apple ~215), `screens/auth/register_screen.dart` (~57, ~105) | Un WebView embebido puede ser rechazado por Google (`disallowed_useragent`) y por Apple. `inAppBrowserView` usa Custom Tabs en Android y `SFSafariViewController` en iOS. **No está confirmado como roto** —una prueba con user-agent de WebView no reprodujo el bloqueo— pero es curarse en salud antes de lanzar Android |

## 🔜 A4 — Login de Apple en Android (acciones fuera del código)

Lo verificado y funcionando: Apple habilitado en Supabase, `client_id` con
Service ID **y** Bundle ID (`app.somosaura.aura.signin,app.somosaura.aura`),
`aura://login-callback` en la allow-list, `site_url` correcto. El authorize
redirige bien a Apple con el Service ID y el callback de Supabase.

**Falta hacer en Apple Developer:**

1. Confirmar que el Service ID `app.somosaura.aura.signin` tenga:
   - Primary App ID `app.somosaura.aura`
   - Domains: `hvgqpzvornlnxmsbqnwg.supabase.co`
   - Return URL **exacto**: `https://hvgqpzvornlnxmsbqnwg.supabase.co/auth/v1/callback`
     (una barra de más → `invalid_client`)
2. **Regenerar el client secret** sin averiguar si venció. Es un JWT con tope de
   6 meses de Apple. **El flujo nativo de iOS NO lo usa**, así que puede estar
   vencido hace meses sin que nadie lo note — y rompe justo el día que se lanza
   Android. Se pega en Supabase → Auth → Providers → Apple → *Secret Key (for
   OAuth)*. **No tocar los Client IDs.**

   ⏰ **RECORDATORIO: reponerlo antes de ~2027-01-19** (5 meses desde hoy). Se
   rompe solo, en silencio, sin que nadie cambie nada.

3. Probar en un Android real: si Apple muestra `invalid_client` → Return URL o
   Service ID mal. Si autoriza pero la app queda colgada → secreto vencido.

## 🔜 assetlinks.json — falta el SHA de Google

`web/.well-known/assetlinks.json` declara hoy **solo** la huella de la clave de
subida. Con Play App Signing, los APKs que instala la gente los firma **Google**
con otra clave, así que los App Links **no verifican** hasta agregar esa huella.

Después de la primera subida: Play Console → **Test and release** → **App
integrity** → **App signing key certificate** → copiar el SHA-256 y agregarlo al
array **sin borrar el de subida**. Detalle y comandos de verificación en
`web/.well-known/LEEME.md`.

No es una regresión: antes el archivo tenía un placeholder y nunca verificó. Y
el impacto está acotado — los flujos críticos usan el scheme `aura://`, que no
necesita verificación.

## 🚫 Fuera de alcance de este build (decisión del 2026-08-19)

No meter acá, van a builds futuros con foco propio:

- Barra de progreso
- Premio de 50 clases
- Features de suscripción
