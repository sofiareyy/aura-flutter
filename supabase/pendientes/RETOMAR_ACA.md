# 👉 RETOMAR ACÁ

**Verificado contra la base:** 2026-08-24 · **Único lugar donde viven los pendientes.**

---

## 📊 De un vistazo

| | Bloque | Estado |
|---|---|---|
| ✅ | **Auditoría completa** (8 áreas) | hecha · 6 hallazgos, 5 ya resueltos |
| ✅ | **Tanda 0** — crons + correo | cerrada |
| ✅ | **Tanda A** — barrido de base (8 items) | cerrada |
| ⏭️ | **Tanda B** — verificación de mail | **salteada por decisión**: se activa cuando entre la primera empresa |
| ✅ | **Auditoría de guards y grants** (dos tandas) | **hecha el 24/8** con el criterio de las dos puntas · 5 arreglos de base |
| 🔵 | **Alta de Rock Studio** (spinning, 2 sedes, 50 bicis) | **lo primero** · la cadena está verificada punta a punta, ver abajo |
| ⬜ | **Tanda C** — build de Dart (19 items) | **lo próximo** · bloqueada por saber si el build 25 se subió |
| ⬜ | **Tanda D** — Modelo C de precios | arrancar por el DISEÑO de reglas, no por código |
| ⬜ | **Tanda E** — experiencias, esquema pesado, keys legacy | |
| ⬜ | **Negocio** (los sigue la usuaria) | aviso del fin de gracia · mail de confirmación |

### ⚠️ Lo primero al retomar

**🔵 El alta de Rock Studio** (spinning, 2 sedes, 50 bicis, 15 para Aura).
El 24/8 se simuló **el proceso completo con cuentas reales** (no superadmin),
en transacciones con rollback, y **los 7 eslabones andan**: crear estudio con
precio modo rango · cargar clase suelta y grilla con el precio correcto ·
comprar pack (acredita con vencimiento) · reservar (descuenta, baja cupo, da
QR) · marcar presente · cancelar a tiempo (recupera) y tarde (no puede) ·
liquidación (70 % y primer mes sin comisión dan bien).

Dos cosas para tener a mano al configurarlo:
- **Modo rango: `valle` es opt-in.** Solo cobra `creditos_min` en los pares
  (día, hora) marcados en `horarios_config`; **todo lo no marcado es pico** =
  `creditos_max`. Si Rock Studio carga el rango y se olvida de marcar las
  franjas valle, **cobra el máximo en todas sus clases y nadie tira un error**.
  Es el punto más frágil del alta. La hora se trunca hacia abajo: marcar la
  franja "10" cubre 10:00, 10:30 y 10:45.
- **Cupos:** se carga `lugares_total = 15` (las bicis que van a Aura). El resto
  no existe para Aura. Medido: la reserva baja el disponible de a uno y
  `clases_resync_cupo` recalcula desde las reservas reales.

**Y dos cosas que esperan a la usuaria:**
- Que **YN Pilates confirme en el teléfono** que puede cargar y cancelar. Todos
  los arreglos del 24/8 son de base, así que ya los tienen sin actualizar nada.
- La decisión **antes del 13/9** sobre qué pasa con las alumnas ya anotadas
  cuando el estudio mueve una grilla (ver pendientes de NEGOCIO).

### 📏 La regla de trabajo que salió del 24/8

**Ningún guard cuenta como verificado hasta medir LAS DOS PUNTAS**: que el
exploit quede cerrado **y** que el usuario legítimo siga pudiendo trabajar.
`FIX_GUARDS_CUERPO.sql` (commit `f4ba3dd`) se validó midiendo solo lo primero,
y **dos de sus cinco guards estuvieron rotos en producción 4 días** sin que
nadie lo viera. No se vio porque se probó con `test@aura.com`, que es
superadmin y satisface `is_admin()`.

**Probar SIEMPRE con una cuenta de estudio real, nunca con `test@aura.com`.**
Y medir efecto —saldos, filas, estados antes/después—, nunca ausencia de error.

Las dos tandas sospechosas ya se auditaron enteras el 24/8
(`FIX_GUARDS_CUERPO.sql` y `FIX_AMARILLAS_AUDITORIA.sql`): 110 funciones, 23
tablas y 3 buckets. **No quedan guards mal validados.** La regla queda para lo
que venga.

**Averiguar si el build `1.0.6+25` se subió a las tiendas.** Los registros se
contradicen: `BUILD_IOS_pendiente.md` dice *"en preparación, número reservado
el 21/8"*, y una nota vieja de este archivo decía *"enviado a revisión"*. No se
puede saber desde el repo — hay que mirar App Store Connect y Play Console.
Si nunca se subió, la Tanda C sale en el 25 y no se quema otro número.
Es la segunda vez que pasa: el número 23 ya se perdió así.

---

# ✅ HECHO EL 2026-08-24 — incidente: los guards del 20/8

Disparado por **YN Pilates**, que no podía cargar clases desde el teléfono:
`PostgresException, message: "no autorizado", code: P0001`. No era config de ese
estudio: **estaba roto para los 11**.

Todo se aplicó a mano vía Management API. **Sin Dart ⇒ sin build.**
SQL completo con el porqué de cada decisión:
`supabase/FIX_GUARDS_20-8_MAL_VALIDADOS_2026-08-24.sql`.

