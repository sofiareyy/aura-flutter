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
| ✅ | **Auditoría FRESCA de punta a punta** (cabeza limpia, sin mirar estas notas) | **hecha el 24/8** · 4 agujeros nuevos + 41 clases mal publicadas · **5 arreglos aplicados** |
| 🟢 | **Alta de Rock Studio** (spinning, 2 sedes, 50 bicis) | **LISTA.** Multi-sede verificado punta a punta el 24/8 con las 2 sedes. Ver abajo. |
| ✅ | **Incidente Tiwar 25/8** — "las clases se duplican / horarios raros" | **no era zona horaria**: reloj de 12 h en el panel + grilla cargada 2 veces como rango · guard aplicado · **limpieza de Tiwar espera confirmación del estudio** |
| ✅ | **Tanda C** — build de Dart | **cerrada 26/8 = build 26** (1.0.6+26), archivado y subido. El build 25 sí se había archivado el 21/8 (dos `.xcarchive`, `1.0.6 (25)`). |
| ⬜ | **Tanda D** — Modelo C de precios | arrancar por el DISEÑO de reglas, no por código |
| 🟡 | **Tanda E** — experiencias, keys legacy | **preservar facturación: la mitad urgente CERRADA el 26/8.** Queda el estudio dado de baja, que espera decisión con la contadora |
| ⬜ | **8 menores de la auditoría fresca** | ninguno urgente · re-medidos el 26/8, los 8 siguen abiertos |
| 🟢 | **Force-update** (`min_build_ios = 26`) | **ACTIVO a propósito** desde el 29/8 · builds 25 y 26 publicados · **no revertir** |
| ⬜ | **Negocio** (los sigue la usuaria) | aviso del fin de gracia |

### 🟢 FORCE-UPDATE ACTIVO en la 26 — decisión de Sofía (confirmada el 30/8)

**Estado real en producción, medido el 30/8:** `min_build_ios = 26`,
`min_build_android = 1`, policy `usuarios_select_alumnas_de_mis_clases`
**repuesta**.

**Es a propósito.** El cartel bloqueante es justamente el mecanismo para que
quien tenga una versión vieja se entere y actualice. **Los builds 25 y 26 están
publicados** en la App Store. **No revertir.**

⚠️ **Corrección a lo que decía este documento el 29/8.** La nota anterior
afirmaba que se habían revertido *dos* cambios. **Sólo se revirtió uno.**

| Cambio del 29/8 | Lo que decía la nota | Lo que pasó de verdad |
|---|---|---|
| `min_build_ios` = 26 | "revertido a 1" | ❌ **nunca se revirtió** — sigue en 26, y así se queda |
| policy de nombres cerrada | "repuesta" | ✅ correcto, la policy volvió |

El commit `bbce0ed` **sólo tocó este `.md`**: el `UPDATE` de `min_build_ios` a 1
jamás corrió. `min_build_android` está en 1 porque nunca se activó, no porque se
haya revertido. Se detectó el 30/8 midiendo `configuracion_global` contra las
notas.

**Alcance del gate** (`lib/services/version_gate.dart:56`, bloquea si
`instalado < minimo`):

- Builds **≤24 no tienen el gate** (nació el 21/08 00:49) ⇒ **no los alcanza**.
- Build **25 sí lo tiene** ⇒ ve el cartel de actualizar. **Ese es el efecto
  buscado.**
- **Web nunca se bloquea** (`kIsWeb` ⇒ `false`), y el gate es **fail-open**:
  error de red, timeout, fila ausente o valor ilegible ⇒ no bloquea a nadie.

### ✅ Lo que SÍ sigue vigente del 29/8: el error de método

Lo que se revirtió con razón fue **la policy de nombres**, y la lección de cómo
se midió sigue valiendo entera:

**El error:** se dedujo "usan web" de que `dispositivos` estaba vacía para los
estudios. Pero esa tabla **sólo registra a quien ACEPTÓ el permiso de push** —
no a quien usa la app.

**La señal correcta es `auth.sessions.user_agent`:**
- `Dart/3.11 (dart:io)` ⇒ **app nativa**
- `Mozilla/...` ⇒ **web**

**Medido: 5 estudios SÍ usaban la app nativa** — Citra, Sculpt Club, Ambra,
Barre Estudio (27/8) y YN Pilates (28/8). Y **ninguno tenía dispositivo
registrado**, lo que confirma que `dispositivos` no sirve como censo de uso.

**Por eso la policy sigue abierta:** un estudio en build 25 lee `usuarios`
directo (no la RPC), así que al cerrarla vuelve a ver "Usuario" en vez del
nombre de la alumna. **Esa mitad espera adopción, el force-update no.**

```sql
-- quién usa app vs web, y con qué versión si registró push
select u.email,
       case when s.user_agent ilike '%dart%' then 'APP' else 'WEB' end as cliente,
       s.updated_at,
       (select max(d.app_version) from public.dispositivos d where d.usuario_id=u.id) as version
  from auth.sessions s join public.usuarios u on u.id=s.user_id
 order by s.updated_at desc;
```

### 🚦 Semáforo de adopción — `supabase/pendientes/SEMAFORO_ADOPCION.sql`

Correr cada par de días. **Verde = seguro** (el build 26 registra push al abrir);
🔴 = usa la app y no dio señal de la 26; 🌐 = sólo web (nada que hacer, la web
siempre es la última).

**Estado al 30/8:** **YN Pilates ya está ✅ EN LA 26** (actualizó el 30/8 a las
14:50). Quedan **4 en 🔴** — Citra, Sculpt Club, Ambra y Barre Estudio, las
cuatro sin abrir la app desde el 27/8. Tiwar, Yessi y BB (x2) van por **web**.

Con el force-update activo, un 🔴 que abra la app **ve el cartel y actualiza**:
el semáforo pasa de ser una alerta a ser el seguimiento de esa transición.

⚠️ El semáforo confirma a quien SÍ actualizó, pero **no prueba lo contrario**:
un estudio en la 26 que rechace el permiso de push seguiría en 🔴.

### ⚠️ Riesgo de los builds MUY viejos (medido el 29/8)

- **El `1.0.6+22` nunca existió.** El historial va `1.0.5+19/20/21` → salto →
  `1.0.6+24` → `+25` → `+26`. El "22" de los nombres de archivo es una tanda
  interna, no un build.
- **El gate de versión nació el 21/08 00:49** ⇒ el **24 y anteriores NO lo
  tienen**: el force-update no los alcanza. Sólo bloquea al 25.
- **Una app vieja SIGUE FUNCIONANDO** con la base de hoy. Repasado uno por uno:
  el DROP de la fantasma (leen la real primero), las policies de horarios (las
  4 acotadas alcanzan), el tope de vistas (insert fire-and-forget), el trigger
  de `checked_in_at` (les arregla la hora), las columnas nuevas de
  `liquidaciones` (Dart ignora claves desconocidas), y
  `admin_upsert_estudio` con el parámetro nuevo (verificado: la llamada vieja
  funciona). Nada rompe.
