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
| 🔴 | **Auditar la tanda de guards del 20/8 entera** | **lo primero** · se validó mal (ver abajo) |
| ⬜ | **Tanda C** — build de Dart (18 items) | **lo próximo** · bloqueada por saber si el build 25 se subió |
| ⬜ | **Tanda D** — Modelo C de precios | arrancar por el DISEÑO de reglas, no por código |
| ⬜ | **Tanda E** — experiencias, esquema pesado, keys legacy | |
| ⬜ | **Negocio** (los sigue la usuaria) | aviso del fin de gracia · mail de confirmación |

### ⚠️ Lo primero al retomar

**🔴 Auditar los 5 guards del 20/8 con el criterio de LAS DOS PUNTAS.**
`FIX_GUARDS_CUERPO.sql` (commit `f4ba3dd`) se verificó midiendo **solo si el
exploit quedaba cerrado**. Nunca se midió que el usuario legítimo siguiera
pudiendo llamar la función. **Dos de los cinco estaban rotos en producción** y
nadie lo vio durante 4 días, porque la verificación se hizo con
`test@aura.com`, que es superadmin y satisface `is_admin()`.

Los 4 arreglos ya salieron el 24/8 (ver abajo), pero **la lección aplica a toda
la tanda y a las que vengan**: ningún guard cuenta como verificado hasta probar
que un estudio real, una profe y una alumna común siguen pudiendo hacer su
trabajo. **Probar SIEMPRE con una cuenta de estudio real, nunca con
`test@aura.com`.** Falta repasar con este criterio el resto de las funciones
endurecidas en `FIX_AMARILLAS_AUDITORIA.sql` (la tanda de grants anterior), que
tiene el mismo problema de origen.


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

Queda para el build el item 18: borrar los dos inserts muertos del cliente. La dueña y la profe pasan; la usuaria ajena no.

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

**3 decisiones de producto antes de tocar código:** cuál "gratis" gana · si el
cartel de espera muestra la posición exacta · si debe existir el mail de
confirmación de reserva.

## ⬜ Tanda D — Modelo C de precios

**Arrancar por el DISEÑO de las reglas, no por el código.** Es feature de
diseño. Ver "FEATURES EN DISEÑO" abajo y `aura-running-club-caso-de-uso-modelo-c`
en memoria.

## ⬜ Tanda E — experiencias, esquema pesado y el resto

- **Experiencias** con buscador y categorías (⚠️ hay **cero experiencias futuras**: decidir si el cuello es descubrimiento u oferta).
- **Preservar facturación** — 12 tablas con CASCADE desde `usuarios`, incluidas `pagos` y `reservas`. Confirmado abierto en la auditoría.
- **Firma del webhook de MP** — se calcula y se descarta; mitigado porque después verifica contra la API.
- **Policy DELETE en `storage.objects`** — no existe para ningún bucket.
- **Log de cambios de estado en `reservas`** — decisión del 22/8: no ahora. Retomar cuando la liquidación mueva plata real.
- **UI para editar packs** — `upsertPricingPack()` existe y ninguna pantalla lo llama; hoy sólo por SQL.

## ⬜ Pendientes de NEGOCIO — los sigue la usuaria

No son tareas técnicas. Están acá para que no se pierdan.

| | Qué | Cuándo |
|---|---|---|
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