| | Qué | Medición |
|---|---|---|
| ✅ | **GUARD 4 · `admin_list_studio_categories`** — el `is_admin()` del 20/8 rompía el panel de **todos** los estudios: `mis_clases_screen.dart` llama esa RPC para el selector de categorías (líneas 1186 y 208). Aflojado a `if auth.uid() is null`. Seguro porque `study_categories` ya tiene RLS SELECT `using (true)`. | 15 de 15 cuentas de estudio rechazadas → **21 de 21 pasan**, 13 categorías. anon → 42501; sin `auth.uid()` → P0001. |
| ✅ | **`estudio_cancelar_clase`** — le pasaba `reservas.creditos_usados` (**bigint**) a `grant_user_credits(p_amount integer)` ⇒ `42883`. Roto para todos, superadmin incluido. Casteado a `::int`. **No venía del 20/8**, pero tapaba al guard 5. | 42883 → **ok, 1 reserva cancelada, 10 créditos devueltos**. |
| ✅ | **GUARD 5 · `refresh_user_credit_balance`** — volteaba la devolución cuando el estudio cancelaba: `estudio_cancelar_clase` → `grant_user_credits(alumna)` → `refresh(alumna)` ⇒ P0001 y se caía la transacción entera: **nadie recuperaba créditos**. El recálculo se mudó a `_refresh_user_credit_balance_interno`, sin guard pero **revocada de anon/authenticated**; la RPC pública conserva el guard del 20/8 intacto. | saldo de la alumna **0 → 10**, reserva en `cancelada_por_estudio`, 1 lote. Saldo ajeno → P0001. Interno desde PostgREST → 42501. `cancelar_mi_reserva` → ok. |
| ✅ | **GUARD 1 · lista de espera** — la profe **nunca** se enteraba de las reservas que entraban por waitlist. No era el guard: `_waitlist_promote_interno` simplemente no cableaba el aviso (solo lo nombraba en un comentario). Cableado contra el interno, en bloque propio para que un fallo del aviso no voltee la promoción. | `aviso_a_la_profe` **0 → 1**, el aviso a la promovida sigue en 1, la reserva directa sigue avisando 1, la suplantación sigue en 0. |

**Guards 2 y 3 (`ensure_referral_code`, `avisos_generales_restantes`): sanos en
las dos puntas**, medidos.

### Segunda tanda del 24/8 — auditoría de las tandas ANTERIORES

Con el mismo criterio de las dos puntas, sobre lo de antes del 20/8:
**110 funciones de `public` (62 las llama la app), 23 tablas y 3 buckets.**
`FIX_AVISO_CANCELACION_Y_FAVORITOS_2026-08-24.sql`.

**No había más guards mal validados.** Los 62 tienen `execute` para
`authenticated`; la matriz de 17 funciones × 4 personas (alumna / profe /
estudio / superadmin) no bloqueó a ningún actor legítimo; y del otro lado, una
alumna ajena rebota en las 10 funciones que son solo del estudio. Storage:
subir a su carpeta OK, a carpeta ajena 42501.

Sí aparecieron **dos huecos más viejos que las tandas de endurecimiento**, que
nunca reportó nadie:

| | Qué | Medición |
|---|---|---|
| ✅ | **La alumna no se enteraba de que le cancelaban la clase.** `notificaciones_usuario` no tiene policy de INSERT; el aviso lo intentaba el cliente y RLS lo negaba en silencio. Ninguna función de la base lo creaba. Ahora lo crea `estudio_cancelar_clase` (SECURITY DEFINER, saltea RLS), en bloque propio para que un fallo del aviso no voltee la devolución. | campanita **0 → 1** con el texto correcto, créditos siguen en 0→10. Clase gratis: el texto no promete devolución. Dos alumnas: 2 campanitas. Fabricar notificaciones ajenas: sigue 42501. |
| ✅ | **Re-favoritear un estudio ya marcado fallaba.** `favoritos_estudios` tenía INSERT/SELECT/DELETE pero no UPDATE, y el `.upsert()` sobre la PK resuelve el conflicto con un UPDATE. | 42501 → pasa. No agrega capacidad: la usuaria ya podía borrar e insertar sus favoritos. |

⚠️ **Al tocar `notificaciones_usuario`: `trg_notif_push_nueva` está ACTIVO** y
dispara `net.http_post` a `push-enviar`. Se comprobó que el push se encola
dentro de la transacción y que el rollback lo borra (cola 0→1→0), así que
probar con rollback es seguro. Sin esa comprobación, un test manda un push real
al teléfono de alguien.

Queda para el build el item 18: borrar los dos inserts muertos del cliente.

### Tercera tanda del 24/8 — editar una grilla ya no duplica clases

Salió de relevar cómo funciona editar clases y grillas.
`FIX_GRILLA_MOVER_CLASES_2026-08-24.sql`. **Sin Dart ⇒ sin build.**

**El bug:** la app propaga los campos del horario fijo a las clases futuras
pero **no la fecha**. Editar el día o la hora fallaba de dos formas según el
tamaño del cambio: corrimiento **> 1 hora o cambio de día** → las clases viejas
quedaban publicadas en el horario anterior y el generador creaba otras encima
(**9 clases pasaban a 18, duplicadas, sin aviso**); corrimiento **≤ 1 hora** →
**se ignoraba en silencio**, porque el chequeo de existencia da por "ya creada"
cualquier clase de esa grilla dentro de ±1 hora.

**El arreglo:** un trigger en `horarios_fijos` que mueve las clases futuras
cuando cambia `dia_semana` u `hora_inicio`. Se mete antes de que la app
regenere, así que el chequeo de existencia las encuentra y los duplicados no
llegan a nacer.

⚠️ **El trigger es *invoker*, NO security definer, y es a propósito:** el
`update clases` de adentro dispara `clases_fija_precio`, que sale temprano si
`current_user` no es `authenticated`/`anon`. Siendo invoker, el precio se
recalcula solo al cambiar de franja. Como definer, una clase movida de valle a
pico se quedaría con el precio viejo — fue el falso negativo de la primera
medición, hecha como `postgres`.

| Medido como `sculptclub.ar@gmail.com` (rango 14 valle / 16 pico) | Antes | Ahora |
|---|---|---|
| hora 10:00→19:00 (valle→pico) | 9→18 duplica | **9→9** · 19:00 · 14→16 cr |
| hora 19:00→10:00 (pico→valle) | 9→18 duplica | **9→9** · 10:00 · 16→14 cr |
| día miércoles→viernes | 9→18 duplica | **9→9** · viernes |
| hora 10:00→10:30 (30 min) | se ignoraba | **9→9** · 10:30 |
| día Y hora juntos | 9→18 duplica | **9→9** · viernes 19:00 · 14→16 cr |
| solo profe / solo cupo / solo créditos | 9→9 ok | **9→9 ok**, sin regresión |
| clases pasadas de la grilla | no se tocan | **no se tocan** (15/7 quedó en 15/7 10:00) |

**Con esto, el instructivo ya no necesita la advertencia de "no toques el día
ni la hora de una grilla".** Queda una sola advertencia viva, la de workshops:
descripción larga, dirección y organizadores no se pueden editar (item 15).

