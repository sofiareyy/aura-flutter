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
| ⬜ | **Tanda C** — build de Dart (19 items) | **lo próximo** · bloqueada por saber si el build 25 se subió |
| ⬜ | **Tanda D** — Modelo C de precios | arrancar por el DISEÑO de reglas, no por código |
| ⬜ | **Tanda E** — experiencias, esquema pesado, keys legacy | |
| ⬜ | **Negocio** (los sigue la usuaria) | aviso del fin de gracia · mail de confirmación |

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

## 🟡 Menores de la auditoría fresca — por prioridad, ninguno urgente

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

## ⬜ Tanda C — el build de Dart · **lo próximo**

Todo junto, un solo release. ⚠️ **Antes: confirmar si el 25 ya se subió.**

**✅ Hechos en el build del 25/8 (grupo 1, revisado en el build local y aprobado):**
- **Item 0 · formulario de grilla nuevo**: lista de horarios **por día** (chips con
  hora + precio de su franja, ej. `🌙 08:30 · 12 cr`), "+ agregar", "copiar a…",
  "Completar un rango…", botón deshabilitado hasta que todos los días tengan
  horario, confirmación día por día con precios y aviso de sala, sin
  "3 meses" (dice 9 semanas). Servicio: `crearHorariosFijosEnGrilla({horariosPorDia, duracionMin, payloadBase})`
  devuelve lo que confirmó el servidor (item 21). Test: `test/grilla_editor_smoke_test.dart`.
  Probado creando de verdad en Hot Clic: 3 grillas exactas, 27 clases, 0 dup, limpiado.
- **Item 20 · 24 h en todos lados**: tarjeta del panel `HH:mm` y los tres
  selectores de hora (grilla, clase suelta, edición) sin AM/PM.
- **"Cancelar clase" cancela la clase** (opción B, base + Dart): etiqueta
  **Cancelada** en las tres vistas del panel (lista, tabla semanal, grilla),
  oculta del lado alumna, mensaje legible al reservar, no se puede cancelar
  dos veces ni **editar** una cancelada; botón **"Reactivar clase"** (verde)
  que la vuelve reservable. RLS medida: alumna 0 filas, otro estudio 0 filas.
- **Sin botones "Generar 3 meses"** en Clases cargadas (el panel regenera al
  abrir y el cron cada noche).
- **"Descripción, sala y fotos"** siempre visible (era plegable, nadie lo
  cargaba) en los tres formularios.
- **Renglón ⓘ debajo de las pestañas** explicando el alcance: Horarios fijos =
  la serie, Clases cargadas = una fecha.
- **Tres errores de debug preexistentes**: `ConnectivityBanner` metía un `Stack`
  arriba de `MaterialApp` (sin `Directionality`, pantalla roja en cualquier
  build local); `_StatBox` (dashboard) y `_CountBox` (asistencia) devolvían
  `Expanded` y los callers los envolvían otra vez.

**✅ Grupo 2 del build (25/8, revisado y aprobado):**
- **Item 14 · Asistencia**: se sacó el filtro "solo HOY" del Build 20; la
  sección PRÓXIMAS vuelve a mostrar clases (6 de 11 estudios no tenían clase
  hoy y veían la lista vacía).
- **Item 17 · errores legibles**: los 4 puntos que mostraban el `PostgresException`
  crudo al estudio ahora muestran "Hubo un problema… escribinos a aura.hola.app@gmail.com"
  y el detalle va a `debugPrint`. Los borrados muestran el mensaje de la base
  (que ya viene en castellano).
- **Item 17b · `_deleteFixed`/`_eliminarGrillaCompleta` no se tragan errores**:
  función compartida `_borrarClasesDeHorario`; si una clase no se puede borrar
  (candado), el horario NO se toca y un diálogo dice cuál y por qué. Simulado
  en base: con una clase protegida, grilla conservada y 0 huérfanas.
- **Item 22 · RPC de nombres**: `estudio_nombres_alumnas(uuid[])` devuelve solo
  (id, nombre, email, **avatar_url**) de alumnas con reserva en clases del
  estudio; **la policy provisoria `usuarios_select_alumnas_de_mis_clases` se
  dropeó**. La usan Asistencia (lista + escaneo) y Cobros. En Asistencia cada
  asistente muestra foto + nombre + email. RLS medida: alumna 0, otro estudio 0,
  anon 401. Archivos: `FIX_RPC_NOMBRES_ALUMNAS_2026-08-25.sql` (v1) y
  `FIX_RPC_NOMBRES_ALUMNAS_v2_avatar_2026-08-25.sql` (suma avatar_url).
- **"Mis Alumnos" (modo gestión) escondido del menú del estudio**: hoy no lo
  usa nadie (0 estudios en gestión, 0 filas en estudio_alumnos) y confundía. La
  ruta, la pantalla y el servicio quedan intactos; reactivar = descomentar el
  `_NavItem` en `estudio_sidebar.dart`.

**Quedaron anotados de la revisión (no hechos):**
- "Excepción de la serie": editar UNA clase y después editar la serie pisa
  la edición individual. Marcar la clase como editada a mano y que la
  propagación la respete.
- "Pausar" un horario fijo (vacaciones) sin borrarlo: el generador ya saltea
  `activo=false`; falta el botón + cancelar sus futuras.
- Filtro para esconder las canceladas viejas en Clases cargadas.
- `17:30h` con la h al final, si se prefiere.