- ⚠️ **Dos asteriscos:**
  1. Los **guards nuevos** devuelven `PostgresException` crudo en el build 24
     (el manejo de errores legible entró el 25/8). Feo, no roto.
  2. ✅ **`tipo_precio = 'servicio'` NO rompe las apps viejas — VERIFICADO
     el 29/8.** La nota original de este archivo decía lo contrario; era un
     **error de análisis** y se corrigió.

     **El modo de falla real, medido en el código del build 24:**
     `clases.tipo_precio` se consume en **un solo lugar**
     (`explorar_screen.dart:946`), como **string suelto**, en una cadena
     `if/else` de comparaciones `==`:

     ```dart
     if (esWorkshop) ...
     else if (tipoPrecio == 'pico') ...
     else if (tipoPrecio == 'normal' || tipoPrecio == 'valle') ...
     // 'servicio' cae acá: no dibuja badge y sigue de largo
     ```

     `'servicio'` **cae en el else vacío**: la tarjeta se muestra **sin badge**
     y la app no se cae. Es, además, el comportamiento deseado.

     **De dónde salió la falsa alarma:** el `enum TipoPrecio {fijo, pico,
     valle, normal, experiencia}` con su `switch` existe, pero **nunca se
     construye desde `clases.tipo_precio`** — se arma en código desde
     `estudios.tipo_precio` (que es `'fijo'`/`'rango'`, otra columna) asignando
     valores literales. **No hay `byName` ni `values.firstWhere`** en ninguna
     parte, que son las funciones que sí lanzarían con un valor desconocido.
     Sin conversión string→enum no hay crash posible.

     ⇒ **Ninguna sesión futura debe frenar la carga de servicios de precio fijo
     por miedo a romper apps viejas.** Ese riesgo no existe.

### 🟡 Servicios de precio fijo: por qué esperar la 1.0.7 (el motivo correcto)

La regla **sigue vigente**, pero por **un solo motivo**, y conviene tenerlo
claro para no confundirlo con el falso riesgo de arriba:

**El motivo real y medido:** el espejo del panel (`PricingCalculator`) todavía
calcula **por franja**. Si un estudio carga una grilla con un servicio de
precio fijo, el formulario le muestra `⚡ 19:30 · 18 cr` mientras la base
guarda **14** — y la confirmación día por día, que lista los precios antes de
crear, le miente. Al recargar el panel aparece el 14 (correcto), pero ya vio
el número equivocado.

**NO es por riesgo de crash de apps viejas** — ese riesgo se verificó y no
existe (ver arriba).

**Qué se puede hacer mientras tanto, sin esperar nada:** si hace falta un
estudio con servicios andando antes de la 1.0.7, **la grilla la carga Aura
desde el backoffice**. El precio queda bien y el estudio nunca ve el número
equivocado. La base está completa y verificada desde el 27/8.

### 📋 Lo que queda por coordinar (sólo la policy)

El force-update ya está activo y se queda. **Lo único que espera adopción es
cerrar la policy de nombres:**

1. **Avisar a los 4 en 🔴 que actualicen** desde el App Store — aunque ahora el
   cartel lo hace solo cuando abren la app.
2. **Verificar adopción con la consulta de `user_agent` + `app_version`**, no
   con `dispositivos` sola.
3. Recién con los 4 en la 26: **cerrar la policy** `usuarios_select_alumnas_de_mis_clases`.

```sql
-- quién usa app vs web, y con qué versión si registró push
select u.email,
       case when s.user_agent ilike '%dart%' then 'APP' else 'WEB' end as cliente,
       s.updated_at,
       (select max(d.app_version) from public.dispositivos d where d.usuario_id=u.id) as version
  from auth.sessions s join public.usuarios u on u.id=s.user_id
 order by s.updated_at desc;
```

### 🔴 `aps-environment` — mirar ANTES de cualquier build de iOS

`ios/Runner/Runner.entitlements` está en **`production`** desde el 26/8, para
archivar el build 26 y subirlo a la App Store.

**Si compilás para probar en tu teléfono o para un TestFlight de prueba, hay
que volverlo a `development` o en ESE build el push no llega.** Y acordate de
dejarlo en `production` otra vez antes del próximo archivado para la tienda.

```
ios/Runner/Runner.entitlements
  <key>aps-environment</key>
  <string>production</string>   <!-- App Store -->
  <string>development</string>  <!-- teléfono propio / TestFlight de prueba -->
```

No es un detalle cosmético: sin el valor correcto, APNs no emite el token y FCM
no puede entregar nada en iOS — y el síntoma es "no llegan las notificaciones",
que es carísimo de diagnosticar desde afuera.

### ⚠️ Lo primero al retomar

**🟢 Rock Studio se puede cargar. El multi-sede está COMPLETO.**

Verificado el 24/8 corriendo el alta entera de las **dos sedes** por el camino
real del backoffice, con la cuenta del dueño (real, no superadmin):

| | |
|---|---|
| Aura crea Palermo y Belgrano, modo rango 12–16, valle 7/8/9 L-V | ok |
| vincular sede 1 | `estudio_admins` = 1 fila · `usuarios.estudio_id` = Palermo |
| **vincular sede 2 — ¿pisa a la primera?** | **NO.** `estudio_id` sigue en Palermo · administra **Belgrano + Palermo** |
| `list_my_studios` | `Belgrano \| Palermo (ACTIVA)` |
| grilla en **Palermo** (07:00 valle) | **PASA · 12 cr** · generar: 4 creadas, 0 omitidas |
| grilla en **Belgrano** (19:00 pico) | **PASA · 16 cr** · generar: 4 creadas, 0 omitidas |
| `set_active_estudio(Belgrano)` | ok · la sede activa cambia |

**Qué lo hizo funcionar:** el arreglo del 24/8 que movió la RLS de
`horarios_fijos` a `estudio_admins`. Antes de eso la segunda sede daba 42501,
porque la RLS miraba el puntero de sede activa, que apunta a una sola.

⚠️ **NO existe ningún "PASO 2" pendiente. Fue un error de diagnóstico del
24/8** y queda anotado acá para que nadie lo vuelva a "arreglar":

`admin_link_estudio_access` sí escribe sólo `usuarios.estudio_id` y 0 filas en
`estudio_admins` — pero **es el fallback legacy**. El botón de vincular del
backoffice llama primero a **`studio_promote_user_to_admin`**
(`admin_service.dart:246`), que ya hace lo correcto y **acumula**:

```sql
insert into estudio_admins (...) on conflict (estudio_id, usuario_id) do nothing;
update usuarios set estudio_id = p_estudio_id where id = ... and estudio_id is null;
```

El `on conflict do nothing` acumula y el `where estudio_id is null` evita pisar
la sede activa. Sólo se cae al legacy si esa RPC no existiera, y existe.
La medición que dio "bloqueado" llamaba **a la función equivocada**.

**Al configurar Rock Studio, tres trampas silenciosas:**
- **Modo rango: `valle` es opt-in.** Solo cobra `creditos_min` en los pares
  (día, hora) marcados en `horarios_config`; **todo lo no marcado es pico** =
  `creditos_max`. Si se carga el rango y se olvidan las franjas valle,
  **cobra el máximo en todas y nadie tira un error**. La hora se trunca hacia
  abajo: marcar "10" cubre 10:00, 10:30 y 10:45.
- **`fecha_inicio_cobro` en null ⇒ se cobra comisión desde el día uno**, sin
  mes de gracia y sin aviso. Los 6 estudios reales lo tienen seteado.
- **Cupos:** cargar `lugares_total = 15` (las bicis que van a Aura). Medido: la
  reserva baja el disponible de a uno y `clases_resync_cupo` recalcula desde
  las reservas reales.

**El viaje completo, verificado el 24/8 con cuentas reales en rollback:**
crear sede en modo rango · grilla de spinning pegada (07:00 y 08:00 valle =
12 cr; 19:00 pico = 16 cr; **12 clases creadas, 0 omitidas**, sin colisión
entre grillas contiguas) · clase suelta 12:00 = 16 cr pico · comprar pack
(40→60) · reservar (−12, cupo 15→14, QR) · marcar presente (a +20 días
BLOQUEADO, mañana con la ventana abierta PASA) · cancelar a tiempo (+16) · el
estudio cancela (+12, campanita) · **vuelta exacta 40 → 12 → 28 → 40**.