**Queda decidir antes del 13/9** qué pasa con las alumnas ya anotadas cuando se
mueve una grilla — ver la tabla de pendientes de NEGOCIO.

### Cuarta tanda del 24/8 — no se puede borrar una clase con alumnas anotadas

Salió de investigar por qué la barra de progreso de Mi Perfil bajó de 1 a 0.
La barra estaba bien (cuenta reservas propias en `presente`/`completada`, y
`test@aura.com` no tiene ninguna). Lo que apareció detrás es lo importante.
`FIX_NO_BORRAR_CLASE_CON_ANOTADAS_2026-08-24.sql`. **Sin Dart ⇒ sin build.**

**El hueco:** los tres botones de borrar SÍ intentan devolver primero, pero
`_deleteFixed` (:2721) y `_eliminarGrillaCompleta` (:4624) hacen
`try{devolver}catch(_){}` y `try{borrar}catch(_){}` **por separado**: si la
devolución falla, el error se traga y **borra igual**. Como hasta el 24/8
`estudio_cancelar_clase` moría siempre con 42883, la devolución fallaba el
100% de las veces. Solo "eliminar clase suelta" (:4552) falla cerrado.

**La evidencia:** el ledger no tiene **ni un** movimiento
`devolucion_clase_cancelada`. Nunca un borrado devolvió créditos.

**El arreglo:** trigger `before delete` que rechaza si hay alumnas activas
(`confirmada`, `pre_confirmada`, `presente`) **o `completada`**. Se eligió bloquear en vez de
devolver-y-borrar porque **es invisible en el camino correcto** —la UI ya
cancela antes de borrar, así que las reservas llegan en `cancelada_por_estudio`
y el trigger ni se entera—, falla cerrado, y no hace que un DELETE mueva plata
en silencio. `completada` se sumó al candado el mismo día, para proteger el registro de
facturación: nadie necesita borrar clases viejas. El candado corre **solo en
BEFORE DELETE**, así que la navegación normal no lo ve.

| Medido como `citrabarre@gmail.com` (alumna con 32 cr, pagó 18) | Antes | Ahora |
|---|---|---|
| botón "eliminar clase suelta" | borró · saldo **32** | **BLOQUEADO** |
| botón "eliminar horario fijo" | borró · saldo **32** | **BLOQUEADO** |
| botón "eliminar toda la grilla" | borró · saldo **32** | **BLOQUEADO** |
| cancelar y después borrar | borró · saldo **50** | borró · saldo **50** |
| borrar con reserva **`completada`** | borró | **BLOQUEADO** (se sumó el mismo día) |
| borrar sin reservas / con `cancelada` | borró | borró |
| `admin_delete_estudio` (backoffice) | borró el estudio | borró el estudio |

La guarda `current_user not in ('authenticated','anon')` exime al backoffice y
a los crons: dentro de un SECURITY DEFINER de postgres `current_user` es
`postgres` (comprobado midiendo). La dueña y la profe pasan; la usuaria ajena no.

**Caminos de créditos a terceros revisados y a salvo:** `canjear_regalo`
acredita a `auth.uid()`; `activar_referido_por_compra` le da al referidor pero
lo disparan `mp-webhook` y `confirmar-pago-manual` con service_role
(`auth.uid()` null, que el guard deja pasar a propósito).

**Números de la base al cierre del 24/8:** 937 clases · 70 horarios fijos ·
4 reservas · 11 estudios · 15 movimientos de crédito · 63 créditos en circulación.
Todas las pruebas corrieron en transacciones con `rollback`; se verificó que
quedaran **0 filas de prueba**.

---

# ✅ HECHO EL 2026-08-22

### Quinta tanda del 24/8 — el estudio no puede marcar asistencia antes de tiempo

Salió de la prueba punta a punta previa a Rock Studio.
`FIX_NO_MARCAR_ASISTENCIA_ANTES_2026-08-24.sql`. **Sin Dart ⇒ sin build.**

Marcar asistencia es un UPDATE directo del cliente sobre `reservas`, sin
función de por medio. Se auditaron los vectores y **tres de cuatro ya estaban
cerrados** por RLS y por `reservas_bloquear_columnas_sensibles`: un estudio
sobre reservas de OTRO estudio (0 filas), revivir `cancelada` (P0001), cambiar
`creditos_usados` (P0001), fabricar una reserva (42501 — `reservas` no tiene
policy de INSERT).

**El que sí estaba abierto:** el QR no se valida en la base, así que el estudio
podía marcar `presente` cualquier reserva suya, sin escanear, de clases a 5 o
30 días vista. Eso **no** inflaba la liquidación por sí solo (`confirmada` y
`presente` están las dos en `estadosLiquidables`). El daño era otro, medido:

| | Antes | Ahora |
|---|---|---|
| Clase a 5 / 30 días / mañana / 13 h · también `ausente` | marcaba | **RECHAZADO** |
| Clase a 11 h (ventana cerrada), 20 min antes, empezando, +30 min, de ayer, ventana en 0 | marcaba | **marca igual** |
| **La alumna cancela tras el intento del estudio** | `{ok:false,"estado_invalido"}` saldo 50 | **`{ok:true, devueltos:18}` saldo 50 → 68** |

O sea: marcando presente por adelantado el estudio **le trababa la cancelación
y le retenía los créditos**, y sí movía plata por la vía indirecta (sin ese
movimiento la reserva se habría cancelado y no sería liquidable).

**La regla:** la asistencia se marca recién cuando la alumna ya no puede
cancelar — el daño escrito como regla. Usa la **misma cascada** que
`cancelar_mi_reserva`: clase → estudio → 720 min.
Se descartó "rechazar si la clase no empezó, con 10 min de tolerancia" porque
rompía dos casos legítimos: el check-in de quien llega 15-20 min antes (clave
con 50 bicis) y el marcado manual el mismo día. Con la ventana de cancelación,
una clase de las 19:00 con cierre de 12 h se marca desde las 07:00 de ese día.
El `greatest(cierre, 10)` conserva la tolerancia del escáner por si un estudio
pone la ventana en 0.

---

## Auditoría completa — las 8 áreas

