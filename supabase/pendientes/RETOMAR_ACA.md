# 👉 RETOMAR ACÁ

**ESTADO:** abierto · **Verificado contra la base:** 2026-08-22

Punto de entrada de la próxima sesión. Único lugar donde viven los pendientes.
Escrito para arrancar sin re-pensar.

---

# ✅ PASO 0 — AUDITORÍA COMPLETA: HECHA (2026-08-22)

Las 8 áreas medidas contra la base. **Resultado: la base está sana.** Las áreas
de plata directa —pricing, reservas, RLS— resistieron todo, incluidos 6
exploits corridos con el JWT del dueño real de una reserva.

| Área | Estado |
|---|---|
| 1 · Pricing (5 arreglos del 22/8) | ✅ todo en pie |
| 2 · Farmeo del vencimiento | ⚠️ **fuga lateral** |
| 3 · Foto de perfil | ⚠️ correcta pero **nunca ejercitada** |
| 4 · Vencimiento de packs | ✅ ok |
| 5 · Escritura de reservas | ✅ 6/6 exploits bloqueados |
| 6 · CASCADE de usuarios | ⚠️ **confirmado abierto** |
| 7 · Los 6 crons | ✅ con asterisco |
| 8 · Storage y RLS | ✅ muy bien |

**Lo que se confirmó bien:** triggers y CHECK de pricing en pie con 0 clases
desviadas; 6 de 6 exploits de reserva bloqueados (bajar el precio, auto-
cancelarse, cambiar el QR, mover la reserva, borrarla, crear una gratis); todas
las tablas públicas con RLS y todo lo sensible invisible para un anónimo —los
CBUs ni llegan a RLS, dan `permission denied` a nivel de grant—; y cero fallas
de cron después del 21/8.

## Los 6 hallazgos nuevos — **3 ya resueltos**

1. ✅ **RESUELTO (22/8) · Fuga en `admin_adjust_user_credits`.** Es la única función que escribe en
   `creditos_movimientos` sin pasar por `grant_user_credits`, y mete
   `expires_at = null` hardcodeado: **cada crédito regalado a mano no vence
   nunca**. Hay 5 movimientos eternos, todos `source='manual'`, todos previos
   al fix, con **29 créditos vivos** (20 de `julietarey2002@gmail.com`).
2. ⬜ **Va al build de Dart · La foto de perfil nunca se ejercitó.** Policies y buckets correctos
   (`{userId}/...`, 10MB, `image/*`), pero **0 archivos y 0 `avatar_url`**.
   Está bien configurada; no está probada.
3. ⬜ **No hay policy de DELETE en `storage.objects`** para ningún bucket. El
   servidor borra (service_role saltea RLS), el cliente no.
4. ✅ **RESUELTO (22/8) · Los 3 crons mensuales no corrieron desde el fix.** Verificados en la Tanda 0; uno estaba roto y se arreglo. Últimas ejecuciones el
   1/8 y el 4/8, *antes* del 21/8. Y dos de ellos son los que le mandan mails a
   los estudios, con próxima corrida pegada al inicio del cobro.
5. ✅ **RESUELTO (22/8) · `pack_credits_expiration`** estaba muerta con 3 sobrecargas de tipos
   ambiguos y cero llamadores.
6. ⬜ **Va en Tanda A (datos) · `vigencia_dias`** no se actualiza en `admin_upsert_pricing_pack`, así que
   se desincroniza de `vencimiento_dias` al editar un pack.

**El patrón que comparten los tres con sustancia:** son puertas laterales que
quedaron abiertas cuando se cerró la principal — el grant manual junto al
farmeo, el `delete-account` junto al cascade, y el `tipo` junto al precio.
Reflejo para la próxima: **cuando cierres un camino, buscá quién más escribe en
la misma tabla.**

## Números de referencia (22/8, post-auditoría)
885 clases · 70 horarios fijos · 5 reservas (4 canceladas) · 9 estudios ·
0 experiencias futuras · 0 clases desviadas de la regla · rangos 11–50 y 11–18 ·
78 usuarios · 6 pagos aprobados por $84.220.

---

# 🔴 ORDEN DE ARREGLO

