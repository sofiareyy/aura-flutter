# Verificación de mail + login de Apple — para retomar

Fecha: 2026-08-21. **Escrito para retomar en un chat nuevo sin re-investigar.**
Todo lo de acá está VERIFICADO contra la base y el código, no supuesto.

> ## Estado al 2026-08-21 (fin de sesión)
>
> | Paso | Estado |
> |---|---|
> | 1. Centrar el punto del logo (4 plantillas) | ✅ **HECHO y visto en Gmail** |
> | 2. `mailer_otp_exp` 3600 → 86400 (24h) | ✅ **HECHO y verificado** |
> | 3. Mensaje `email_not_confirmed` en el login | ✅ **YA ESTABA** — ver corrección abajo |
> | 4. Activar `mailer_autoconfirm = false` | ⏳ **MAÑANA, post-aprobación de Apple** |
> | 5. Personalizar plantilla `email_change` | ⏳ opcional, sin tocar |
>
> **Config en vivo ahora**: `mailer_autoconfirm=true` (verificación APAGADA a
> propósito), `mailer_otp_exp=86400`, las 4 plantillas con el punto centrado.

---

## 1. Verificación de mail — estado

### Config actual (Management API, `/config/auth`)

```
mailer_autoconfirm ....... true        ← la verificación está APAGADA
mailer_otp_exp ........... 3600        ← 1 hora (corto, ver pendiente)
smtp_host ................ configurado (propio)
smtp_admin_email ......... hola@somosaurapass.com
smtp_sender_name ......... Aura
site_url ................. https://somosaurapass.com
```

### ✅ Lo ya probado y OK

- **El mail LLEGA y a bandeja principal, no spam.** Probado con el mail de
  recuperación (mismo diseño que el de confirmación) desde
  somosaurapass.com → login → "¿Olvidaste tu contraseña?".
- **El link apunta bien.** Verificado con `admin/generate_link` (no crea
  usuarios ni manda mails):
  ```
  host ......... hvgqpzvornlnxmsbqnwg.supabase.co
  path ......... /auth/v1/verify
  type ......... recovery
  redirect_to .. https://somosaurapass.com      ← correcto
  ```
  `uri_allow_list` incluye `https://somosaurapass.com` y `/**`. El link de
  confirmación usa el MISMO mecanismo (solo cambia `type=signup`).
- **Las plantillas ya están personalizadas** con Aura, en español:
  ```
  confirmation  "Confirmá tu cuenta en Aura"      personalizada
  recovery      "Cambiá tu contraseña de Aura"    personalizada
  magic_link    "Entrá a tu cuenta de Aura"       personalizada
  invite        "Te invitaron a unirte a Aura"    personalizada
  email_change  "Confirm Email Change"            ⚠️ GENÉRICA, en inglés
  ```

### ✅ El punto del logo — CENTRADO Y VERIFICADO (2026-08-21)

**El logo es el CORRECTO** (cuadrado naranja `#e8763a`, anillo negro, punto
negro). **NO hay que cambiarlo.** No tocar el ícono de la app tampoco.

**Único problema**: el punto negro del centro se corre **en Gmail**.

**Causa**: el punto se centra con
`position:absolute; top:50%; left:50%; transform:translate(-50%,-50%)`.
**Gmail elimina el `transform` pero respeta el `top/left:50%`** ⇒ el punto queda
con su esquina superior izquierda en el centro del anillo, corrido hacia abajo
y a la derecha.

**El arreglo** (centrado estático, sin `transform`, en las **4** plantillas —
las cuatro comparten el mismo bloque):

```html
<!-- ANTES -->
<div style="width:28px;height:28px;border:3px solid #0d0d0d;border-radius:999px;position:relative;">
  <div style="width:10px;height:10px;background:#0d0d0d;border-radius:999px;
              position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);"></div>
</div>

<!-- DESPUÉS (lo que se aplicó) -->
<div style="width:28px;height:28px;border:3px solid #0d0d0d;border-radius:999px;">
  <div style="width:10px;height:10px;background:#0d0d0d;border-radius:999px;
              margin:9px 0 0 9px;"></div>
</div>
```

### ⚠️ CORRECCIÓN: son 9px, NO 6px (este doc estaba mal)

La versión original de este doc decía `margin:6px auto 0`, con la cuenta
"anillo de 28px con borde de 3px ⇒ 22px por dentro". **Esa cuenta asume
`box-sizing:border-box`, que la plantilla NO declara** (se verificó: no aparece
`box-sizing` en ninguna de las 5). Sin esa declaración vale el default
`content-box` ⇒ el interior del anillo son **28px**, no 22:

```
(28 − 10) / 2 = 9
```

**Segunda confirmación, independiente**: lo que hace hoy el `transform` es
`top:50%` = 14px menos `translateY(-50%)` = −5px ⇒ el punto arranca a **9px**.
O sea, 9px reproduce exactamente lo que ya se veía bien en Apple Mail. Con 6px
el punto habría quedado 3px **alto** — corrido para el otro lado.