La base está sana. Las áreas de plata directa aguantaron todo: **6 de 6
exploits de reserva bloqueados** (corridos con el JWT del dueño real),
**0 clases desviadas** de la regla de precio, y todo lo sensible invisible para
un anónimo — los CBUs ni llegan a RLS, dan `permission denied` a nivel de grant.

| Área | |
|---|---|
| 1 · Pricing (5 arreglos) | ✅ en pie |
| 2 · Farmeo del vencimiento | ⚠️ fuga lateral → **arreglada** el mismo día |
| 3 · Foto de perfil | ⚠️ correcta pero **nunca ejercitada** → va a Tanda C |
| 4 · Vencimiento de packs | ✅ |
| 5 · Escritura de reservas | ✅ 6/6 exploits bloqueados |
| 6 · CASCADE de usuarios | ⚠️ **confirmado abierto** → Tanda E |
| 7 · Los 6 crons | ✅ (uno estaba roto, arreglado) |
| 8 · Storage y RLS | ✅ |

**Los 6 hallazgos nuevos:** 5 resueltos el mismo día (la fuga de créditos, los
3 crons, `pack_credits_expiration`, `vigencia_dias`); quedan 2 → la foto de
perfil sin ejercitar (Tanda C) y la falta de policy DELETE en `storage.objects`.

## Tanda 0 — cerrada

| | |
|---|---|
| ✅ | **Los 3 crons mensuales.** `aviso-cobro-manana` **estaba roto**: pedía `reservas.estudio_id`, que no existe, y fallaba en silencio devolviendo 200 sin mandar un mail. Arreglado, con captura de errores y flag `dry_run` permanente en las dos funciones de mail. |
| ✅ | **Correo, sin tocar DNS.** El SPF ya existía en `send.somosaurapass.com`. Lo roto era que `hola@somosaurapass.com` no recibe. Se pasó el pie de los mails a `aura.hola.app@gmail.com` —que ya usaban la app y la web— y se sumó `reply_to` en las 6 funciones. |

## Tanda A — cerrada, 8 de 8

| | Qué | Migración |
|---|---|---|
| ✅ | **Créditos manuales sin vencimiento** — la única función que escribía en `creditos_movimientos` sin pasar por `grant_user_credits`. **0 eternos en toda la base.** | `20260822180000` |
| ✅ | **`ensure_referral_code`** — era la última sin `search_path`. **94 de 94 blindadas.** | `20260822190000` |
| ✅ | **Código muerto, 4 firmas** | `20260822190000` |
| ✅ | **Índice `reservas_usuario_clase_uidx`** — decía "ya reservaste" en clases que el estudio te había cancelado | `20260822200000` |
| ✅ | **`expires_at NOT NULL`** — cierra la tabla para que no vuelvan los eternos | `20260822210000` |
| ✅ | **Etiquetas de la grilla** — `v_tipo := 'normal'` hardcodeado hacía que TODA clase generada naciera mal etiquetada | `20260822210000` |
| ✅ | **`vigencia_dias` espejada** | `20260822220000` |
| ✅ | **El estudio no resucita reservas canceladas** — podía inflar su propia liquidación | `20260822230000` |

**Dos cosas NO se tocaron, a propósito:**
- **Las 189 clases sin categoría.** Es decisión del estudio. Se verificó que la propagación de la grilla funciona: correlación perfecta en 30 horarios fijos. No es bug del sistema.
- **`creditos_por_categoria`.** Archivo histórico deliberado ("la dejamos por si hay que auditarla").

**Y el noveno ítem no existía:** `estudios.estado` no es una columna. El pendiente
decía "estados del estudio" y era sobre `reservas.estado`, que sí se arregló.

### Números de referencia (para comparar la próxima)
885 clases · 70 horarios fijos · 5 reservas · 9 estudios · 78 usuarios ·
0 precios desviados · 0 etiquetas desviadas · 0 créditos eternos ·
0 experiencias futuras · rangos 11–18 (clases) y 50 (el workshop).

---

# ⬜ LO QUE QUEDA

## ⏭️ Tanda B — verificación de mail · SALTEADA

`mailer_autoconfirm = true`. **Decisión del 22/8: no ahora.** Se activa cuando
entre la primera empresa. El detalle completo está más abajo, en PASO 1.

## ⬜ Tanda C — el build de Dart · **lo próximo**

Todo junto, un solo release. ⚠️ **Antes: confirmar si el 25 ya se subió.**

**Alto impacto — el motivo del build**
1. **El texto de "gratis"** — una clase de 0 créditos dice `0 cr` y `Canjear · 0 créditos`, nunca "gratis". Para la captación no es cosmético. Ojo: el `'Reservar gratis'` que existe depende de `_esGratuita` ("sos alumno del estudio"), es otro gratis. **Decidir cuál gana.**
2. **Badge "PRECIO REDUCIDO"** en 573 de 583 clases (`explorar_screen.dart:1009`).
3. **El cartel de lista de espera tapa contenido** — pantalla de la alumna.
   ⚠️ **No confundir con el item 16**, que es la lista de espera del lado del
   ESTUDIO. Son dos cosas distintas que se llaman parecido.

**Consecuencias de lo que se hizo en base**
4. El mensaje de "falta configurar el precio" no llega en el alta (`mis_clases_screen.dart:1975`).
5. Borrar el método huérfano `updateGlobalCreditValue` (la RPC ya no existe).
6. Los multiplicadores de `_packsBase` están corridos: son `1.10/1.00/0.95/0.90`.
7. **La columna fantasma — base y Dart JUNTOS, en este mismo release.**
   `clases` tiene una columna `"lugares_ disponibles"` (con un espacio en el
   medio del nombre), duplicado muerto de `lugares_disponibles`. Verificado el
   24/8: **null en las 937 filas**. Está vacía y no molesta, así que **no se
   borra por separado antes** — hacerlo abriría una ventana en la que la base
   ya no la tiene y las apps viejas todavía la piden. Se hace todo de una:
   · `alter table public.clases drop column "lugares_ disponibles";`
   · y limpiar las referencias del Dart en el mismo build.
   ⚠️ **Son 10, no 8** (el conteo viejo estaba desactualizado). Las 10 leen
   `lugares_disponibles` PRIMERO y usan la fantasma solo como `??` de respaldo,
   así que sacar el fallback es seguro y no cambia comportamiento:
   `models/clase.dart:40` · `services/clases_service.dart:231` ·
   `services/estudios_service.dart:178` · `widgets/clase_card.dart:26` ·
   `screens/clases/detalle_clase_screen.dart:293,489` ·
   `screens/clases/mis_clases_screen.dart:3612,5021,5819,6699`.