> **Estado al 22/8:** Tanda 0 ✅ cerrada (lo tecnico) · Tanda A ⬜ **4 de 9**
> Los items de NEGOCIO estan al final, separados: los sigue la usuaria, no son
> tareas tecnicas.

---

## ✅ Tanda 0 — CERRADA

| | Que | Resultado |
|---|---|---|
| ✅ | Los 3 crons mensuales | Verificados. `acreditar-creditos-corporativos` corrido de verdad (200 OK, `{empresas:0}`), con lo que quedo probado el camino cron → Vault → edge, identico en los tres. **`aviso-cobro-manana` estaba ROTO**: pedia `reservas.estudio_id`, que no existe, y fallaba en silencio con un 200. Arreglado y deployado. |
| ✅ | Correo | Resuelto **sin tocar DNS**. El SPF ya existia en `send.somosaurapass.com`; lo unico roto era que `hola@somosaurapass.com` no recibe. Se cambio el pie de los mails a `aura.hola.app@gmail.com` (que ya usaban la app y la web) y se sumo `reply_to` en las 6 funciones. |

---

## ⬜ Tanda A — el barrido de base · **8 de 9**

### Hechas

| | Que | Migracion |
|---|---|---|
| ✅ | **Fuga de `admin_adjust_user_credits`** — los creditos regalados a mano no vencian nunca. Parametro `p_dias` (default 90), compatible con la app sin build. Los 29 eternos resueltos: Julieta (clienta real) a 90 dias sin cambio visible para ella, las dos de prueba vencidas. **0 creditos eternos en toda la base.** | `20260822180000` |
| ✅ | **`ensure_referral_code` con `search_path`** — era la ultima sin blindar. **94 de 94 SECURITY DEFINER blindadas.** | `20260822190000` |
| ✅ | **Codigo muerto, 4 firmas** — `pack_credits_expiration` (3 sobrecargas ambiguas) y `admin_update_global_credit_value`. La nota vieja decia "0 llamadores" y era **falsa**: habia un wrapper en Dart. Se dropeo igual porque esta huerfano y porque asi falla con PGRST202 en vez de desincronizar en silencio. | `20260822190000` |
| ✅ | **`expires_at NOT NULL`** en `creditos_movimientos` — cierra la tabla para que no vuelvan los eternos por ningun camino, ni siquiera por SQL. Relevado antes: solo 2 funciones insertan y las 9 llamadas pasan vencimiento. | `20260822210000` |
| ✅ | **Etiquetas de la grilla** — `generar_clases_estudio` hacia `v_tipo := 'normal'` hardcodeado y esa rama corria SIEMPRE, asi que toda clase generada nacia mal etiquetada. Se arreglo la funcion y DESPUES se backfillearon las 72 de Sculpt (54 valle, 18 pico). Creditos sin tocar. Probado simulando el cron: 41 clases nuevas, 0 mal etiquetadas. | `20260822210000` |
| ✅ | **El estudio no puede resucitar reservas canceladas** — podia dar vuelta `cancelada` → `presente` e inflar su propia liquidacion (`presente` es liquidable). Guarda quirurgica en el trigger que ya existia: el escaner completo sigue andando, incluido el "deshacer". Se complementa con el arreglo del indice: la alumna puede re-reservar. | `20260822230000` |
| ✅ | **`vigencia_dias` espejada** — el upsert de packs escribia solo `vencimiento_dias` y la primera edicion por RPC las hacia divergir. Ahora escribe las dos. **Ojo: el "item 7 · datos" del plan estaba mal descrito** como 3 correcciones de data rota; resultaron ser 3 cosas distintas (ver abajo). | `20260822220000` |
| ✅ | **Indice `reservas_usuario_clase_uidx`** — excluia solo `'cancelada'` cuando hay DOS estados muertos. Sintoma: "ya reservaste" en una clase que el estudio te habia cancelado. | `20260822200000` |

### Faltan — 5

| | Que | Nota |
|---|---|---|
| ⬜ | **`estudios.estado` sin CHECK** | Lo que queda del item de whitelist. Es el mas chico: acepta cualquier string. Va DESPUES del de reservas, ya hecho. |
| ⬜ | **Columna fantasma** `clases."lugares_ disponibles"` (con espacio) | La columna se borra en base ahora; las **8 referencias del Dart** esperan al build. |


