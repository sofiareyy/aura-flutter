# 👉 RETOMAR ACÁ

**ESTADO:** abierto · **Verificado contra la base:** 2026-08-21

Punto de entrada de la próxima sesión. Escrito para arrancar sin re-pensar.

---

## Lo que quedó cerrado el 2026-08-21

Todo aplicado en producción y verificado con rollback + efecto medido:

| | Fix | SQL en el repo |
|---|---|---|
| 🔴 | `reservas`: UPDATE libre + INSERT gratis | `FIX_RESERVAS_ESCRITURA_CLIENTE_2026-08-21.sql` |
| 🔴 | Borrado en cascada de `usuarios` | `FIX_TANDA2_2026-08-21.sql` |
| 🔴 | 5 crons con 401 (Vault) | `FIX_CRONS_VAULT_2026-08-21.sql` |
| 🔴 | Borrado de cuenta roto por gift cards | commit `120b956` |
| 🔴 | **Farmeo del vencimiento + créditos eternos** | `FIX_FARMEO_VENCIMIENTO_2026-08-21.sql` |
| 🟠 | Storage acotado + límites | `FIX_TANDA2_2026-08-21.sql` |
| 🟠 | Foto de perfil (nunca había funcionado) | `FIX_FOTO_PERFIL_2026-08-21.sql` |
| 🟠 | Vencimiento de packs a 90 días | `FIX_VENCIMIENTO_PACKS_2026-08-21.sql` |
| 🟠 | Tabla `resenas` legacy | borrada |

**No queda ningún 🔴 abierto.**

---

## PASO 1 — Verificación de mail (lo que falta de la Sesión 1)

`mailer_autoconfirm = true`: hoy cualquiera se registra con un mail que no es
suyo y queda confirmado al instante.

**Cierra tres caminos de plata** (hoy en cero, pero se arman solos):

| Camino | Mecanismo | Se activa cuando |
|---|---|---|
| Créditos corporativos | `trg_vincular_usuario_empresa` → `grant_user_credits` automático por dominio | sumes la primera empresa |
| Reservas gratis | `reservar_clase`: estudio en modo `gestion` + mail en `estudio_alumnos` ⇒ 0 créditos | un estudio pase a modo gestión |
| Gift cards | `canjear_regalo` valida contra `auth.users.email` | haya gift cards sin canjear |

Y **destraba la bienvenida** (hoy inerte a propósito).

### ⚠️ Por qué no es solo tocar el toggle

Es un switch en el dashboard, pero **la app tiene que manejar el estado
"registrado sin confirmar"**. Hoy asume que el login post-registro funciona
directo. Si no lo maneja, **rompés el registro para todos los usuarios nuevos**.

### MEDIR PRIMERO, sin activar nada

Todo esto se puede verificar con el toggle apagado:

1. **`register_screen.dart`**: ¿qué hace cuando `signUp` devuelve `session == null`?
   Con autoconfirm apagado, Supabase devuelve usuario sin sesión.
2. ¿Existe una pantalla o cartel de **"revisá tu mail"**? Si no, hay que hacerla
   (Dart ⇒ build).
3. ¿Qué pasa si alguien **intenta loguearse sin confirmar**? GoTrue devuelve
   `email_not_confirmed`. ¿La app lo traduce o muestra el error crudo?
4. **OAuth (Google/Apple)** no se ve afectado: llega con el mail ya verificado.
   Confirmarlo.
5. El template de confirmación **ya está configurado** en el dashboard
   (`mailer_subjects_confirmation` = "Confirmá tu cuenta en Aura"). Verificar que
   el `emailRedirectTo` apunte a `AppConstants.auraWebUrl` y esté en la allowlist.

**Recién con eso decidir** si se activa ya o si primero hace falta un build con
la pantalla de "confirmá tu mail".

---

## PASO 2 — Tanda de base (Sesión 3): 7 ítems, minutos cada uno

Todos sin build. Juntarlos en una sola sesión.

| # | Qué | Detalle medido |
|---|---|---|
| 1 | `ensure_referral_code` sin `SET search_path` | Es el **último** SECURITY DEFINER que le falta. Es `security definer`, alcanzable por `authenticated` |
| 2 | Borrar la RPC muerta `admin_update_global_credit_value` | **0 llamadores** (la app usa `admin_set_valor_credito_ars`). No escribe `configuracion_global`, por eso desincroniza |
| 3 | Borrar la columna fantasma `clases."lugares_ disponibles"` (con espacio) | **0 filas** con dato; las 885 usan la correcta. **OJO**: el Dart la nombra en **8 lugares**, siempre con `??` después de la correcta ⇒ borrar la columna es seguro, limpiar el Dart va después (build) |
| 4 | Whitelist de estados del estudio | Ver `WHITELIST_ESTADOS_ESTUDIO.md`. Que un estudio no pueda revivir una `cancelada` a estado facturable |
| 5 | Exigir la firma del webhook de MP | Hoy se calcula y **se descarta**: `if (signature && !valid) console.warn(...)` sin cortar, y el branch GET ni la evalúa. Requiere redeploy de la edge |
| 6 | Borde de `cancelada_por_estudio` en `reservas_usuario_clase_uidx` | El índice excluye solo `'cancelada'` ⇒ si el estudio cancela y reabre, la usuaria **no puede volver a reservar**. Cambiar a `NOT IN ('cancelada','cancelada_por_estudio')` |
| 7 | Correo saliente: SPF + Reply-To | Ver `CORREO_SALIENTE.md`. `somosaurapass.com` no tiene MX ni SPF; `hola@somosaura.app` sí recibe |

---

## Después

- **Sesión 2** — `PRESERVAR_FACTURACION.md` (cambio de esquema, el más pesado)
- **Sesión 4** — tanda de Dart, **un solo build**: cartel de lista de espera,
  modo visita Pieza C, "Reservar gratis", limpieza de la foto de perfil, las 8
  referencias a la columna fantasma, badge, y salir de las keys legacy
- **Mantenimiento** — `SANEAR_ESTOS_DOCS.md`
- **Feature en evaluación** — eventos gratis: técnicamente anda out-of-the-box
  (medido), el límite "1 por persona por evento" **ya existe** en doble capa.
  Falta solo documentarlo

---

## Estado del repo al cerrar

`origin/main` = `87c0f6d`, sincronizado, sin nada pendiente de pushear.
Builds **1.0.6+25** enviados a revisión en App Store y Google Play.
