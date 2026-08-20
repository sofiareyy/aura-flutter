# Proyecto: arreglar + asegurar la promoción de lista de espera

Nota original: 2026-08-19.

## ✅ TANDA 1 (base) — APLICADA Y VERIFICADA 2026-08-20

SQL: `supabase/LISTA_ESPERA_TANDA1.sql`. **Sin tocar Dart**, así que no hubo
build ni deploy. Todo verificado en transacción + rollback: **15/15** del flujo
legítimo y **10/10** de los exploits. La base quedó limpia (0 filas de prueba).

### Lo que se arregló

**A — el motor.** Toda la lógica pasó a `_waitlist_promote_interno`, con los
**4** bugs corregidos (el pendiente original tenía 2; los otros dos aparecieron
al mirar el código desplegado):

| # | Bug | Fix |
|---|---|---|
| 1 | `FOR UPDATE` sobre `left join estudios` → *"cannot be applied to the nullable side of an outer join"*. **Fallaba acá siempre.** | Lock sobre `clases` sola; el nombre del estudio en un select aparte sin lock |
| 2 | `order by posicion` — la columna nunca existió | `order by created_at asc, id asc` (llegada, con desempate determinista) |
| 3 | `update lista_espera set posicion = posicion - 1` | Eliminado |
| 4 | 🆕 `delete ... where usuario_id = v_user_id` comparaba **`text` = `uuid`** (no existe ese operador) | Se borra por `id` de la fila de lista de espera |

**A5 — el promovido ahora se entera.** 🆕 Hallazgo de esta sesión: el aviso
in-app lo insertaba el **cliente** con el `usuario_id` de OTRO, y RLS lo
denegaba (`notificaciones_usuario` solo tiene policies de SELECT y UPDATE); el
error quedaba tragado por su `try/catch`. Nadie se enteraba de nada, teniendo
30 minutos para confirmar. Ahora el insert lo hace la función, que es
`SECURITY DEFINER` y saltea RLS.
> ⚠️ Es la **campanita in-app**, NO un push al celular. Un push real necesita
> FCM/APNs, que el proyecto no tiene montado. El promovido lo ve al abrir la app.

**B — guards**, con función interna en vez del flag de sesión que se había
pensado (`app.wl_internal`): más limpio porque la interna simplemente no se
puede llamar desde afuera, sin depender de setear/resetear una variable.

```
_waitlist_promote_interno   postgres | service_role          ← nadie más la alcanza
waitlist_promote_next       postgres | authenticated | service_role
release_pre_reserva         postgres | authenticated | service_role
cleanup_pre_reservas        postgres | authenticated | service_role
waitlist_count              + anon (a propósito: devuelve solo el número)
waitlist_mis_posiciones     postgres | authenticated | service_role
```

- `waitlist_promote_next`: permite `is_admin()`, `es_miembro_de_estudio()`, o
  tener alguna reserva en esa clase (el que acaba de cancelar la suya).
- `release_pre_reserva`: liberás la tuya, o una vencida (cleanup).
- ⚠️ **Ojo para la próxima**: el `revoke ... from anon` inicial era un **no-op**.
  Las funciones tenían el grant a `PUBLIC` (`=X/postgres`) y `anon` hereda de
  ahí. Hay que **revocar `PUBLIC`** y otorgar explícito a `authenticated`.

**C — policy cerrada.** `waitlist_count_public` (`USING true`, exponía
`usuario_id` a `anon`) eliminada. Las dos policies redundantes consolidadas en
`waitlist_own`. RPCs nuevas: `waitlist_count(clase_id)` (solo el número) y
`waitlist_mis_posiciones()` (posición derivada con `row_number()`).

### Verificación D — resultados

**Flujo legítimo (15/15):** dos en lista con `created_at` separado → C libera su
pre-reserva → **se promovió a A, el de `created_at` más viejo, no a B** →
pre-reserva de A con `expires_at` a 30.0 min y `creditos_usados=0` → se borró la
fila de A y **quedó la de B** → `lugares_disponibles` neto **cero** → **1
campanita para A y 0 para C** (el que liberó) → A confirma → `estado=confirmada`
y se le cobran **12 créditos, el precio real** → el trigger **encoló el mail**
(cola 0→1, revertido por el rollback: no se mandó nada).

