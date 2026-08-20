# Auditoría de seguridad integral — 2026-08-20

Revisión de que todos los fixes de seguridad de la semana siguen en pie, más un
barrido transversal de grants y RLS. **Ningún fix se revirtió ni se pisó.**
Aparecieron 2 agujeros críticos **preexistentes** (ya cerrados) y una lista de
menores (abiertos).

## ✅ Los 8 fixes verificados en la base actual

| Fix | Evidencia |
|---|---|
| Regalos (minting) | `regalos` con RLS; única policy es SELECT (remitente por `auth.uid()` o destinatario por email del JWT). **Sin policy de INSERT** ⇒ nadie crea regalos desde el cliente |
| `confirm_pre_reserva` | deriva el precio de la clase, filtra por `usuario_id = auth.uid()`, valida estado y expiración |
| Campanita (`notificaciones_estudio`) | SELECT/UPDATE por `es_miembro_de_estudio()`; sin puntero legacy |
| `generar_clases_*` | `generar_clases_estudio` con guard y ACL sin PUBLIC/anon; `generar_clases_todos_estudios` solo `postgres \| service_role` |
| Idempotencia suscripciones | `pagos.credits_granted_at` existe y la usan plan y pack |
| Separación datos de cobro | **0** columnas sensibles en `estudios`; `estudios_datos_cobro` con RLS, anon → 401 |
| `valor_credito` NULL + trigger | default NULL, `trg_estudios_datos_cobro` presente |
| Lista de espera | una sola policy (`waitlist_own`), motor por `created_at`, guards en promote/release |

**Tablas sensibles, probadas con la anon key real:** `usuarios`, `pagos`,
`creditos_movimientos`, `reservas`, `regalos`, `lista_espera`, `empresas`,
`admin_users`, `notificaciones_usuario`, `liquidaciones` → **0 filas**;
`estudios_datos_cobro` y `notificaciones_estudio` → **401**.

**Funciones de plata:** `grant_user_credits`, `consume_user_credits`,
`process_approved_pack_payment` → solo `postgres | service_role` (anon → 401
confirmado por API).

---

## 🔴 CERRADOS hoy — 2 críticos preexistentes

SQL: `supabase/FIX_2_CRITICAS_PRICING_CORPORATIVO.sql`. Solo base, sin Dart.

### 1. `admin_upsert_pricing_pack` — cualquiera reescribía precios de packs
`SECURITY DEFINER`, alcanzable por **anon**, y **sin `is_admin()`** pese al
nombre. `pricing_credit_packs` es la MISMA tabla que lee `crear-checkout-pack`
**para cobrar** ⇒ se podía poner un pack a $1 y comprarlo, o insertar packs.
**Verificado explotable: se ejecutó desde anon en la auditoría.**

Fix: guard `is_admin()` al inicio + `revoke from public, anon` +
`grant to authenticated, service_role`. Cuerpo y firma idénticos (los 9
parámetros con sus defaults).

### 2. `acreditar_creditos_corporativos` — minteaba créditos desde anon
Sin argumentos, sin guard, alcanzable por **anon**, y adentro llama a
`grant_user_credits` en loop. **Se ejecutó desde anon**; devolvió 0 solo porque
hoy no hay empresas activas con créditos por empleado.

Fix: **solo permisos**, `revoke from public, anon, authenticated` +
`grant to service_role`. No es cambio de diseño: **restaura el candado
original** — `EMPRESAS_CORPORATIVO.sql:207` ya decía
`grant execute ... to service_role`. El grant público se coló después, casi
seguro por un `drop`+`create` posterior (que resetea el ACL a los defaults de
Supabase). Queda igual que `generar_clases_todos_estudios`.

Llamador legítimo confirmado: la edge `acreditar-creditos-corporativos` valida
el service_role en el header (fail-closed) y crea su cliente con
`SERVICE_ROLE_KEY` ⇒ el cron sigue andando.