**Y dos cosas que esperan a la usuaria:**
- Que **YN Pilates confirme en el teléfono** que puede cargar y cancelar.
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

# ✅ HECHO EL 2026-08-25 — incidente Tiwar: "se duplican las clases y aparecen horarios raros"

**Reporte:** el dueño cargó "8:30 y 9:30" y ve clases a la "1:30 y 2:30"; la
usuaria ve "17:30 y 18:30" para lo que creían la misma clase. Sonaba a zona
horaria. **No lo era.** Se midió todo antes de tocar:

| Qué se creyó | Qué era (medido) |
|---|---|
| desfase de timezone | **no existe**: `clases.fecha` es `timestamp without time zone` (hora de pared), la API devuelve `"…T08:30:00"` sin `Z`, Dart no aplica zona al parsear, y no hay ninguna resta de 7 h en el código (las 27 `Duration(hours:` son −3 para "ahora en Argentina" o ventanas) |
| "1:30 y 2:30" | **13:30 y 14:30 en reloj de 12 h.** La tarjeta del panel del estudio usa `DateFormat('hh:mm a')` (`mis_clases_screen.dart:5017`) — el **único** lugar de toda la app en 12 h, desde el commit inicial. Y esas clases existen |
| "17:30 y 18:30" | las dos siguientes clases reales cuando la usuaria miró (grilla cargada 16:15 ART, lista de la alumna = `fecha >= ahora`) |
| "cargó 8:30 y 9:30" | son los dos **"Desde"** que tipeó. El formulario de grilla es un **rango**; mandó dos —08:30→21:30 y 09:30→22:30— con 46 s de diferencia. El cartel se lo dijo: *"13 clases por día"* |
| "el generador duplica" | **no**: reproducido, `generar_clases_estudio` es idempotente en 3 corridas. Las 534 clases de más entran enteras por las **60 grillas duplicadas** |

**Regla que deja:** cuando tres personas ven tres horas distintas, antes de
pensar en zona horaria mirar si **son la misma clase**. En una grilla con una
clase por hora, casi nunca lo son.

| | Qué | Medición | Archivo |
|---|---|---|---|
| ✅ | **Guard: no se puede cargar dos veces el mismo horario fijo.** Trigger `BEFORE INSERT OR UPDATE` en `horarios_fijos`, rechaza con mensaje legible y `errcode 23505`. Va como trigger y no como índice único porque Postgres no deja crear el índice mientras existan los duplicados de Tiwar y Yessi; **el índice `(estudio_id, dia_semana, hora_inicio)` va en la migración que limpie Tiwar**, y el trigger queda como capa del mensaje. | lote normal 5 slots ✅ genera 20 · doble tap **RECHAZADO** · rango solapado **rechazado entero, siguen 5** · slot nuevo ✅ · editar profe/cupo ✅ · mover a libre ✅ · mover a ocupado **RECHAZADO** · otro estudio mismo slot ✅ · como `postgres` **RECHAZADO** · Tiwar edita sus 130 (dupes incluidos) ✅ 130 filas · cron regenera ✅ | `FIX_GRILLAS_SIN_DUPLICADOS_2026-08-25.sql` |
| ✅ | **`aviso-alumnos-email` mostraba la clase 3 h antes.** `new Date("…T08:30:00")` en Deno (UTC) + `timeZone: Buenos_Aires` ⇒ **05:30**. Latente: `avisos_envios` = 0, nunca se mandó uno. Pasa a `timeZone: 'UTC'` como ya hacía `nueva-reserva-estudio-email`. **Deployada** (declarada en `config.toml`, `verify_jwt` intacto). | `node` en `TZ=UTC`: **05:30 → 08:30** | edge function |
| ✅ | **`email-confirmacion`** tenía el mismo patrón. Arreglada **en el código, NO deployada**: no está en `config.toml` (deployarla cambiaría `verify_jwt` en silencio) y si debe existir es decisión de producto (ver NEGOCIO). | idem | edge function |
| ✅ | **El generador no crea clases encima de una que ya existe.** Interacción encontrada en la verificación de punta a punta: `clases.horario_fijo_id` es `ON DELETE SET NULL` (borrar una grilla deja sus clases huérfanas y publicadas), el chequeo de existencia iba **sólo por `horario_fijo_id`** (ciego a huérfanas), el guard de grillas no ve clases, y `_deleteFixed` traga errores. Medido: borrar grilla → 3 huérfanas → recrear → **3 fechas duplicadas**. Ahora hay un **segundo chequeo por `(estudio, fecha exacta)`**, venga de la grilla que venga o de ninguna; contador `ocupadas` aparte. De yapa el cron **deja de crearle semanas duplicadas a Tiwar** hasta la limpieza. | huérfanas por SQL → recrear: **dups 0** (antes 3) · el caso real (`_deleteFixed` con clase protegida por el candado, 1 huérfana tragada) → recrear: **dups 0** · grilla nueva 6/0 · regenerar 0/6 · mover 0/6 · cron como `service_role`: 6 estudios, colisiones siguen 517, 0 desalineadas · Tiwar `creadas 0 · ocupadas 6` (antes creaba 12) | `FIX_GENERADOR_NO_PISA_CLASES_2026-08-25.sql` |

---

# ✅ HECHO EL 2026-08-25 — incidente Citra: QR, nombres y campanita