**Sin `auto`**: los dos márgenes van explícitos (`9px 0 0 9px`) para que el
cliente de mail no tenga que calcular nada. `margin` lo respetan Gmail /
Outlook / Apple Mail sin excepción.

**Aplicado y verificado el 2026-08-21**: PATCH a las 4 plantillas → HTTP 200 →
re-lectura del `GET` y comparación **byte a byte** contra lo enviado: idénticas.
`transform` y `position` restantes: **0 y 0** en las 4. Campos modificados en
toda la config: exactamente los 4 de las plantillas, nada más. `email_change`
intacta. **Sofi lo confirmó visualmente en Gmail: el punto quedó centrado.**

**No se toca nada más**: ni el naranja, ni el anillo, ni el tamaño, ni el
wordmark `AURA.`. Un solo atributo `style`.

Se aplica con la Management API: `PATCH /v1/projects/{ref}/config/auth` con
`mailer_templates_{confirmation,recovery,magic_link,invite}_content`.

### 📋 Pasos — estado real

1. ✅ **Centrar el punto** en las 4 plantillas. HECHO 2026-08-21 (con 9px, ver
   corrección arriba). Confirmado a ojo en Gmail.
2. ✅ **Subir `mailer_otp_exp`** de `3600` (1h) a `86400` (24h). HECHO
   2026-08-21. `GET` de verificación: `86400`, y fue el **único** campo que
   cambió en toda la config. Aplica a links emitidos de ahí en adelante; los ya
   emitidos conservan la ventana con la que nacieron.
3. ✅ **Mensaje en el login para `email_not_confirmed`** — **YA ESTABA HECHO**,
   este doc lo daba por pendiente por error. Existe
   `_mostrarDialogoSinConfirmar()` en `login_screen.dart:300`, con explicación
   ("puede figurar como remitente Supabase y estar en spam") y **botón de
   reenviar** que llama a `auth_service.dart:46` (`resend`, `OtpType.signup`).
   Se dispara en el `catch` del login (`login_screen.dart:283`) cuando el error
   contiene `email not confirmed`. Commiteado el 2026-08-19 (`3efb5d9`) y
   **presente en el build web desplegado** (verificado buscando el texto dentro
   de `build/web/main.dart.js`).
   ⚠️ **Pero**: que esté en `main.dart.js` prueba que está en **web**. La app de
   las tiendas (iOS/Android) corre el build que se haya publicado — es
   justamente lo que motiva el paso 4.
4. ⏳ **Activar `mailer_autoconfirm = false`** → **QUEDA PARA MAÑANA**, ver abajo.
5. ⏳ Opcional: personalizar la plantilla `email_change`, la única genérica.

### ⏳ Paso 4 — DECIDIDO: se activa mañana, DESPUÉS de que Apple apruebe el build

**Decisión de Sofi (2026-08-21): hoy NO se activa. `mailer_autoconfirm` queda
en `true`.** Todo lo demás (web/base) quedó listo hoy; mañana solo va el build
desde la Mac.

**El motivo**: activar la verificación hace que el login por email/contraseña
falle con `email_not_confirmed` hasta que la persona confirme. El mensaje
amable que explica eso ("revisá tu mail" + reenviar) vive **dentro de la app**.
La web ya lo tiene, pero **la app publicada en las tiendas corre el build viejo**
— y no sabemos cuál es. Si activáramos hoy, quien se registre desde la app de la
tienda vería un **error crudo**, sin explicación ni botón de reenviar, durante
toda la ventana hasta que Apple apruebe (que puede ser un día o varios).

**El orden correcto, entonces**:

1. Buildear y subir desde la Mac (ver `PUSH_NOTIFICACIONES.md` → "PARA LA MAC").
2. **Esperar la aprobación de Apple.**
3. Recién ahí: `PATCH {"mailer_autoconfirm": false}`.

**Checklist para retomar mañana, en el momento de activar:**

- [ ] El build nuevo está **aprobado y disponible** en la App Store (no solo
      "subido" ni en revisión).
- [ ] **Re-medir** que sigan 100% de los usuarios con `email_confirmed_at`. El
      74/74 es del 2026-08-20; con el autoconfirm prendido cualquier registro
      nuevo también nace confirmado, así que debería seguir dando 100%, pero se
      mide igual antes de tocar.
- [ ] `PATCH /v1/projects/hvgqpzvornlnxmsbqnwg/config/auth`
      con `{"mailer_autoconfirm": false}`.
- [ ] `GET` de verificación: que quede en `false` y que sea el **único** campo
      que cambió.
- [ ] **Probar con una cuenta descartable**: registrarse → que exija validación
      → que llegue el mail → que el link entre bien → que el diálogo de
      "Validá tu cuenta" con el botón de reenviar aparezca en la app.
- [ ] Reversión si algo sale mal: `PATCH {"mailer_autoconfirm": true}`, es
      inmediato y no requiere nada del lado de la app.