### ⬜ Pendiente nuevo — log de cambios de estado en `reservas`

`reservas` **no tiene historial de cambios de `estado`**. La guarda del
22/8 PREVIENE que un estudio resucite una reserva cancelada, pero sin log no
hay forma de DETECTAR abuso a posteriori por otros caminos.

**Decision de la usuaria (22/8): no ahora.** Hoy prevenir alcanza — 6 estudios
reales, todos conocidos, y la liquidacion practicamente no mueve plata todavia
(1 reserva facturable en total). Retomar cuando haya volumen real.

### ⚠️ El "item 7 · datos" no existia como tal

El plan lo describia como "3 correcciones de data rota". Aplicando el filtro
—¿es decision del estudio, o data rota que nadie decidio?— resultaron ser tres
cosas de naturaleza distinta:

| | Que era en realidad | Que se hizo |
|---|---|---|
| **7a** · 189 clases sin categoria | **Decision del ESTUDIO.** Se verifico que la propagacion de la grilla funciona: correlacion perfecta en 30 horarios fijos, los que tienen categoria se la pasan a sus clases y los que no, no. No es un bug del sistema: son estudios que no la cargaron. | **FRENADO.** Las categorias las eligen los estudios, clase por clase. No se rellenan por ellos. |
| **7b** · `creditos_por_categoria` | **Archivo historico a proposito.** La migracion `20260721180000` dice: "la dejamos en configuracion_global por si hay que auditarla". | **SE DEJA.** Borrarla seria revertir una decision, no corregir un error. |
| **7c** · `vigencia_dias` | **Riesgo real** sobre una decision ya tomada: se eligio conservar la columna igualada, pero el upsert no la escribia. | **HECHO.** `20260822220000`. |

**Lo accionable de "los datos" era una sola linea.**

💡 Pero salio un pendiente de producto: **el formulario de grilla NO exige
categoria.** El widget muestra "Elegi al menos una" como sugerencia y la unica
validacion al guardar es que el nombre no este vacio. Por eso hay 189 clases
sin categoria: el sistema lo deja pasar en silencio y el estudio no se entera
de que importa. Dos caminos, los dos de la usuaria: que el form la exija (Dart,
al build) o avisarle a Yessi y Ambra que las completen desde su panel.

💡 Y un detalle cosmetico: **24 clases de Yessi se llaman "Fumcional"**, con
eme. Typo del estudio, visible para las usuarias.

---

## ⬜ Pendientes de NEGOCIO — los sigue la usuaria

No son tareas tecnicas. Estan aca para que no se pierdan, no para que alguien
las tome.

| | Que | Cuando |
|---|---|---|
| ⬜ | **Avisar el fin de la gracia** | Citra el **13/9**. 6 estudios entre el 13/9 y el 30/9. La transicion es automatica; falta la conversacion. Ver `aura-avisar-fin-de-gracia` en memoria. |
| ⬜ | **¿Los usuarios deberian recibir mail de confirmacion de reserva?** | `email-confirmacion` existe en el repo con su `reply_to` puesto, pero **nunca se deployo**. Hoy no reciben ese mail (si ven la reserva y el QR en la app). Es decision de producto, no se sube solo porque el archivo existe. |

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

## ⬜ Tanda B — verificación de mail
Va **antes** del build: probablemente necesite una pantalla de "revisá tu mail",
y descubrirlo después es perder el release. `mailer_autoconfirm = true`
confirmado. **Medir antes de tocar el toggle** o rompés el registro de todos.

## ⬜ Tanda C — el build de Dart (todo junto, un release)
Encabeza **el texto de "gratis"** (captación). Detalle completo en
`DART_PENDIENTE_proximo_build.md`. Sumar de la auditoría: **probar que la foto
de perfil funcione de verdad**, porque no hay un solo archivo subido.

## ⬜ Tanda D — Modelo C → destraba los running clubs
Ver `aura-running-club-caso-de-uso-modelo-c` en memoria. La excepción tiene que
admitir cero y ser respetada por los **dos** triggers **y** por
`generar_clases_estudio`, o el cron la pisa.