**Alto impacto — el motivo del build**
0. ✅ **Rediseño del formulario de grilla — HECHO el 25/8.** Causa clases
   fantasma y quejas (Tiwar 25/8; le va a pasar a Rock Studio). Relevado el
   25/8, diseño decidido, ver `DART_FORMULARIO_GRILLA.md`. En una línea:
   **la lista de horarios, POR DÍA, es la fuente de verdad y la vista previa a
   la vez**; el rango y "copiar a otros días" son atajos que *rellenan* la
   lista, no lo que se envía. Por día y no una sola lista: medido, 4 de los
   6 estudios con grilla tienen horarios distintos según el día.
   Descubrimiento clave del relevamiento: **hoy no existe forma de crear UN
   horario fijo semanal** — "Nueva clase" es evento único y "Crear grilla" es
   un generador por rango. Un Crossfit con 2 clases por día no tiene
   herramienta, y por eso Tiwar usó el rango como si fuera "hora de apertura".
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

✅ (hecho 25/8) 14. **(b) El listado de clases abajo del QR en Asistencia — REGRESIÓN.**
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

✅ (hecho 25/8) 17. **Que el panel no le muestre al estudio el error crudo de Postgres.**
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

22. 🔴 **RPC limpia para los nombres de alumnas — y dropear la policy provisoria.**
    El 25/8 se abrió `usuarios_select_alumnas_de_mis_clases` para desbloquear
    Asistencia hoy. Una policy habilita la **fila entera**: el estudio ve
    además `creditos`, `plan`, `codigo_referido`, `empresa_id`, `avatar_url`
    de esa alumna. No hay plata ajena ni CBUs, pero es más de lo que la
    pantalla necesita. **Arreglo:** una RPC `estudio_listar_asistentes(clase_id)`
    que devuelva sólo `(usuario_id, nombre, email, estado, codigo_qr)`,
    cambiar `_cargarAsistentes` para usarla (y de paso matar el N+1: hoy hace
    una query por asistente), y **`drop policy usuarios_select_alumnas_de_mis_clases`**.
23. **El `#BK-` que ve la alumna quedó en 4 dígitos.**
    `reserva_confirmada_screen.dart:433` hace `codigoQr.split('-').last`. Con
    los 12 hex sin guiones eso daba el código entero (`#BK-45DB492F6964`); con
    el formato `AURA-…` del 25/8 `.last` son los 4 dígitos al azar
    (`#BK-4571`). Sirve pero es débil. **Arreglo de una línea:** usar
    `split('-')[1]`, el bloque hex (`#BK-58E38EDA`).

17b. 🔴 **`_deleteFixed` y `_eliminarGrillaCompleta` no pueden tragarse errores** —
    **va con el 17, y es el que deja clases huérfanas invisibles.**
    `mis_clases_screen.dart:2681` (`_deleteFixed`, :4624 `_eliminarGrillaCompleta`):
    por cada clase futura de la grilla hacen `try{cancelar}catch(_){}` y
    `try{borrar}catch(_){}` **por separado**, y después borran la grilla
    **pase lo que pase**. Si el borrado de una clase falla —el candado del
    24/8 porque tiene una reserva `presente`/`completada`, un error de red,
    lo que sea— la clase queda **huérfana** (`horario_fijo_id` NULL por el
    `SET NULL`), **publicada, tomando reservas, e invisible en "Horarios
    fijos"**. El estudio cree que la borró. Medido el 25/8 simulando el
    camino exacto: `borradas 3 · falló y se tragó 1 · grilla borrada · 1
    huérfana publicada`. Desde el 25/8 el generador ya no crea encima de
    esa huérfana (no duplica), pero la huérfana sigue ahí.
    **Arreglo, en este orden:** (1) borrar las clases; (2) si **alguna**
    falló, **NO borrar la grilla**, parar y mostrar cuál y por qué — el
    mensaje del candado ya es legible (*"tiene alumnas anotadas / ya
    tomada"*); (3) sólo si todas se borraron, borrar la grilla. El detalle
    técnico sigue yendo a `debugPrint`, como en el 17.
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

20. ✅ **(hecho 25/8) La tarjeta del panel del estudio a 24 h.** `mis_clases_screen.dart:5017`
    usa `DateFormat('hh:mm a')` → *"01:30 PM"*. Es el **único** lugar de la app
    en 12 h y fue lo que confundió a Tiwar (leyó 13:30 como "1:30"). Cambiar a
    `HH:mm`. Rock Studio va a tener una grilla igual de densa: hacerlo en este
    build.
21. ✅ **(hecho 25/8) El snackbar de la grilla dice "N horarios creados" con `rows.length`**
    (`estudio_admin_service.dart:500`), contado en el cliente antes del insert.
    Con el guard del 25/8 un lote con duplicados se rechaza entero, así que ya
    no puede mentir por partes — pero el estudio ve el `23505` crudo por el
    item 17. Cuando se arregle el 17, ese mensaje ya viene legible desde la
    base (*"Ya tenés un horario fijo el lunes a las 08:00…"*): mostrarlo tal
    cual.

**Decisiones de producto — 2 de 3 CERRADAS el 25/8, no volver a preguntarlas:**
- ✅ **Cuál "gratis" gana: no hay conflicto.** Se usa el texto "gratis" para
  precio 0, sin definir precedencia, porque `_esGratuita` es de **modo
  gestión** y hoy no aplica a nadie (0 estudios en gestión, 0 filas en
  `estudio_alumnos`, 0 clases con `creditos = 0`). Los dos "gratis" no pueden
  coexistir en ninguna pantalla. Al implementarlo, dejar claro en el código
  que son cosas distintas: `_esGratuita` = "vos ya le pagás al estudio" (por
  usuaria) vs precio 0 = "esta clase es gratis para todos" (por clase).
- ✅ **El cartel de lista de espera SÍ muestra la posición exacta** (item 3).
- ⬜ Si debe existir el mail de confirmación de reserva → sigue abierta, en
  NEGOCIO.

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