**Recordatorio de por qué activar es seguro** (ver la sección de abajo): solo
afecta a **registros nuevos**, los 74 existentes ya tienen `email_confirmed_at`,
y el 61% entra por OAuth, que ya trae el mail verificado.

### ✅ Activar NO rompe a los usuarios actuales — medido

```
usuarios totales ........... 74
con email_confirmed_at ..... 74      ← TODOS
SIN confirmar .............. 0
```

`mailer_autoconfirm` **solo afecta a registros nuevos**; Supabase mira
`email_confirmed_at`, que los 74 ya tienen (se los estampó el autoconfirm).
Nadie tiene que verificar retroactivamente, nadie pierde acceso.

Además, **el 61% entra por OAuth** (apple 25 + google 20 = 45 de 74) y esos
proveedores ya entregan el mail verificado ⇒ la verificación solo afecta a los
**29** de email/contraseña.

---

## 2. 🍎 Login de Apple + "olvidé mi contraseña" — PROBLEMA REAL, va al build

**NO se tocó hoy. Es ajuste de UI para el build de mañana.**

### El problema

En `login_screen.dart` está todo en UNA pantalla, en este orden:

```
campo Email → campo Contraseña → "¿Olvidaste tu contraseña?" (L532)
→ botón Ingresar → divisor → Continuar con Google → Continuar con Apple
```

Una usuaria de Apple ve el formulario de contraseña **primero** y el botón de
Apple más abajo. Que toque "¿Olvidaste tu contraseña?" es plausible.

### Los números (verificados)

```
identidades:  email 29  |  apple 25  |  google 23
con password ................ 29
SIN password ................ 45     ← 61%, ven el link igual
con identidad 'email' ....... 29     ← exactamente los mismos 29
usuarios con password pero SIN identidad email:  0
```

Los 29 con contraseña son **exactamente** los 29 con identidad `email`.
**Cero** usuarios pasaron por este flujo hasta ahora.

### ⚠️ Territorio no pisado

Si alguien de Apple completa el reset, sería el **primer** caso de "usuario con
contraseña pero sin identidad `email`" en toda la base. **No está verificado que
`signInWithPassword` funcione en ese estado** — GoTrue reciente valida contra la
identidad, no solo contra `encrypted_password`. **Probar con una cuenta
descartable antes de afirmar nada.**

### ✅ Opción recomendada

**Que el reset detecte la cuenta solo-OAuth y no mande el mail**, respondiendo
algo tipo: *"Tu cuenta entra con Apple. Tocá el botón 'Continuar con Apple'."*

Es lo más simple, evita el estado no probado, y le resuelve la confusión a la
persona en el momento. Requiere saber el proveedor antes de mandar: se puede
con un RPC `SECURITY DEFINER` que reciba el email y devuelva solo el proveedor
(**sin filtrar si la cuenta existe o no**, para no habilitar enumeración de
usuarios).

Alternativas descartadas por ahora: separar visualmente los métodos en el login
(no resuelve el fondo), o dejarlo y aceptar los dos métodos (depende del estado
no verificado de arriba).

---

## 3. Qué queda para el BUILD de mañana

El build ya estaba destrabado (Tanda 2 de lista de espera cerrada). Se suman:

| Ítem | Dónde |
|---|---|
| ~~Mensaje `email_not_confirmed` en el login~~ | ✅ **ya está en el código** desde el 2026-08-19 (`3efb5d9`); entra solo con buildear |
| Reset que detecta cuenta solo-OAuth | `login_screen` / `auth_service` — punto 2 |
| El cartel de créditos que tapa contenido | `detalle_clase_screen` — ver `LISTA_ESPERA_arreglar_y_asegurar.md` |
| **Push**: copiar los 2 archivos de Firebase, agregar el `.plist` DESDE XCODE, verificar `aps-environment` | ver `PUSH_NOTIFICACIONES.md`, sección "PARA LA MAC" |

**Lo que NO necesita build** (todo servidor): centrar el punto del logo, subir
`mailer_otp_exp`, activar `mailer_autoconfirm`.

---

## Notas sueltas

- `main.dart:164` llama a `acreditar_bienvenida` en **cada login**, y esa
  función **no existe** en la base (la migración
  `supabase/pendiente_bienvenida/20260723110000_bienvenida_creditos_apagado.sql`
  nunca se aplicó). Falla con `PGRST202`, tragado por su `try/catch`. Inofensivo
  pero es una request fallida por sesión.
- **Orden decidido para la bienvenida**: primero verificación de mail, DESPUÉS
  aplicar la migración y encender el flag. Motivo:
  `admin_encender_bienvenida` **acredita retroactivamente a todos los ya
  registrados**; encenderla sin verificación dejaría cobrar a cuentas con mails
  truchos.
- La cuenta de Sofi (`sofi.rey.2000@gmail.com`) tiene **dos identidades**:
  apple (23/06) y google (14/08), sin contraseña. Es una de las 3 con 2+
  identidades.