8. **Probar que la foto de perfil funcione** — 0 archivos subidos desde el fix.

**Ya estaban en la lista**
9. "Ver todas" de Experiencias lleva a donde no hay ninguna.
10. Foto de perfil: dos caminos de upload duplicados (`DART_FOTO_PERFIL.md`).
11. Modo visita Pieza C: volver a la clase tras registrarse (`MODO_VISITA_pieza_A.md`).
12. Badge de packs (`BADGE_PACKS_pendiente.md`).
13. Keys legacy — **primer paso** nomás: publicar con la clave nueva, esperar adopción, y recién después desactivar la vieja (`SALIR_DE_KEYS_LEGACY.md`).

**Hallazgos del 24/8 probando en el teléfono** (los encontró la usuaria; los
tres son Dart puro, ninguno es un guard ni toca la base)

14. **(b) El listado de clases abajo del QR en Asistencia — REGRESIÓN.**
    `asistencia_screen.dart`, `_cargar()`. El Build 20 (`9459ffb`) arregló un
    bug real —antes hacía `from('clases')` sin filtro y traía clases de TODO el
    marketplace— pero de paso metió un filtro de **solo HOY**:
    `.where((c) => DateTime(f.year,f.month,f.day) == hoyDia)`.
    **Arreglo: borrar ese `.where`.** `getClasesDeEstudio(from: hoy)` ya recorta
    a hoy-en-adelante, que es justo lo que esperan los buckets.
    Prueba de que el filtro no era intencional: `_bucketDeClase` devuelve
    `'proximas'` y la UI (líneas 1734-1744) dibuja una sección **PROXIMAS** que
    nunca puede tener nada. Sección muerta desde el Build 20; el selector
    AHORA/HOY/PROXIMAS se había escrito en `8738f70` para mostrar futuras.
    Medido el 24/8: **6 de los 11 estudios tienen 0 clases hoy** ⇒ lista vacía.

15. **(c) La hoja de detalle de clase no muestra la descripción.**
    `_ClaseDetalleSheet` en `mis_clases_screen.dart:5803`. El tap anda
    (`onTap → _showClaseSheet`); lo que falta es dibujar. La hoja solo renderiza
    fecha, instructor, cupos, duración y créditos: **nunca lee**
    `clase['descripcion']`, `clase['incluye']` ni `clase['instructor_descripcion']`,
    aunque `getClasesDeEstudio` hace `.select()` y los tres ya vienen en el mapa.
    **Arreglo: agregar las filas.** No hace falta tocar la query.

16. **(a) No existe la pantalla de lista de espera del ESTUDIO.**
    El estudio no puede ver quién está esperando. Son dos cosas:
    · **Datos:** `lista_espera` tiene una sola policy, `waitlist_own`
      (`auth.uid() = usuario_id`), así que el estudio consultándola recibe 0
      filas. La policy abierta `waitlist_count_public` se cerró **bien** en
      `LISTA_ESPERA_TANDA1.sql` (exponía el `usuario_id` de todas a cualquiera)
      y dejó la RPC `waitlist_count`, que devuelve el número sin identidades.
    · **UI:** `WaitlistService` solo se usa en `detalle_clase_screen.dart`, que
      es la pantalla de la ALUMNA. El panel del estudio no tiene nada.
    **Arreglo: construir la UI sobre `waitlist_count`.** Si además se quiere
    mostrar *quiénes* esperan, eso necesita una RPC nueva —no reabrir la
    policy—, y es decisión de producto (ver las 3 de abajo).

17. **Que el panel no le muestre al estudio el error crudo de Postgres.**
    Lo que hizo feo el incidente del 24/8: YN Pilates vio en pantalla
    `PostgresException, message: "no autorizado", code: P0001`. Un estudio no
    puede hacer nada con eso, y encima asusta.
    Tres puntos en `mis_clases_screen.dart`:
    · **1237** — el `catch` del `Future.wait` de `_loadStudio` hace
      `_error = e.toString()`. Es el que se vio el 24/8.
    · **1168** — `_error = 'Error al generar clases: ${e.toString()}'`.
    · **1250 y 2006** — `_openForm` y `_openGridForm` llaman a
      `_loadCategoriasDisponibles()` **sin `try/catch`**: ahí la excepción sube
      pelada, ni siquiera hay cartel.
    **Arreglo:** mensaje humano — *"Hubo un problema al cargar. Escribinos a
    aura.hola.app@gmail.com"* — y el detalle técnico a `debugPrint`, que es el
    patrón que el mismo archivo ya usa al guardar (ver el `catch` del alta de
    clase, con su comentario explicando por qué). Barato, y evita que el
    próximo error de base asuste a un estudio.
    Ojo: **no tapar el error**, solo traducirlo. El texto crudo tiene que
    seguir yendo a `debugPrint` o no se puede diagnosticar nada.

18. **Borrar los dos inserts muertos a `notificaciones_usuario`.**
    El cliente intenta crear campanitas para OTROS usuarios. `notificaciones_usuario`
    no tiene policy de INSERT, así que RLS los rechaza **siempre** con 42501 y el
    `catch (_) {}` se lo traga. Además ahora los crea la base, así que si RLS
    los dejara pasar **duplicarían** el aviso:
    · `estudio_admin_service.dart:581` — campanita de lista de espera. La crea
      `_waitlist_promote_interno` desde el 22/8.
    · `reservas_service.dart:593` — aviso "❌ Clase cancelada". La crea
      `estudio_cancelar_clase` desde el 24/8.
    **Arreglo: borrarlos.** No hay que reemplazarlos por nada.