**Exploits (10/10):** promover clase ajena → `no_autorizado`; liberar la
pre-reserva **activa** de otro → `no_autorizado`; liberar una **vencida** →
permitido; `anon` en las 3 funciones → `permission denied`; `authenticated`
llamando a la interna → `permission denied`; `anon` leyendo `lista_espera` → 0
filas (habiendo 1 real); `waitlist_count` como `anon` → devuelve **3** de 3
reales, sin identidades.

---

## ⏳ TANDA 2 (cliente / Dart) — PENDIENTE

**Necesita build + prueba en Chrome + push (que deploya a producción).**
El cliente ya está roto hoy, así que dejarlo no empeora nada.

### 1. Sacar el `showImmediate` mal dirigido
`reservas_service.dart:418` — `NotificacionesService.showImmediate` es una
notificación **local**: se muestra en el teléfono de **quien ejecuta el código**,
o sea **el que canceló**, no el promovido. Esa persona ve "Tenés 30 minutos para
confirmar tu lugar en X", que no es suyo. **Borrar ese bloque**; la campanita ya
la crea la función (A5).
- Hoy el bug está **dormido** porque la promoción nunca funcionaba y el loop no
  corría. **La Tanda 1 lo despierta.**
- Solo afecta **móvil**: en web `showImmediate` arranca con `if (kIsWeb) return;`.
- Se puede sacar también el insert a `notificaciones_usuario` (líneas ~430): RLS
  lo deniega y ahora sería duplicado.

### 2. Los 6 usos de `posicion` → `waitlist_mis_posiciones()`
La columna **no existe**, así que todo esto devuelve **HTTP 400** hoy (la sección
"En espera" de Mis Reservas está caída):

| Sitio | Qué hace |
|---|---|
| `reservas_service.dart:468` | `.select('clase_id, posicion, clases(...)')` |
| `reservas_service.dart:470` | `.order('posicion', ascending: true)` |
| `mis_reservas_screen.dart:456` | `.select('usuario_id, posicion')` |
| `mis_reservas_screen.dart:458` | `.order('posicion')` |
| `mis_reservas_screen.dart:171-175` | delete + "reordenar posiciones" |
| `mis_reservas_screen.dart:600`, `1797-1829` | muestra `'Posición #$posicion'` |

La RPC `waitlist_mis_posiciones()` devuelve `(clase_id, posicion, total)` para
`auth.uid()`. Sugerido: query normal a `lista_espera` (propias, `order by
created_at`) con el embed de `clases`, y **una sola llamada** a la RPC para
mapear `clase_id → posicion`. Sin N+1.

### 3. `waitlist_service.getCount()` → `waitlist_count()`
`waitlist_service.dart:18-24` cuenta filas del lado cliente
(`.from('lista_espera').select('id').eq('clase_id', ...)`), que es justo lo que
la Tanda 1 cerró. **Ahora devuelve siempre 0.** Repuntar a
`rpc('waitlist_count', {'p_clase_id': claseId})`.

### 4. Probar en Chrome
Anotarse en una lista de espera, ver la posición y el conteo, cancelar desde
otra cuenta y confirmar que el promovido ve la campanita al abrir la app.

---

## Contexto que sigue vigente

- `cancelar_mi_reserva` marca `estado='cancelada'` (no borra) y **no** promueve:
  la promoción la dispara el cliente (`reservas_service.dart:400` y
  `estudio_admin_service.dart:561`). **Evaluar aparte** mover la promoción
  server-side adentro de `cancelar_mi_reserva`: sería más robusto (promueve
  aunque el cliente se cierre) y permitiría cerrar todavía más el guard de
  `waitlist_promote_next`, pero cambia de dónde salen las notificaciones.
- `lista_espera.usuario_id` es **text** (no uuid). Tenerlo en cuenta siempre.
- `lista_espera` tiene unique `(clase_id, usuario_id)` — el `upsert` de `join()`
  funciona bien.

---

## Diagnóstico original (2026-08-19) — se deja por contexto

## Estado actual: la promoción NO funciona