Tres síntomas reportados juntos ("el QR no escanea", "no llegó el aviso", "no
aparece el nombre al marcar presente"). Se sospechó una clase de Citra rota.
**Medido: la clase 516 está sana** (martes 25/8 18:30, grilla 32 alineada, una
sola en ese minuto). **Son tres causas independientes y sistémicas — le pasaban
a todos los estudios.**

| | Qué | Medición | Archivo |
|---|---|---|---|
| ✅ | **El escáner rechazaba TODOS los QR reales.** Valida el formato antes de consultar la base (`asistencia_screen.dart:400`, `^AURA-[A-Z0-9]{8}-\d+-\d+-\d{4}$`). Hasta el 21/7 el código lo generaba el cliente así; ese día se mudó a la base (`897c6cc`, D1) y salió como 12 hex sueltos. Nadie tocó el regex. **`_waitlist_promote_interno` nunca dejó de usar el formato correcto** — `reservar_clase` era el único desalineado. Se arregla en la BASE para que funcione en las apps ya instaladas. | en toda la base: 3 reservas `AURA-…` (junio, canceladas) vs **2 de 12 hex** (19/8 y 24/8) ⇒ **el escáner no leyó una sola reserva real desde julio**. Después: `AURA-58E38EDA-603-…-4571` **pasa**, el lookup encuentra la reserva/clase/alumna correcta, `clase_id` embebido coincide, aguanta basura del lector; cancelar por QR nuevo OK; las 2 viejas intactas | `FIX_QR_FORMATO_ESCANER_2026-08-25.sql` |
| ✅ | **El estudio no veía el nombre de sus alumnas.** `_cargarAsistentes` pide `usuarios.nombre,email` y la única policy era `usuarios_select_self` ⇒ `null` ⇒ la UI mostraba 'Alumno'. **Provisorio**: policy acotada vía helper `es_alumna_de_mi_estudio()`. | Citra ve **`malekuipers <malekuipers@gmail.com>`** ✓ · no ve a Julieta (0 filas) · lista **2 de 78** · Sculpt no ve a la alumna de Citra (0) · alumna ve 1 (ella) · anon 1 · cancelando **todas** las reservas deja de verla | `FIX_ESTUDIO_VE_NOMBRES_ALUMNAS_2026-08-25.sql` |
| ✅ | **La campanita de reserva no le llegaba al dueño.** Sólo insertaba para `rol='profe'` con `nombre == clases.instructor`; un `admin_estudio` nunca recibía nada, y salía con 0 si la clase no tenía instructor (**277 de 1797 clases futuras**). Ahora `union` de profe (igual que antes) + dueños del estudio, dedup, excluyendo a quien reservó. | 0 → **3 campanitas** (los 3 admins de Citra) con el texto correcto, en una clase **sin instructor** · la dueña reservando en su propia clase → **0** · reserva ajena (guard 20/8) → **0** · otro estudio → **0** | `FIX_CAMPANITA_RESERVA_AL_DUENO_2026-08-25.sql` |

### Tres más de la revisión del formulario en Chrome/Safari (misma tarde)

| | Qué | Medición | Archivo |
|---|---|---|---|
| ✅ | **La sala distingue horarios.** El guard de grillas y el generador iban por `(estudio, día, hora)` sin mirar `sala`: un estudio con dos salones no podía tener dos clases al mismo minuto. Clave con `lower(trim(coalesce(sala,'')))` en los dos. El mensaje del guard pide cargar la sala si es otra. | lun 08:00 en Sala 1 **y** Sala 2 → pasan · misma sala (con mayúsculas/espacios distintos) → rechazado · sin sala dos veces (caso Tiwar) → rechazado · generador publica **las dos** · Tiwar y Citra sin cambios | `FIX_SALA_EN_CLAVES_Y_SIN_PASADAS_2026-08-25.sql` |
| ✅ | **El generador no publica el pasado.** La semana arranca el lunes: crear una grilla un martes publicaba las del lunes anterior (medido: 3 clases del 24/8). Se saltean, cuentan como omitidas. | clases en el pasado: **0** | idem |
| ✅ | **"Cancelar clase" cancela la CLASE.** `estudio_cancelar_clase` devolvía créditos y cancelaba reservas pero no tocaba la fila: la clase seguía publicada y **reservable**, y el panel la mostraba igual. Opción B (decidida): columna `clases.cancelada`; el RPC la marca, vacía su lista de espera y es idempotente; `reservar_clase` y `confirm_pre_reserva` la rechazan; la waitlist no promueve; el generador no la recrea (ocupa su minuto); el candado permite borrarla después. **Dart en este build:** etiqueta CANCELADA en el panel, ocultas en Explorar/detalle de estudio, mensaje legible al reservar. | cancelar → `cancelada=true`, reservas `cancelada_por_estudio`, lista de espera 0, saldo devuelto · cancelar de nuevo → `ya_cancelada` · reservar → `clase_cancelada` · confirmar pre-reserva → `clase_cancelada` · promote → `skipped` · cron no la recrea · alumna no la des-cancela (0 filas) · estudio la borra después ✓ | `FIX_CLASE_CANCELADA_2026-08-25.sql` |

**Hot Clic** (estudio de prueba, no real) quedó con **0 clases y 0 reservas**: se
borraron 7 clases pasadas de junio y las 3 reservas canceladas de prueba.

### El mail sí se envió — es spam, y hay algo real que arreglar

`delivered` a Citra (confirmado en Resend); el bounce era una casilla de prueba
inexistente. Pero **el FROM sale de un dominio SIN SPF**: `hola@somosaurapass.com`
no tiene registro SPF; el SPF vive en `send.somosaurapass.com`, que **no es el
dominio del FROM**. DKIM está y DMARC es `p=none`, así que entrega — con la
señal débil que manda a spam. **La nota vieja que decía "el SPF ya existe" mira
el subdominio equivocado.** Arreglo: agregar SPF en el dominio raíz (DNS, no
código).

### ⚠️ Consecuencia de la campanita, para decidir

`test@aura.com` es admin de **8 estudios** y es **la única cuenta con
dispositivos push** (×2). Con este arreglo recibe un push por **cada reserva de
cualquier estudio**. Es la cuenta de prueba propia, así que es ruido y no daño;
se apaga poniéndole `notifs_reservas_profe = false`, o se excluye a los
superadmin con una línea en la función. **Sin decidir.**

---

# ✅ HECHO EL 2026-08-24 — AUDITORÍA FRESCA de punta a punta

Pedida con **cabeza limpia y sin dar nada por bueno**, midiendo **contra la
base** y no contra estas notas, con **cuentas reales y nunca `test@aura.com`**,
y verificando **las dos puntas** en cada cosa. Todo en transacciones con
`rollback`; verificado que quedaran 0 filas de prueba.

**Encontró 4 agujeros que las tandas anteriores no habían visto, y 41 clases
mal publicadas en producción.** Los 5 arreglos están aplicados y commiteados.

| | Qué | Medición | Commit |
|---|---|---|---|
| ✅ | **`consume_user_credits_detallado` invocable desde internet.** SECURITY DEFINER, sin validar quién llama, tomando el `user_id` por parámetro, con `EXECUTE` para **PUBLIC** además de anon y authenticated. Cualquiera con la anon key —que va dentro de la app— vaciaba los créditos de cualquiera **sin loguearse**. | alumna ajena deja a otra en 0 (**40 → 0**); anon idem (**22 → 0**); por HTTP devolvía **200**. Después: **42501 / HTTP 401** para anon y para alumna logueada; reservar, cancelar y confirmar pre-reserva siguen andando. | `382067c` |
| ✅ | **Escalada por el email → control de `liquidaciones`.** El guard de `usuarios` no protegía `email`, y la policy de `liquidaciones` comparaba contra el mail hardcodeado `'test@aura.com'` en vez de `is_admin()`. Una alumna se ponía ese mail y quedaba dueña del libro de pagos. | Antes: cambiarse el mail PASA, leía `est 3 · $8400`, insertaba falsas, **modificaba 2 y borraba 2**. Después: mail **BLOQUEADO**, liquidaciones **0 filas / 42501**; el admin real sigue leyendo, creando, marcando pagada y borrando. | `8215db7` |
| ✅ | **Un dueño no podía administrar 2 sedes.** Las 4 policies de `horarios_fijos` autorizaban con `usuarios.estudio_id`, que **no es una columna de permisos**: es el puntero de **sede activa**. Al ser escalar, la segunda sede quedaba inaccesible. | `bottarobelen` (real, no superadmin): grilla en Colegiales PASA, **en Urquiza 42501**. Después: **las dos PASAN**, y el flujo completo en la 2ª sede anda (2 grillas → 8 clases → mover horario → 0 duplicados). Sin regresión: Citra 23 grillas, Sculpt 17. | `f34dd9d` |
| ✅ | **Farmeo corporativo recurrente.** `es_corporativo` y `empresa_id` no estaban en el guard; lo único que los tapaba era una FK, porque `empresas` está vacía. El cron mensual está **activo**. | Simulando la primera empresa (30 cr/empleado): **40 → 190 cr en 5 corridas**, 150 regalados. Después: **BLOQUEADO** en las 3 formas; el alta de un empleado real por dominio sigue vinculando y acreditando (30 cr) y el cron le sigue pagando. | `b718592` |
| ✅ | **41 clases publicadas a la hora equivocada** (Citra y Yessi). Daño anterior al arreglo de grillas del 24/8. | 41 **movidas**, 0 borradas · desalineadas **41 → 0** · colisiones **37 → 1** · total futuro **397 → 397** · precios desviados 0 · las 5 reservas intactas. | `a3a5b97` |

**Huérfanas vivas en producción (barrido del 25/8):** **una sola** clase
futura con `horario_fijo_id NULL` en toda la base — YN Pilates 31/08 11:00
(id 2439), la de siempre, con la grilla 239 viva en el slot. El problema era
sólo a futuro. Con el generador nuevo esa huérfana ya no engendra más
duplicados, pero la del 31/08 sigue siendo un duplicado real: menor 1.

⚠️ **Efecto deliberado del generador nuevo:** si un estudio carga una clase
suelta o un workshop **en el mismo minuto** que una clase de grilla, esa
semana la grilla no genera la suya (`ocupadas 1`). Un minuto, una clase, por
estudio — coherente con el guard de grillas. Si algún día un estudio con dos
salas necesita dos clases al mismo minuto, esto lo frena.

### ⚠️ La lección del backfill: parecían duplicados y no lo eran

Las 37 "clases duplicadas" **no eran duplicados**. Medido: en los 13 grupos, el
horario correcto de cada clase estaba **libre**. Lo que pasaba es que dos
grillas **distintas** chocaban en la hora equivocada — Citra los lunes, grilla
18 (08:30) y grilla 20 (09:30): del 31/8 al 28/9 las dos a las 08:30 con el
slot 09:30 **vacío**, y el 5 y 12/10 al revés.

Cada fila era una clase **legítima mal ubicada**. **Borrarlas le habría sacado
a Citra y Yessi 41 clases reales que sí dictan.** Se movieron: resuelve la
colisión y repone la faltante de una sola vez.

**La regla que deja:** antes de borrar filas "duplicadas", chequear si el lugar
correcto está libre. Si lo está, es un *move*, no un *delete*.

### ⚠️ Y la del grant a PUBLIC

El plan original del arreglo #2 era *"revocar a anon y authenticated"*. Al
mirar la ACL antes de tocar apareció `=X/postgres`, que es el grant a
**`PUBLIC`**: con eso ahí, **revocar a anon y authenticated no habría cerrado
nada**, porque todo rol hereda de PUBLIC. Fue la única de las tres primitivas
de crédito que lo tenía.

**La regla:** al revocar un `execute`, mirar la ACL completa —`proacl`—, no
sólo los roles obvios.

### Lo que la auditoría probó que SÍ está bien

- **El viaje completo de plata cierra exacto:** 40 → 12 → 28 → 40, con cuentas
  reales, incluyendo pack, reserva, QR, presente, cancelación de la alumna y
  cancelación del estudio con campanita.
- **0 precios desviados** en 702 clases futuras y 79 grillas.
- **Convención de `dia_semana` consistente:** 0 desvíos en 1007 clases de grilla.
- **Editar una grilla ya no duplica**, incluido el **borde exacto de 1 hora**
  (que era el caso que antes se ignoraba en silencio).
- **Marcar asistencia antes de tiempo sigue bloqueado**; con la ventana abierta
  se puede.
- **Las `admin_*` abiertas a `anon` rechazan todas por HTTP** (probadas
  `admin_delete_estudio`, `admin_list_users`, `admin_adjust_user_credits`,
  `admin_pricing_snapshot`): el grant está desprolijo pero no es explotable.
- **Las 32 tablas tienen RLS.** `admin_activity_logs` y `avisos_entregas` la
  tienen con 0 policies, o sea deny-all: fallan cerrado, está bien.

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
| ✅ | **`ensure_referral_code`** — era la última sin `search_path` de las de entonces. ⚠️ **El "94 de 94" ya no vale:** medido el 24/8 hay **113 funciones y 5 sin `search_path`** (`set_updated_at`, `set_study_review_updated_at`, `sync_categoria_estudio`, `sync_categorias_clase`, `aura_inicio_mes_art`). Las 5 son trigger functions *invoker*, **0 SECURITY DEFINER** ⇒ riesgo bajo. | `20260822190000` |
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

### Re-medición del 2026-08-26 (después del build 26)

1320 clases (997 futuras) · 115 horarios fijos · **2 reservas** · 11 estudios ·
79 usuarios · 117 funciones · 32 tablas.

**El ledger de créditos cuadra: 85 disponibles en `creditos_movimientos` = 85
en `usuarios.creditos`, con los mismos 16 movimientos del 24/8.** Nada
financiero se perdió.

⚠️ **Pero las reservas pasaron de 5 (24/8) a 2.** Las 3 que faltan estaban
canceladas y no movieron créditos —el ledger lo confirma—, pero **no se puede
saber quién las borró ni cuándo**: no hay log de cambios de estado en
`reservas` (el ítem que se postergó el 22/8). Es el argumento concreto para
levantarlo: cuando la liquidación mueva plata real, una diferencia así no se
va a poder explicar.
(La secuencia `reservas_id_seq` fue de 552 a 649 en el mismo período, pero eso
son ids consumidos por las pruebas con `begin/rollback`, no filas borradas.)

### Números de referencia (para comparar la próxima)

**Al cierre del 2026-08-24, después de la auditoría fresca:**
1019 clases (702 futuras) · 79 horarios fijos · 5 reservas (2 vivas) ·
11 estudios · 78 usuarios · 16 movimientos de crédito · 85 créditos en
circulación (ledger y `usuarios.creditos` coinciden) · 29 pagos ·
113 funciones · 32 tablas · 22 triggers · 1 liquidación.

**0 precios desviados · 0 clases futuras desalineadas de su grilla ·
0 créditos eternos · 0 emails desincronizados con `auth.users` ·
0 usuarios corporativos · 1 colisión futura (la huérfana de YN Pilates).**

⚠️ Los números viejos de esta sección (885 clases, 70 horarios, 9 estudios)
quedaron desactualizados en dos días. **Medir siempre contra la base.**

---

# ⬜ LO QUE QUEDA

## ✅ Multi-sede — CERRADO. Rock Studio se puede cargar.

El arreglo de la RLS de `horarios_fijos` (commit `f34dd9d`) fue lo único que
hacía falta. `studio_promote_user_to_admin` ya acumulaba en `estudio_admins`
desde antes, y los 3 usuarios multi-sede ya estaban bien ahí (0 punteros a
estudios que no administran, 0 huérfanos): **no hubo backfill que hacer.**

⚠️ **El "PASO 2" que este documento marcó unas horas como bloqueante NO
EXISTE.** La medición usó `admin_link_estudio_access` (el fallback legacy) en
vez de `studio_promote_user_to_admin` (lo que llama el botón del backoffice,
`admin_service.dart:246`). Ver el detalle arriba, en "Lo primero al retomar".

---

## ⏸️ Para cuando actives MODO GESTIÓN — hoy no bloquea nada

**Hoy no usás modo gestión: 0 estudios en `modo='gestion'` y 0 filas en
`estudio_alumnos`.** Esto duerme hasta que actives esa función. No tiene nada
que ver con Rock Studio ni con el multi-sede.

**Las 4 policies de `estudio_alumnos`** (select/insert/update/delete) siguen
con el mismo error de categoría que tenía `horarios_fijos`: autorizan con
`usuarios.estudio_id`, que es el puntero de sede activa y no una columna de
permisos. El día que un estudio pase a modo gestión, el bug vuelve entero: un
dueño de dos sedes no va a poder ver ni cargar el padrón de alumnas de la
segunda.

**El arreglo es el mismo de una línea que ya se aplicó en `horarios_fijos`:**
cambiar las 4 a `es_miembro_de_estudio(estudio_id)`. Ver
`FIX_GRILLAS_MULTISEDE_paso1_2026-08-24.sql` como plantilla.

**Hacerlo ANTES de encender el primer estudio en modo gestión**, no después.

---

## ✅ Tiwar Fitness — RESUELTO el 26/8, y el ÍNDICE ÚNICO ya está puesto

**Fue un reset, no un dedupe.** Tenía 130 grillas para 70 slots (60 duplicados
del doble envío del formulario de rango del 25/8), pero además los horarios
cargados no eran los que dicta: una clase por hora de 08:30 a 21:30 L-V,
incluida **16:30 que era "Open Box"** (no va a Aura) y toda la franja
10:30–14:30 que no existe; y le faltaba el sábado.

| | |
|---|---|
| borradas | **1158 clases · 130 grillas** (0 reservas, en ningún estado) |
| cargadas | **37 grillas · 318 clases** (26/8 → 24/10) |
| horarios L-V | 08:30, 09:30, 15:30, 17:30, 18:30, 19:30, 20:30 |
| sábado | 11:30, 12:30 · domingo cerrado |
| nombre / cupo | `Cross / Funct / Hyrox`, sin instructor, cupo 12 (Tiwar lo ajusta) |
| verificado | 0 duplicadas · 0 en el pasado · 0 precios desviados · sin 16:30 ni domingo |

`FIX_TIWAR_RESET_E_INDICE_UNICO_2026-08-26.sql`

⚠️ **Pendiente comercial, NO técnico — las franjas de Tiwar parecen invertidas.**
Su config de valle son las horas **8, 9, 19 y 20**, o sea que **08:30, 09:30,
19:30 y 20:30 salen a 11 cr** (las baratas) y el mediodía a 14. En un box esas
cuatro suelen ser las horas **pico**. Comparación: YN tiene valle 11–15
(mediodía, coherente); Sculpt lo tiene mezclado. **Si Tiwar decide invertirlo,
es un solo `admin_set_pricing_estudio`: recalcula las clases futuras solo, NO
hay que recargar la grilla.**

### 🔒 Índice único — puesto el 26/8

```sql
create unique index horarios_fijos_slot_uidx
  on public.horarios_fijos (estudio_id, dia_semana, hora_inicio, (lower(trim(coalesce(sala,'')))));
```

Con la sala en la clave, mismo criterio que el trigger del 25/8. **Ya no queda
ningún duplicado en toda la base.** Medido después de crearlo: repetir un
horario → 23505 (Tiwar y Rock Studio); re-mandar el lote entero del caso 25/8 →
rechazado entero, siguen 37; **como `postgres` tampoco se puede** (el índice no
depende del trigger); y lo legítimo pasa: horario nuevo ✓, mismo slot en otra
**sede** ✓, mismo slot en otra **sala** ✓.

**Yessi** ya se había resuelto el 25/8 (miércoles 18:00 tenía dos grillas
distintas; quedó la de menor id con sus clases).

## ✅ Reset de contraseña — RESUELTO cross-device el 26/8

**El problema:** el SDK usa **PKCE por defecto** (`gotrue 2.19`,
`flowType = AuthFlowType.pkce`). `resetPasswordForEmail` guardaba el **code
verifier en el dispositivo que pedía el reset**, y el link del mail
(`{{ .ConfirmationURL }}`) sólo se podía canjear **ahí**. Abierto en otro
dispositivo → sin sesión → el router mandaba a `/login`. Eso dejó a **Yessi
Funes** sin poder entrar desde el 29/7.

**El arreglo (dos partes, ninguna necesita el build de la tienda):**

1. **Plantilla del mail (config, aplicada).** El botón ya no usa
   `{{ .ConfirmationURL }}` sino un link fijo a la web:
   `https://somosaurapass.com/#/reset-password?token_hash={{ .TokenHash }}&type=recovery`
   Copias en el repo: `supabase/plantillas/recovery_ACTUAL_tokenhash.html` y
   `recovery_ANTERIOR_pkce.html` (para revertir).
2. **`reset_password_screen.dart` (Dart, sale por GitHub Pages al pushear).**
   Lee `token_hash` del hash routing —y de `Uri.base` como respaldo— y lo canjea
   con `verifyOTP(type: OtpType.recovery)`. Ese canje **NO usa el verifier**.
   Spinner mientras verifica, pantalla de "link vencido" con botón a `/login`
   si falla, y conserva el camino viejo (sesión ya establecida por deep link)
   para las apps instaladas.

**Medido de punta a punta el 26/8:** un token pedido desde un navegador se
canjeó **desde otro** → `✓ sesión obtenida`. Y el parseo del hash routing
verificado con un token falso → muestra la pantalla de link inválido.

### 💡 Lo que no hay que volver a intentar

- **El prefijo `pkce_` del token NO molesta.** `{{ .TokenHash }}` renderiza el
  valor de `auth.users.recovery_token`, que con PKCE arranca con `pkce_`, y el
  canje por `token_hash` **igual funciona** (medido). O sea: **no hace falta
  cambiar el `authFlowType` de la app a implicit**, que era el riesgo grande
  (rompería el fragmento en web por el hash routing y tocaría el login con
  Google/Apple).
- **NO cambiar `redirectTo` a https://** en `login_screen.dart`: iOS no tiene
  `associated-domains` y el App Link de Android sólo cubre `/payment-result`,
  así que abriría el navegador en vez de la app. Con la plantilla nueva
  `redirectTo` **es irrelevante**: la URL la fija la plantilla.

### Dos cosas operativas

- **5 cuentas de estudio NO tienen contraseña** (entraron con Google/Apple):
  Ambra, Sculpt Club y las tres de BB Estudio. Si intentan email + contraseña
  **nunca van a poder**: tienen que usar el botón de Google.
- **Yessi Funes**: se desbloquea a mano desde Supabase Dashboard →
  Authentication → Users → Reset password (requiere la `service_role` key, que
  no está en el vault). **De acá en adelante puede resetear sola.**

## 🟡 Menores de la auditoría fresca — **5 de 8 CERRADOS el 28/8**

**Cerrados** (`FIX_MENORES_AUDITORIA_2026-08-28.sql`, dos puntas medidas):
**2** (DELETE en storage, probado por la Storage API) · **4** (plan/suscripción
— eran 4 columnas libres, no 2) · **6** (policy de config renombrada, sigue
abierta a propósito por el gate pre-login) · **7** (policy `using(true)` de
horarios_fijos dropeada; el estudio ve las suyas y nadie más) · **8** (las 5
funciones con search_path; quedan 0 sin él).

**28/8, más tarde — 7 de 8 cerrados:** la huérfana de YN se **borró** (4 FK
pre-chequeadas, la gemela de grilla sigue) y `admin_link_estudio_access` ahora
**escribe `estudio_admins` también** (decisión: no borrarla, hacerla
consistente; mismo insert acumulativo que la función moderna).
**Queda 1:** las RPC de bienvenida — ⏸️ **decisión de producto** (qué recibe un
usuario nuevo), la usuaria la toma con calma. Si se decide borrar las llamadas
es Dart ⇒ build 27.

**Ninguno bloquea a Rock Studio ni a nada de hoy.**

| Prio | Qué | Por qué |
|---|---|---|
| **1** | **La huérfana de YN Pilates.** 31/08 11:00, dos clases idénticas: id **2441** de la grilla 239 (correcta) e id **2439** sin grilla, 0 reservas. | Es la única colisión futura que queda. Es un `DELETE` de 1 fila, no un move. Decisión de la usuaria porque es data de un estudio real. |
| **2** | **Sin policy `DELETE` en `storage.objects`.** No existe para ninguno de los 3 buckets. | Nadie puede borrar lo que sube — **ni Aura**. Con Rock Studio subiendo fotos, el bucket sólo crece. Ya estaba anotado desde la auditoría de las 8 áreas. |
| **3** | **`admin_link_estudio_access` sigue escribiendo sólo `usuarios.estudio_id`** y 0 filas en `estudio_admins`. ⚠️ **Esto NO es modo gestión** y no bloquea nada hoy. | Es el **fallback legacy** de vincular acceso: sólo se usa si `studio_promote_user_to_admin` no existiera, y existe. Pero si algún día se cayera a él, el estudio quedaría **sin acceso real y con un síntoma confuso** (el backoffice diría "vinculado" y el panel no dejaría cargar nada). **Vale borrarla, o hacerla escribir `estudio_admins` también.** |
| **4** | **`plan` y `subscription_status` son auto-escribibles** por la propia usuaria. | Medido: **ninguna función regala créditos mirándolas** (`process_approved_plan_payment` es SECURITY DEFINER y la dispara el webhook contra una fila de `pagos` real). El efecto se limita a **un badge falso en la UI**. Barato de cerrar sumándolas al guard. |
| **5** | **Las 3 RPCs de bienvenida que no existen** — `acreditar_bienvenida`, `bienvenida_esta_activa`, `admin_apagar_bienvenida`. La migración nunca se aplicó. | El Dart lo maneja bien (`catch` silencioso, y el backoffice dice *"falta aplicar la migración"*), así que **no está roto**. Pero `acreditar_bienvenida` se llama en **cada login** y falla siempre: una ida y vuelta desperdiciada por sesión. **Decidir: aplicar la migración o borrar las 3 llamadas.** Lo segundo toca Dart ⇒ build. |
| **6** | **La policy `"Admins leen config"` de `configuracion_global` es `SELECT using (true)`** para todos. | El nombre miente, pero **no filtra nada sensible** (valor del crédito, min_build, categorías). La lectura abierta probablemente sea necesaria: el chequeo de `min_build` corre **antes del login**. **Renombrarla, no cerrarla** — cerrarla sin mirar rompería el gate de versión. |
| **7** | **`horarios_fijos` tiene `"todos pueden ver horarios"` con `USING (true)`.** | Cualquier usuario logueado lee las grillas de todos los estudios. Es anterior a todo esto y no filtra nada que no sea público (las clases ya lo son). Cosmético salvo que se quiera privacidad de grilla. |
| **8** | **Las 5 funciones sin `search_path`** (ver Tanda A). | Las 5 son trigger functions *invoker*, **0 SECURITY DEFINER** ⇒ no hay vector real. Prolijidad. |

**Ninguno tiene fecha.** El único con un disparador es el bloque de modo
gestión de arriba, y el disparador no es un día: es "antes de encender el
primer estudio en modo gestión".



## ⏭️ Tanda B — verificación de mail · SALTEADA

`mailer_autoconfirm = true`. **Decisión del 22/8: no ahora.** Se activa cuando
entre la primera empresa. El detalle completo está más abajo, en PASO 1.

## ✅ Tanda C — CERRADA. Es el **build 26** (1.0.6+26), compilado el 26/8

Commits: `51e8da1` (grupo 3) · `cf2d67f` (sueltos) · `6f202d9` (bump + aps).
Los grupos 1 y 2 ya estaban (25/8). `flutter analyze` 0 errores, tests OK, web
e iOS compilan.

### Lo que quedó AFUERA y por qué — leer antes de re-proponerlo

- **Item 12 · badge "MEJOR VALOR" de packs.** NO se tocó: el 14/8 la usuaria
  dijo *"anotalos pero no los toques ahora"*. Ojo, el bloqueo técnico de la
  nota vieja ("requiere CLI linkeado") **ya no existe** — el SQL se corre por
  Management API. Es agregar una columna de texto a `pricing_credit_packs` y
  leerla en `_packDesdeFila`; base + Dart, o sea que necesita su propio build.
- **Item 13 · salir de las keys legacy.** NO en este build, y no por miedo:
  medido el 26/8, la `sb_publishable_…` **funciona** — REST lee, la RPC
  responde, y GoTrue la acepta (con una key inválida contesta
  *"Invalid API key"*; con la publishable contesta `invalid_credentials`, o
  sea que llegó a chequear la contraseña). El motivo es otro: el paso 1 es
  *publicar con la clave nueva y esperar adopción*, y eso quiere un build
  donde el cambio de clave sea la variable notable, no uno con quince cambios
  más encima.
- **Item 7 · el DROP de la columna fantasma.** La mitad Dart entra en el build
  26; el `alter table` está listo en
  `supabase/FIX_COLUMNA_FANTASMA_2026-08-26.sql` para **correr después de que
  el build 26 esté publicado y verificado**. Ver ahí el detalle de por qué no
  hay ventana de riesgo.
- **Item 16 · lista de espera del estudio.** Hecho, pero hoy no muestra nada:
  `lista_espera` tiene **0 filas** y nunca se usó, porque ninguna clase futura
  está llena. Dato del 26/8: hay **2 reservas en toda la app**, las dos de
  agosto. No es un bug, es la etapa.

### Correcciones a lo que decía esta nota (estaba desactualizada)

- **Item 8 (foto de perfil) ya andaba.** Decía "0 archivos subidos desde el
  fix"; el 26/8 hay un avatar subido el **24/8 a las 21:33**, posterior al fix.
- **Item 23 (`#BK-`) NO estaba hecho.** Figuraba como hecho-sin-verificar y el
  código seguía con `.split('-').last`. Se arregló ahora.
- **Item 7: las referencias eran 7 de 10, no 10 de 10.** La nota decía que las
  diez leían la columna real primero; en `clase_card.dart` y en los dos puntos
  de `detalle_clase_screen.dart` la fantasma iba **primero**. Daba igual porque
  siempre es null, pero la afirmación estaba mal.

### Decisiones de negocio que quedaron abiertas (medidas, sin decidir)

- **Las franjas de Tiwar parecen invertidas**: 8, 9, 19 y 20 h están en valle
  (11 cr) y son las horas más pedidas. Se arregla con un
  `admin_set_pricing_estudio`, sin recargar clases.
- **YN Pilates tiene `creditos_max = 13` pero ninguna clase pasa de 11**, así
  que se lleva el badge de precio reducido en 79 de 79. Mismo olor que lo de
  Tiwar: una banda configurada que no se usa.
- **La clase huérfana de YN Pilates** (31/08 11:00, id 2439, 0 reservas).

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

## ✅ Preservar facturación — la mitad urgente, CERRADA el 26/8

**El agujero grave está tapado: una alumna que borra su cuenta ya no se lleva
puesta la plata del estudio.** Dos arreglos, los dos en producción:

1. **`delete-account` v10** (edge function, `a70c3cc`). En vez de borrar la fila
   de `usuarios` y pelear contra 12 CASCADE, la **anonimiza** (lápida,
   `rol = 'eliminado'`) y borra la cuenta de `auth.users`, que es el borrado
   real. Se van nombre, email, foto, códigos de referido y lo de suscripción;
   quedan válidas las reservas, los pagos y el ledger. También se limpian
   `pagos.gift_email` y `gift_mensaje`, que son dato personal de OTRA persona.
   Y se tapó el segundo agujero: cuando quien borra es dueña de un estudio, si
   una clase tiene reservas liquidables ya **no se borra, se cancela**.
2. **Las FK a `SET NULL`** (`aca4c76`, `FIX_CASCADE_FACTURACION_paso3_2026-08-26.sql`).
   `reservas.usuario_id`, `pagos.user_id`, `creditos_movimientos.user_id` y
   `admin_activity_logs.admin_user_id`. Es la red para el borrado por SQL
   directo. Incluyó un prerrequisito que apareció midiendo: sin él,
   `estudio_cancelar_clase` se caía con `p_user_id es null` y el estudio no
   podía cancelar una clase con una reserva de cuenta borrada.

**Viaje completo medido contra producción el 26/8:** cuenta real creada →
reservó con la RPC real → completada → borró su cuenta por la edge function →
**el estudio conserva sus 12 créditos por cobrar**, la reserva figura a nombre
de "Anónimo", y la cuenta no puede iniciar sesión (`invalid_credentials`, y el
JWT viejo da `user_not_found`).

### 🟡 Lo que NO cierra — para hablar con la contadora, NO re-proponer como bug

**`admin_delete_estudio` sigue destruyendo la facturación**, por una puerta
distinta de la que cerramos: hace `delete from public.clases where estudio_id`,
y **`reservas.clase_id` es otro `ON DELETE CASCADE`** (no el de `usuario_id`).
Encima hace `delete from public.liquidaciones`.
Medido el 26/8 con Citra en una transacción con rollback: **sus 36 créditos por
cobrar pasan a 0 y sus 2 reservas desaparecen.**

**Decisión de la usuaria, no técnica** (26/8): borrar un estudio es una acción
rara y deliberada de superadmin. Lo que hay que definir con la contadora es si
el histórico de facturación de un estudio dado de baja tiene que sobrevivir —
por ejemplo si se le quedó debiendo plata, o por obligación fiscal.
Las dos salidas, cuando esté decidido: `reservas.clase_id` a `SET NULL`, o que
`admin_delete_estudio` archive en vez de borrar.

## 🟢 Tanda D — servicios de precio fijo · **BASE EN PRODUCCIÓN desde el 27/8; falta el Dart (build 27)**

**9 decisiones cerradas, 0 abiertas.** Todo el diseño está en
`supabase/pendientes/SERVICIOS_PRECIO_FIJO_relevamiento.md`: el caso real de la
usuaria, las 9 decisiones, cómo lo ve el estudio al cargar, el reparto
base/Dart, la trampa del orden y el plan de construcción paso a paso.

**La BASE ya está aplicada y verificada** (`FEAT_SERVICIOS_PRECIO_FIJO_2026-08-27.sql`,
huellas idénticas, las 8 puntas medidas — el detalle en la sección 6c del
archivo). **Lo que falta es SOLO el Dart del build 27** (tabla azul de 6b:
chips, renglón "precio único", pantalla del backoffice, `TipoPrecio.servicio`,
Explorar sin badge para 'servicio').
⚠️ **NO entregarle el alta de servicios a ningún estudio hasta ese build** — el
espejo del panel todavía calcula por franja. Si hace falta antes, la grilla la
carga Aura desde el backoffice.

Tres cosas que conviene saber antes de abrirlo:
- **Es aditivo**: un *early return* en `calcular_precio_clase`. La tabla arranca
  vacía ⇒ ningún estudio actual cambia de precio. La verificación obligatoria
  es recalcular todo y que dé **idéntico**.
- **`clases_tipo_precio_check` va PRIMERO** (hoy no acepta `'servicio'`; sin
  ampliarlo el trigger revienta con 23514).
- **La base sola hace que el estudio vea un número equivocado mientras carga**
  (el espejo del panel sigue calculando por franja). Por eso no se le entrega
  el alta de servicios a ningún estudio hasta el build 27.

## ⬜ Modelo C de precios — la excepción de precio

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
| ✅ | **Alumnas anotadas cuando el estudio toca la grilla — RESUELTO el 28/8** | La usuaria eligió **BLOQUEAR**: una clase con anotadas no se mueve (ni en grilla ni suelta), el cupo no baja por debajo de las anotadas, borrar la grilla cancela con devolución en vez de dejar huérfanas, y la colisión al mover está guardada. 12 puntas medidas. Ver `GRILLA_CON_ANOTADAS_relevamiento.md` y `FEAT_GRILLA_BLOQUEAR_CON_ANOTADAS_2026-08-28.sql`. Al build 27 sólo va la mejora de UX (avisar antes de intentar). |
| ⬜ | **Avisar el fin de la gracia** | **Citra el 13/9.** 6 estudios entre el 13/9 y el 30/9. Transición automática; falta la conversación. |
| ✅ | **Mail de confirmación de reserva — DECIDIDO Y ACTIVO desde el 29/8** | Cableado por base (trigger al confirmarse), texto aprobado ("fitness y experiencias", línea del código). Le llega a todas las alumnas ya. |
| ⬜ | **Categorías faltantes** | Avisarle a Yessi (112 clases) y Ambra (77) que las completen. O que el form las exija (Dart). |

## ⬜ WEB / INICIO — mejoras, no urgentes (anotadas el 28/8)

| | Qué | Nota |
|---|---|---|
| 1 | **Verificar si se arregló el contador de clases** | No recordamos si quedó resuelto. **Medir antes de tocar** |
| 2 | **Las tarjetas de clase se ven estiradas en desktop** | Optimizar responsive en pantalla grande |
| 3 | **Categorías ordenadas alfabéticamente** en el inicio | |
| 4 | **El inicio está medio vacío** | Hoy sólo "cerca de ti", estudios y clases de hoy. Enriquecerlo. Cuando haya **running clubs**, mostrarlos ahí. Experiencias queda vacío hasta que haya |
| 5 | **Explorar no está optimizado para buscar experiencias** | Está pensado para clases. Se cruza con la feature en diseño "Experiencias: categorías y buscador propios" |

Todo Dart ⇒ build 27 o posterior.

## ⬜ Sección BEAUTY — a validar, NO construir (28/8)

Dos lugares (**uñas** y **cosmetología**) quieren entrar por promoción.
**Decisiones abiertas antes de sumar nada:**
- Validar que haya demanda real.
- Definir la comisión (¿la de clase, o una propia como la de workshop?).
- Cómo se implementa: ¿categoría común, o **servicio de precio fijo**? Ojo que
  la Tanda D ya resuelve "precio único sin franja", que es probablemente lo que
  necesita un servicio de belleza.

**No sumar todavía.**

## ⬜ Mantenimiento

Sanear los docs de esta carpeta · escribir el doc de eventos gratis (no existe;
ya hay material: la medición end-to-end con saldo 0 está hecha).

---

## 💡 Cosas aprendidas que conviene no volver a descubrir

- **La trampa del `config.toml`:** aparecio dos veces. Una edge function no
  declarada ahi cambia su `verify_jwt` en silencio al deployar. **Chequear antes
  de cada deploy.** Al 30/8 hay **11 declaradas**: `delete-account`,
  `cleanup-lista-espera`, `regenerar-grillas`, `acreditar-creditos-corporativos`,
  `aviso-alumnos-email`, `email-regalo`, `aviso-cobro-manana`,
  `reporte-mensual-estudios`, `mp-webhook`, `nueva-reserva-estudio-email` y
  `push-enviar`.
  ⚠️ **`email-confirmacion` y `resena-email` estan desplegadas y NO declaradas**
  (las dos con `verify_jwt = true`, que es lo que necesitan porque las invoca un
  trigger con el anon key). Si alguna vez se re-deployan, declararlas primero.
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