19. **Paralelizar la carga de "ver un estudio" (y de paso limpiar 2 cosas).**
    Medido el 24/8 a raíz de que la web se sentía lenta (~4 s en abrir un
    estudio). **No era la base**: server-side la apertura del panel más pesado
    (Citra, 368 clases) tarda **53 ms**. El costo real es la red: **una sola
    ida y vuelta a Supabase mide entre 150 ms y 1,6 s**, muy variable — por eso
    "antes era más rápido" depende del momento, no del código.
    `DetalleEstudioScreen._cargar()` hace **8 idas y vueltas EN SERIE**, sin
    `Future.wait`: getEstudio · getClasesDeEstudio (clases + reservas) ·
    getExperienciasDeEstudio (clases + reservas otra vez) · esFavorito ·
    getReviewsForStudy · canReviewStudy. Ocho por ~250 ms son 2 s; con dos
    muestras lentas te vas a 4 y pico.
    **Arreglo: `Future.wait`.** Pasan de sumarse a costar lo que la más lenta.
    Es la mejora de performance más grande disponible y es barata.
    · **Vale la pena también:** `_conOcupacion` consulta `reservas` **dos
      veces** —una para clases y otra para experiencias— donde una sola
      alcanza. Es 1 de las 8; se va gratis al paralelizar.
    · **Evaluado y NO vale la pena hoy:** el índice faltante en
      `horarios_fijos(estudio_id)`. Con 70 filas el planner hace seq scan y es
      más rápido que un índice. Anotado para cuando la tabla crezca.
    · **Aparte, decisión de producto:** `_loadStudio` llama a
      `generar_clases_estudio` en **cada** apertura del panel (24 ms de
      servidor para Citra, 207 búsquedas de existencia, más una ida y vuelta).
      Funciona, pero conviene decidir cuándo debe regenerarse la grilla en vez
      de hacerlo siempre.

**3 decisiones de producto antes de tocar código:** cuál "gratis" gana · si el
cartel de espera muestra la posición exacta · si debe existir el mail de
confirmación de reserva.

## 📘 Para el instructivo de los estudios

Material ya relevado y verificado contra la base. Falta redactarlo y darle
formato; el contenido está.

**Cómo editar**

> **Clase suelta.** Tocá la clase en "Clases cargadas" y apretá **Editar**.
> Podés cambiar todo, incluidos **fecha y hora**. Si subís los cupos, la lista
> de espera se promueve sola.
>
> **Grilla (horario fijo).** Editala tranquila: la profe, el nombre, los cupos,
> los créditos y también **el día y la hora**. Todas las clases futuras ya
> publicadas se actualizan y se mueven solas; las que ya pasaron no se tocan.
> Si el horario nuevo cae en otra franja, el precio se ajusta solo.
>
> **Workshop / experiencia.** Se edita como una clase suelta: nombre, profe,
> fecha, hora, cupos y precio. ⚠️ La **descripción larga, la dirección y los
> organizadores** todavía no se pueden editar — para cambiarlos hay que
> borrarlo y volver a crearlo. (Se arregla en el build, item 15.)

**FAQ — “¿Por qué me figura en la liquidación una clase que todavía no pasó?”**

> Porque el crédito ya se descontó. Cuando una alumna reserva, sus créditos
> salen de su cuenta en ese momento, no el día de la clase. Por eso la reserva
> entra en tu liquidación apenas queda **confirmada**.
>
> Si la alumna cancela **dentro del plazo** (12 horas antes por defecto), la
> reserva pasa a cancelada, ella recupera sus créditos y **deja de figurar**.
> Si cancela tarde o no viene, la reserva sigue contando y vos la cobrás.
>
> Los estados que se liquidan son: confirmada, presente, ausente y completada.
> No se liquidan: cancelada ni cancelada por el estudio.

**Qué NO se puede hacer, y por qué** (por si un estudio pregunta)

> · **Borrar una clase con alumnas anotadas.** Hay que cancelarla primero: así
>   les devolvemos los créditos y les avisamos. Después sí se puede borrar.
> · **Borrar una clase que ya tomaron.** Queda como registro de cobro.
> · **Marcar asistencia antes de tiempo.** Se puede marcar recién cuando la
>   alumna ya no puede cancelar (12 h antes por defecto). Si no, se le trabaría
>   la cancelación y perdería créditos que le corresponden.

## ⬜ Tanda D — Modelo C de precios

**Arrancar por el DISEÑO de las reglas, no por el código.** Es feature de
diseño. Ver "FEATURES EN DISEÑO" abajo y `aura-running-club-caso-de-uso-modelo-c`
en memoria.

## ⬜ Tanda E — experiencias, esquema pesado y el resto

- **Experiencias** con buscador y categorías (⚠️ hay **cero experiencias futuras**: decidir si el cuello es descubrimiento u oferta).
- 🔴 **Preservar facturación — SUBE DE PRIORIDAD por el alta de Rock Studio.**
  12 tablas con CASCADE desde `usuarios`, incluidas `pagos` y `reservas`.
  Confirmado abierto en la auditoría. **Y hay un segundo CASCADE, medido el
  24/8:** `reservas.clase_id` es `ON DELETE CASCADE`, así que borrar una clase
  se lleva puestas sus reservas — incluidas las **`completada`**, que son la
  evidencia de lo que se le debe al estudio.
  El 24/8 se cerró el camino de todos los días con
  `trg_clases_bloquear_borrado`: no se puede borrar una clase que tenga
  reservas en `confirmada`, `pre_confirmada`, `presente` **ni `completada`**
  (`FIX_NO_BORRAR_CLASE_CON_ANOTADAS_2026-08-24.sql`). Las `cancelada` sí se
  pueden borrar.

  **¿Hace falta igual romper el CASCADE? SÍ — pero ya no por las clases.**
  El candado tapa al estudio borrando clases desde el panel. Quedan **dos
  caminos que no pasan por él**, medidos el 24/8:
  1. **La alumna borrando su cuenta.** `reservas.usuario_id` es CASCADE desde
     `usuarios`, y la edge function `delete-account` corre con service_role
     —exenta por la guarda de `current_user`— y encima borra reservas a mano
     (`index.ts:216`). Medido: borrar a Male se lleva sus **2 reservas**,
     incluida la `completada` de **18 créditos facturados a Citra**. Este es el
     riesgo original de [[aura-cascade-borra-deuda-estudio]], y sigue intacto.
  2. **`admin_delete_estudio`**, exento a propósito (borrar un estudio entero
     es deliberado y tiene su confirmación).

  **Números al 24/8:** 552 ids de reserva asignados y 5 filas vivas ⇒ **547
  reservas borradas**; 2520 ids de clase y 1019 vivas ⇒ ~1500 clases borradas.
  **El arreglo de fondo** es que la reserva sobreviva a la baja de la usuaria:
  `on delete set null` en `reservas.usuario_id` con los datos mínimos copiados
  (email/nombre al momento), o una tabla de historial de facturación. No
  bloquea el alta de Rock Studio, pero conviene antes de que facture en serio.
