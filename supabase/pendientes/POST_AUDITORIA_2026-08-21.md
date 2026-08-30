# Pendientes de la auditoría del 2026-08-21

Lo que se **midió** y se decidió **no tocar** antes del build. Nada de esto es
explotable hoy salvo donde se aclara.

---

## 🟠 Verificación de mail apagada (`mailer_autoconfirm = true`)

Cualquiera se registra con un mail que no es suyo y queda confirmado al
instante. El template "Confirmá tu cuenta" existe y está configurado, pero no
se exige.

Importa porque **tres reglas de negocio usan el mail como prueba de identidad**:

| Camino | Mecanismo | Exposición al 21/8 |
|---|---|---|
| Créditos corporativos | `trg_vincular_usuario_empresa` → si el dominio matchea una empresa activa, `grant_user_credits` automático | 0 empresas activas |
| Reservas gratis | `reservar_clase`: estudio en modo `gestion` + mail en `estudio_alumnos` ⇒ `creditos = 0` | 0 estudios en gestión, padrón vacío |
| Gift cards | `canjear_regalo` valida contra `auth.users.email` | 0 sin canjear |

**Los tres en cero hoy**, por eso se postergó. Pero se arman solos: el día que
entre la primera empresa, cualquiera con un mail `@esa-empresa.com` se lleva
los créditos sin trabajar ahí.

**Activar antes de sumar la primera empresa.** Es un toggle en el dashboard,
pero hay que probar que la app maneje el estado "registrado sin confirmar"
(hoy asume que el login post-registro funciona directo).

---

## 🟡 Firma del webhook de Mercado Pago: no se exige

`isValidSignature()` está bien implementada (HMAC-SHA256, fail-closed sin
secretos) pero **su resultado se descarta**:

```js
if (signature && !(await isValidSignature(req, rawBody))) {
  console.warn('firma invalida, continuando con verificacion por API')
}
```

Si la firma es inválida solo loguea. Si no mandás el header, ni se evalúa. El
branch **GET no la chequea en absoluto**.

**No mintea créditos** y esto se midió: `procesarPago` ignora el body y
re-consulta `api.mercadopago.com/v1/payments/{id}` con el token real del
comercio; el `status` sale de MP. La acreditación es idempotente (medido:
saldo 0 → 50 en la primera llamada, se queda en 50 en el replay) y
`process_approved_pack_payment` tiene ACL solo `postgres` + `service_role`.

Queda como defensa en profundidad: hoy cualquiera puede invocar el endpoint y
forzar el procesamiento de IDs arbitrarios (llamadas salientes a MP, ruido).
Fix: hacer que el POST corte con 401 si la firma no valida, y chequear también
en el GET.

---

## 🟡 Menores medidos

- **`anon` enumera los 83 objetos de storage.** Los buckets son públicos, así
  que el contenido ya era accesible; lo nuevo es poder listarlos.
- **`estudio_vistas` con `CHECK true`**: se pueden insertar vistas sin límite
  (medido: 5 de una). Infla las métricas que ve el estudio.
- **Lista de espera sin tope por usuaria**: no se puede repetir clase (hay
  unique), pero se puede anotar en 300 clases de una (medido).
- **`pack_credits_expiration` tiene 3 overloads con semánticas distintas**
  (una devuelve fecha desde la compra, otra días desde el nombre del pack, otra
  fecha con `valid_days`). Riesgo de vencimiento mal calculado según qué firma
  resuelva. Unificar.
- **Bucket `avatares`**: público y vacío. Ver abajo, está roto.
- ~~**`crear-pago-pack` y `email-confirmacion`** existen en el repo pero **no
  están desplegadas**.~~ **DESACTUALIZADO — cerrado el 30/8.**
  `email-confirmacion` está **desplegada** (v1, 28/8) y **cableada por base**
  con el trigger `trg_notif_email_confirmacion_alumna`.
  `crear-pago-pack` era **código muerto** (0 referencias en `lib/` y `web/`; el
  camino vivo es `crear-checkout-pack`): **borrada del repo y del `config.toml`
  el 30/8.**