### Verificación (rollback, con `set role` real)

| | |
|---|---|
| ADMIN edita un pack | precio 22000 → 12345 ✅ |
| Llamada sin `p_vencimiento_dias` | resolvió con el default 90 ✅ (el backoffice no lo manda) |
| SERVICE_ROLE ejecuta la corporativa | `{"empresas":0,"usuarios":0,"creditos":0}` ✅ |
| anon → packs | `permission denied` (grant) ✅ |
| anon → corporativa | `permission denied` (grant) ✅ |
| usuaria común → packs | `No autorizado` (guard) ✅ |
| usuaria común → corporativa | `permission denied` ✅ |
| Post-rollback vía API | ambas HTTP **401**; packs en 22000/50000/95000/180000 ✅ |

---

## 🟡 ABIERTOS — para la próxima sesión

`SECURITY DEFINER`, alcanzables por `anon`, **sin ningún guard interno**
(`is_admin` / `auth.uid` / `es_miembro_de_estudio`). No son regresiones: nunca
entraron en ninguna tanda.

| Función | Riesgo |
|---|---|
| `decrementar_lugares(clase_id)` | **No probada (destructiva).** Bajarle cupos a cualquier clase. Sabotaje |
| `vincular_usuario_a_empresa(p_user_id, p_email)` | **Encadena con la 🔴 2**: vincularse como corporativo. Cerrar la 2 corta el minteo, pero esta sigue suelta |
| `aviso_destinatarios_email(p_aviso_id)` | Posible fuga de emails de alumnas |
| `refresh_user_credit_balance(p_user_id)` | **Confirmada: anon la ejecuta.** Solo recalcula desde el ledger (idempotente, no mintea), pero no debería ser pública |
| `admin_list_studio_accesses`, `admin_list_studio_categories` | `admin_*` sin `is_admin()` (lectura) |
| `aplicar_pricing_a_clases_futuras`, `avisos_generales_restantes`, `calcular_precio_clase`, `completar_reservas_vencidas`, `ensure_referral_code`, `notify_profes_nueva_reserva`, `recalc_pack_prices`, `refresh_estudio_rating` | Menores; revisar con el mismo criterio |

Otros observados, fuera de alcance:
- `process_approved_plan_payment` tiene grant a **`authenticated`** (no solo
  service_role). Valida el estado del `pagos` + `credits_granted_at`, no
  `auth.uid()`. Conviene revisar si un logueado puede forzar la acreditación.
- `admin_upsert_pricing_pack` **no tiene `SET search_path`** (clase de
  vulnerabilidad en SECURITY DEFINER). No se agregó para mantener el cambio
  mínimo y reviewable.

## 🐛 Bug de datos encontrado de paso (no de seguridad)

`AdminService.upsertPricingPack()` (`admin_service.dart:673`) **NO manda
`p_vencimiento_dias`**, así que toma el default **90**. Pero los packs reales
tienen 30 / 45 / 45 / 60 días ⇒ **cada vez que se edita un pack desde el
backoffice, su vencimiento se resetea a 90 días.** Se ve en la verificación:
tras la edición de prueba el pack 4 quedó en 90, y tras el rollback volvió a 30.
Es Dart + RPC, arreglar aparte.

## Nota de método

Tres tests míos dieron falsos negativos esta semana por asumir que "no hubo
error" = "bloqueado":
1. Un `UPDATE` filtrado por RLS afecta 0 filas **sin lanzar excepción**.
2. Llamar RPCs con `{}` da 404 por **argumentos faltantes**, no por permisos —
   dos que parecían bloqueadas en realidad ejecutaban.
3. `revoke ... from anon` es un **NO-OP** si `PUBLIC` tiene el grant
   (`=X/postgres`): anon hereda de PUBLIC. **Hay que revocar PUBLIC.**

Regla para la próxima: medir el efecto (filas afectadas, ACL real, `set role`
con argumentos correctos), nunca la ausencia de error.