`waitlist_promote_next(p_clase_id, p_count)` **falla siempre** (error inmediato,
tragado por su `exception when others` → devuelve `ok:false` en silencio). Nadie
se promociona nunca → no se crean `pre_confirmada`s → `confirm_pre_reserva` y
`release_pre_reserva` no tienen sobre qué actuar.

**Dos bugs que la rompen (verificado en vivo llamándola):**
1. **`FOR UPDATE` sobre un `LEFT JOIN`** — el primer `select ... from clases c
   left join estudios e ... for update` tira `"FOR UPDATE cannot be applied to
   the nullable side of an outer join"`. Salta primero.
2. **`order by posicion` sobre columna inexistente** — `lista_espera` NO tiene
   `posicion` (columnas: id, clase_id, usuario_id **(text)**, created_at,
   notificado). El `select usuario_id, posicion ... order by posicion` fallaría
   después de arreglar el #1. También hay `update lista_espera set posicion =
   posicion - 1` que hay que sacar.

## Qué hacer en la sesión dedicada (todo junto)

1. **Arreglar el bug #1 (FOR UPDATE):** separar el lock — bloquear `clases` con
   su propio `select ... for update` sin el join a `estudios` (traer el nombre
   del estudio en un select aparte, sin `for update`).
2. **Arreglar el bug #2 (posicion → created_at):** el orden de la lista de
   espera es por **`created_at`** (orden de llegada), como se decidió (ver
   `BADGE_PACKS_pendiente.md` / auditoría item B3). Sacar toda referencia a
   `posicion` (el `order by posicion` y el `update ... set posicion`). El "puesto"
   sale del orden por `created_at`, no de una columna renumerada.
   - OJO: `lista_espera.usuario_id` es **text** (no uuid). Tenerlo en cuenta en
     los joins/comparaciones (ya se sabía del pendiente de lista de espera).
3. **Guards de seguridad (caller validation)** — el finding 🟠 de Tanda 1:
   - `waitlist_promote_next`: que un usuario cualquiera no promueva la grilla de
     una clase ajena. Permitir: admin del estudio (`es_miembro_de_estudio`), o
     un usuario con reserva en esa clase, o llamada interna. Las llamadas
     internas (desde `release_pre_reserva`) necesitan saltar el guard — usar un
     flag de sesión (`set_config('app.wl_internal','1',true)`) seteado por
     release antes de llamar a promote, y reseteado después. `revoke ... from anon`.
   - `release_pre_reserva`: solo podés liberar **tu propia** pre-reserva, **o**
     una **vencida** (para el cleanup). Guard:
     `if usuario_id is distinct from auth.uid() and not (expires_at < now()) then
     rechazar`. Esto preserva: dueño rechaza la suya (auth.uid()=usuario_id),
     cleanup libera vencidas (expired), y bloquea liberar la pre-reserva activa
     de otro. `revoke ... from anon`.
   - Único llamador interno de promote: `release_pre_reserva`. `cleanup_pre_reservas_expiradas`
     llama a release (no a promote). Revocar anon de cleanup también (defensa).
4. **Verificar end-to-end** (las dos puntas, método de siempre):
   - **Flujo legítimo:** anotarse en lista de espera → se libera un cupo (cancelo
     una reserva) → **promueve** al siguiente (crea pre_confirmada) → el promovido
     **confirma** (`confirm_pre_reserva`, ya arreglado) → paga el precio real →
     (y con el trigger de email ya puesto, al confirmarse dispara el mail al estudio).
   - **Exploit tapado:** un usuario cualquiera no puede promover una clase ajena
     ni liberar la pre-reserva de otro.

## Contexto útil
- `cancelar_mi_reserva` marca `estado='cancelada'` (no borra) y **no** promueve
  hoy — la promoción la dispara el cliente (`reservas_service.dart:387`
  `_promoverYAvisar`, y `estudio_admin_service.dart:553` al aumentar cupo).
  Evaluar si conviene mover la promoción server-side dentro de cancelar/editar.
- Cuerpos actuales: `waitlist_promote_next`, `release_pre_reserva`,
  `cleanup_pre_reservas_expiradas` están en `supabase/FIX_WAITLIST_FLOW.sql`
  (pero el desplegado es el que manda — confirmar con `pg_get_functiondef`).