---

## 🐛 Bug funcional: subir foto de perfil no anda

Las dos pantallas de perfil suben al bucket **`avatares`**:

- `editar_perfil_screen.dart` → `MediaUploadService.uploadAvatar()` → path
  `{userId}/perfil.{ext}`
- `mi_perfil_screen.dart:794` → upload directo → path `{userId}/perfil.jpg`

…y `avatares` **no tiene ninguna policy de INSERT**, así que las dos fallan.
Por eso el bucket está vacío. El único avatar real vive en
`user-media/avatars/<uid>/…`, de una versión anterior que usaba
`pickAndUpload(bucket: 'user-media', folder: 'avatars')`.

Dos arreglos posibles:

1. **Apuntar las dos pantallas a `user-media`** con la convención
   `avatars/<uid>/<ts>.<ext>` (ya cubierta por la policy nueva
   `user_media_upload_own_folder`). Es cambio de Dart, sin tocar la base.
2. Darle policy propia a `avatares`, acotada por `(foldername)[1] = auth.uid()`.
   Ojo: `mi_perfil_screen` arma el path a mano, hay que unificarlo igual.

Preferible la 1: deja un solo bucket de media de usuario y borra `avatares`.

---

## 🧹 `admin_update_global_credit_value`: código muerto e incompleto

Hay **dos** RPCs para cambiar el valor del crédito:

| RPC | `configuracion_global` | `estudios_datos_cobro` | packs | planes |
|---|:--:|:--:|:--:|:--:|
| `admin_set_valor_credito_ars` | ✅ | ✅ | ✅ | — |
| `admin_update_global_credit_value` | ❌ | ✅ | ✅ | ✅ |

La segunda **no escribe `configuracion_global`**. Medido: llamándola con 1200,
los estudios y los packs pasan a 1200 y la config global se queda en **1000**.
Como `ValorCredito` lee la config global, cualquier estudio nuevo (que nace con
`valor_credito = NULL`) quedaría liquidando a 1000 mientras el resto va a 1200.

**No es explotable ni está en uso**: la app llama solo a
`admin_set_valor_credito_ars` (desde `admin_config_screen.dart:103`);
`updateGlobalCreditValue` no la invoca ninguna pantalla. Conviene borrar el RPC
y el método muerto para que nadie lo llame por error.

---

## ✅ Cerrado el 2026-08-21: vencimiento de packs

`admin_upsert_pricing_pack` tenía `p_vencimiento_dias integer DEFAULT 90` y el
UPDATE lo escribía sin condición, así que editar un pack le reseteaba el
vencimiento a 90 días (los reales son 30/45/45/60). Medido: Esencial 45 → 90.

Arreglado del lado servidor (`supabase/FIX_VENCIMIENTO_PACKS_2026-08-21.sql`):
default a `null` y `coalesce(p_vencimiento_dias, vencimiento_dias)` en el
UPDATE — "si no me decís nada, no cambies". Aplica a todos los llamadores sin
build nuevo. Packs nuevos sin el parámetro: 60 días. Verificado 6/6.

De paso se le agregó el `SET search_path` que le faltaba.

### Lo que quedó pendiente de esto

1. **Dart**: `AdminService.upsertPricingPack()` sigue sin exponer
   `p_vencimiento_dias`. Hoy da igual — el método es **código muerto** (0
   llamadores) y no existe pantalla para editar packs. **Cuando se arme esa
   pantalla, hay que agregarle el parámetro**, o el vencimiento no va a ser
   editable desde la UI (se va a preservar siempre, que es el comportamiento
   seguro, pero no configurable).
2. **`ensure_referral_code` sigue sin `SET search_path`.** Es el último
   SECURITY DEFINER del proyecto que le falta. Al escribir el plan se dijo que
   `admin_upsert_pricing_pack` era la única; eran dos.