- **Firma del webhook de MP** — se calcula y se descarta; mitigado porque después verifica contra la API.
- **Policy DELETE en `storage.objects`** — no existe para ningún bucket.
- **Log de cambios de estado en `reservas`** — decisión del 22/8: no ahora. Retomar cuando la liquidación mueva plata real.
- **UI para editar packs** — `upsertPricingPack()` existe y ninguna pantalla lo llama; hoy sólo por SQL.

## ❓ Preguntas abiertas

**¿Archivar o borrar las clases muy viejas (1-2 años) para no acumular?**
Decisión de la usuaria **con su contadora**: cuánto tiempo hay que guardar.
La parte técnica es un cron de pocas líneas, pero **la forma importa**:
- ✅ **Recomendado: archivar, no borrar.** Una columna `archivada` (o
  `estado='archivada'`) en `clases`: desaparecen de todas las vistas pero la
  fila y sus reservas quedan intactas. Cero riesgo contable.
- ⚠️ **Borrar de verdad, solo después de romper el CASCADE** (Tanda E). Hoy
  borrar una clase vieja se lleva sus reservas `completada`, que son la
  evidencia de cobro. Además el candado del 24/8 justamente impide borrarlas,
  así que un cron tendría que correr con service_role para saltearlo — y ahí
  volvés a perder la facturación.
- ❌ **Lo que NO hay que hacer:** un borrado automático con el CASCADE como
  está. Sería el bug que tapamos el 24/8, pero automatizado.

## ⬜ Pendientes de NEGOCIO — los sigue la usuaria

No son tareas técnicas. Están acá para que no se pierdan.

| | Qué | Cuándo |
|---|---|---|
| 🔴 | **Qué pasa con las alumnas ya anotadas cuando el estudio mueve una grilla** | **Antes del 13/9** (cuando arranquen las reservas reales). Desde el 24/8 editar el día/hora de una grilla **mueve** las clases futuras, que es lo correcto — pero eso le cambia el horario a quien ya se anotó. Hoy no muerde: medido, **0 clases futuras de grilla con reservas activas**. Opciones: **(2) mover + campanita automática** —la preferida por la usuaria, y el patrón ya existe desde el aviso de cancelación— o **(3) rechazar el cambio si hay anotadas**. Ver `FIX_GRILLA_MOVER_CLASES_2026-08-24.sql`. |
| ⬜ | **Avisar el fin de la gracia** | **Citra el 13/9.** 6 estudios entre el 13/9 y el 30/9. Transición automática; falta la conversación. |
| ⬜ | **¿Los usuarios deberían recibir mail de confirmación de reserva?** | `email-confirmacion` existe en el repo y **nunca se deployó**. Decisión de producto. |
| ⬜ | **Categorías faltantes** | Avisarle a Yessi (112 clases) y Ambra (77) que las completen. O que el form las exija (Dart). |

## ⬜ Mantenimiento

Sanear los docs de esta carpeta · escribir el doc de eventos gratis (no existe;
ya hay material: la medición end-to-end con saldo 0 está hecha).

---

## 💡 Cosas aprendidas que conviene no volver a descubrir

- **La trampa del `config.toml`:** aparecio dos veces. Una edge function no
  declarada ahi cambia su `verify_jwt` en silencio al deployar. Quedaron
  declaradas `aviso-cobro-manana`, `reporte-mensual-estudios`,
  `aviso-alumnos-email` y `email-regalo`. **Chequear antes de cada deploy.**
- **Arranque en frio:** la primera invocacion despues de un deploy corta a los
  5s por el default de `pg_net`. No rompe el cron; para ver la respuesta hay
  que pasar `timeout_milliseconds := 30000`.
- **Las 2 funciones de mail a estudios aceptan `{"dry_run": true}`**: arman el
  reporte y devuelven a quien le habrian escrito, sin mandar mail.
- **No hay UI para editar packs.** `upsertPricingPack()` existe en
  `admin_service.dart:662` y ninguna pantalla lo llama: hoy un pack suelto solo
  se cambia por SQL. Ojo, subir el valor del credito desde `/admin/config` **ya
  recalcula los 4 packs solo**; la UI haria falta solo para un precio que no
  salga de la formula.

## 📋 Como cambiar precios — referencia

| Que | Donde | Que hace |
|---|---|---|
| **Valor del credito** | `/admin/config` | `admin_set_valor_credito_ars`: en UNA transaccion escribe `configuracion_global`, **recalcula los 4 packs** y actualiza el `valor_credito` de los 9 estudios. Por eso no puede desincronizar. |
| **Precio de un estudio** (fijo o pico/valle) | Backoffice → Estudios → el estudio → **Precios** | `admin_set_pricing_estudio` + recalculo de sus clases |
| **Precio de un pack puntual** | ⚠️ solo por SQL | `admin_upsert_pricing_pack`, sin pantalla |

⚠️ **`ConfiguracionScreen` (`lib/screens/perfil/configuracion_screen.dart`) NO
tiene nada que ver con precios**: es la pantalla de ajustes de la usuaria
(notificaciones). **No tocarla.** Lo huerfano era el metodo
`updateGlobalCreditValue`, anotado en DART_PENDIENTE item 5.

---

# FEATURES EN DISEÑO

## 1. Modelo C de pricing — la excepción de precio

**Decidido el 22/8.** Precio automático por franja (ya funciona) **más una
excepción explícita que sólo Aura puede levantar**.

**El caso de uso concreto que lo vuelve necesario: el running club gratis.**
Clase recurrente y gratis, hoy imposible de cargar — y **no por los arreglos de
esta tanda**: la bloquea el trigger de precio, que pisa `creditos` con el
precio del estudio. Probado: pedir una clase en 0 en Citra dejó 18.
Configurarle precio al estudio no ayuda; es justamente lo que le pone precio.