## ⬜ Tanda E — experiencias, esquema pesado y el resto
Experiencias (⚠️ hay **cero experiencias futuras**: decidir si el cuello es
descubrimiento u oferta), preservar facturación (12 tablas CASCADE, incluidas
`pagos` y `reservas`), keys legacy (sólo queda la `anon` de la app), y la firma
del webhook de MP.

## ⬜ Mantenimiento
Sanear los docs de esta carpeta, y escribir el doc de eventos gratis (no existe;
ya hay material: la medición end-to-end con saldo 0 está hecha).

---
# Lo que se cerró el 2026-08-22 — tanda de pricing

Los cinco aplicados en producción y verificados con tabla temporal + rollback,
las dos puntas cada uno. **Ninguna fila de producción se movió.**

| | Arreglo | Migración |
|---|---|---|
| 🔴 | Bypass del `tipo`: workshop caro → clase sin repreciar | `20260822140000_precio_cierra_bypass_tipo.sql` |
| 🔴 | Sin precio configurado no se cargan clases (se acabó el 10 escondido) | `20260822150000_precio_rechaza_estudio_sin_precio.sql` |
| 🟠 | CHECK de sanidad 0–500 en las dos tablas, validado | `20260822160000_precio_check_sanidad_creditos.sql` |
| 🟠 | Fuera el `default 10` de `horarios_fijos.creditos` | `20260822170000_precio_saca_default_10.sql` |
| 🟢 | Monitoreo de arbitraje de comisión (no bloquea) | `MONITOREO_arbitraje_workshops.sql` |

**Lo que quedó demostrado y conviene no re-discutir:**
- El pico/valle automático **ya funciona** en clases normales. El estudio no
  elige el precio: lo pone la regla según día y hora. Verificado sobre 884
  clases, 0 desvíos.
- Sculpt Club es el único en modo `rango` (valle 14 / pico 16, 30 franjas).
  Los otros 8 en modo fijo.
- **Un usuario con saldo 0 puede reservar un evento gratis de punta a punta**:
  reserva confirmada, QR, aparece en "mis reservas", cupo descontado, saldo
  intacto, 0 movimientos en el ledger. No hay ningún gate de pack ni de
  suscripción. Medido con un usuario real.

---

# Lo que se cerró el 2026-08-21

| | Fix | SQL |
|---|---|---|
| 🔴 | `reservas`: UPDATE libre + INSERT gratis | `FIX_RESERVAS_ESCRITURA_CLIENTE_2026-08-21.sql` |
| 🔴 | Borrado en cascada de `usuarios` | `FIX_TANDA2_2026-08-21.sql` |
| 🔴 | 5 crons con 401 (Vault) | `FIX_CRONS_VAULT_2026-08-21.sql` |
| 🔴 | Borrado de cuenta roto por gift cards | commit `120b956` |
| 🔴 | Farmeo del vencimiento + créditos eternos | `FIX_FARMEO_VENCIMIENTO_2026-08-21.sql` |
| 🟠 | Storage acotado + límites | `FIX_TANDA2_2026-08-21.sql` |
| 🟠 | Foto de perfil | `FIX_FOTO_PERFIL_2026-08-21.sql` |
| 🟠 | Vencimiento de packs a 90 días | `FIX_VENCIMIENTO_PACKS_2026-08-21.sql` |
| 🟠 | Tabla `resenas` legacy | borrada |

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

`main` sincronizado. **Todo lo de esta sesion ya esta aplicado en produccion**
(8 migraciones de base, la limpieza de reservas y 5 edge functions
deployadas); los archivos del repo son el registro, no la fuente.

⚠️ **Verificar siempre contra la base, nunca contra los archivos.** Acá las
migraciones se aplican a mano, así que un `.sql` en el repo no prueba que esté
aplicado. Usar `pg_get_functiondef` / `pg_trigger` / `pg_constraint`. Ese error
costó tres tropiezos esta semana. Ver `aura-sql-produccion-management-api`.

Plan completo con las 8 áreas y el orden:
https://claude.ai/code/artifact/85e0bcd6-dc65-4912-aae2-40371ad2e618
