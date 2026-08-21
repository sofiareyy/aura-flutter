# Verificación de mail + login de Apple — para retomar

Fecha: 2026-08-21. **Escrito para retomar en un chat nuevo sin re-investigar.**
Todo lo de acá está VERIFICADO contra la base y el código, no supuesto.

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

### ⚠️ El punto del logo está corrido (PENDIENTE, ya diagnosticado)

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

<!-- DESPUÉS -->
<div style="width:28px;height:28px;border:3px solid #0d0d0d;border-radius:999px;">
  <div style="width:10px;height:10px;background:#0d0d0d;border-radius:999px;
              margin:6px auto 0;"></div>
</div>
```

**Por qué 6px**: anillo de 28px con borde de 3px ⇒ 22px por dentro. Punto de
10px. `(22 − 10) / 2 = 6`. `auto` centra en horizontal. Solo usa `margin`, que
Gmail / Outlook / Apple Mail respetan sin excepción.

**No se toca nada más**: ni el naranja, ni el anillo, ni el tamaño, ni el
wordmark `AURA.`. Un solo atributo `style`.

Se aplica con la Management API: `PATCH /v1/projects/{ref}/config/auth` con
`mailer_templates_{confirmation,recovery,magic_link,invite}_content`.

### 📋 Pasos que faltan, en orden

1. **Centrar el punto** en las 4 plantillas (arriba). ← lo único que quedó a medio hacer
2. **Subir `mailer_otp_exp`** de `3600` (1h) a `86400` (24h). Con 1h, quien
   abre el mail al día siguiente encuentra el link vencido.
3. **Mensaje en el login** para `email_not_confirmed` → *"Revisá tu mail para
   confirmar tu cuenta"* + botón de reenviar. **Es Dart ⇒ va al build.**
4. **Activar**: `mailer_autoconfirm = false`. No necesita build, es servidor.
5. Opcional: personalizar la plantilla `email_change`, la única genérica.

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
| Mensaje `email_not_confirmed` en el login | `login_screen` — punto 1.3 de arriba |
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