Las tres salidas de hoy y por qué ninguna sirve:
- **Como experiencia a 0 pesos:** anda ya, pero los workshops **no pueden
  repetirse** y caen en Experiencias, no entre las clases.
- **Por SQL:** anda, pero el cron de las 03:00 crea la semana nueva del borde a
  precio del estudio. Se vuelve pago de a una semana por vez.
- **Modelo C:** la buena.

⚠️ Al diseñarlo: la excepción tiene que admitir cero y ser respetada por los
**dos** triggers **y** por `generar_clases_estudio`, si no el cron la pisa.

Quedan además **7 decisiones de borde** (clases al límite de franja, estudios
sin valle, recálculo del pasado, etc.) en el documento de pricing.

## 2. Experiencias: categorías y buscador propios

Sólo lado **usuario** (descubrir), nunca lado estudio (cargar) — el botón de
cargar está escondido a propósito por el 15% vs 30%.

Lo medido:
- Las experiencias **son `clases` con `tipo='workshop'`**: misma tabla, mismas
  reservas, **y ya usan el mismo `categorias text[]`**. A nivel dato no hay
  nada que construir.
- Explorar **las excluye** (`clases_service.dart:23`).
- **El filtro de categorías filtra ESTUDIOS, no clases** — es el habilitador
  que falta, y para experiencias es bloqueante (la categoría de un taller de
  cerámica nunca coincide con la del estudio de yoga).
- 190 de 589 clases futuras no tienen ninguna categoría.
- Las experiencias son las únicas con foto propia (9 de 589 clases tienen
  imagen; la única experiencia tiene foto, galería y descripción larga).
- ⚠️ **Hay una sola experiencia futura en toda la base.** Un buscador sobre un
  item no se puede evaluar. Decidir si el cuello es descubrimiento u oferta.

## 3. Running clubs como categoría dentro de clases

`Running` y `GRATIS` **ya existen** en `study_categories`. Pero hoy son chips
muertos: ningún estudio los tiene y el filtro mira estudios. Bloqueado por el
mismo habilitador que las experiencias, más el Modelo C para el precio 0.

## 4. Cartel de "clase gratis" + consumo aparte

Reusar el slot de `detalle_clase_screen.dart:736` (la tarjeta verde de "Reserva
gratuita"), resolviendo la precedencia contra `_esGratuita`, que significa otra
cosa (alumno del estudio en modo gestión, por usuario y no por clase).
Más una nota corta del estudio para el café de después, con prefijo fijo de
Aura. **El badge tiene que estar en el listado, no sólo en el detalle**, o se
lee como carnada.

---

# PASO 1 — Verificación de mail (viene de la Sesión 1)

`mailer_autoconfirm = true`: hoy cualquiera se registra con un mail que no es
suyo y queda confirmado al instante.

**Cierra tres caminos de plata** (hoy en cero, pero se arman solos):

| Camino | Mecanismo | Se activa cuando |
|---|---|---|
| Créditos corporativos | `trg_vincular_usuario_empresa` → `grant_user_credits` por dominio | sumes la primera empresa |
| Reservas gratis | `reservar_clase`: estudio en modo `gestion` + mail en `estudio_alumnos` ⇒ 0 créditos | un estudio pase a modo gestión |
| Gift cards | `canjear_regalo` valida contra `auth.users.email` | haya gift cards sin canjear |

### ⚠️ Por qué no es sólo tocar el toggle

**La app tiene que manejar el estado "registrado sin confirmar".** Hoy asume que
el login post-registro funciona directo. Si no lo maneja, **rompés el registro
para todos los usuarios nuevos.**

### Medir primero, con el toggle apagado

1. `register_screen.dart`: ¿qué hace si `signUp` devuelve `session == null`?
2. ¿Existe pantalla o cartel de "revisá tu mail"? Si no, hay que hacerla (build).
3. ¿Qué pasa si alguien intenta loguearse sin confirmar? (`email_not_confirmed`)
4. OAuth no se ve afectado: llega con el mail verificado. Confirmarlo.
5. `emailRedirectTo` → `AppConstants.auraWebUrl`, y en la allowlist.

---

# Más adelante

- **`PRESERVAR_FACTURACION.md`** — cambio de esquema, el más pesado
- **`SANEAR_ESTOS_DOCS.md`** — mantenimiento de esta carpeta
- **Devoluciones y vencimiento** — 5 reglas distintas + créditos eternos.
  Postergado al build 22 a propósito, **no re-proponer**
- **Avisar el fin de la gracia** — 5 estudios empiezan a pagar 30% el 1/10/2026
- **Último admin de un estudio** — mejora de prioridad baja, no re-proponer

---

# Estado del repo al cerrar (2026-08-22)

**Todo lo de esta sesión ya está aplicado en producción**: 10 migraciones de
base, la limpieza de reservas de prueba y 5 edge functions deployadas. Los
archivos del repo son el registro, no la fuente.

Chequeo de cierre corrido contra la base: los 13 arreglos en pie, y los datos
idénticos a la referencia (885 clases, 70 horarios, 5 reservas, 9 estudios,
0 desvíos de precio, 0 de etiqueta, 0 créditos eternos, 0 basura de prueba).

⚠️ **Verificar siempre contra la base, nunca contra los archivos ni contra las
notas.** Acá las migraciones se aplican a mano, así que un `.sql` en el repo no
prueba que esté aplicado. Usar `pg_get_functiondef` / `pg_trigger` /
`pg_constraint` / `information_schema`. Ver `aura-sql-produccion-management-api`
en memoria.

Esta sesión hubo **cuatro** conclusiones equivocadas, todas con la misma forma:
medir un eje y concluir sobre todos. Un archivo en vez de la base (los triggers
de precio), un array en vez de la cadena de llamadas (los packs "bloqueados"),
el apex en vez del subdominio (el SPF), y una consulta que no distinguía "falta
el CHECK" de "falta la columna" (`estudios.estado`). La última fue sobre una
nota escrita el mismo día. **Una nota no se vuelve falsa con el tiempo: nace
incompleta.**

Plan completo con las 8 áreas y el orden:
https://claude.ai/code/artifact/85e0bcd6-dc65-4912-aae2-40371ad2e618
