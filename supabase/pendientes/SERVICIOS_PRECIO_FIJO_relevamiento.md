# Servicios de precio fijo — relevamiento (Tanda D)

Medido contra la base el 2026-08-26. **Nada construido.**

Concepto: Aura configura desde el backoffice un precio fijo para un servicio de
UN estudio ("sauna de X = 8 créditos"). Cuando ese estudio carga un horario y
elige ese servicio, el precio se pone solo, **sin valle/pico**. Las clases
normales del mismo estudio siguen con su rango.

## 1. El hallazgo que hace esto barato

**`calcular_precio_clase(p_estudio_id, p_categoria, p_dia, p_hora)` ya recibe
`p_categoria`… y la ignora por completo.** Y **los tres llamadores le pasan
`null`**.

Esa función es el **único cuello** por donde pasa todo el precio del sistema.
Si la búsqueda del precio fijo vive ahí adentro, todo lo demás lo respeta solo.
No hay que tocar el generador ni inventar excepciones repartidas.

## 2. Quién pisa el precio hoy — son CINCO, no dos

| Quién | Cuándo corre | Qué hace hoy |
|---|---|---|
| `horarios_fijos_fija_precio` (trigger) | el estudio guarda un horario | **pisa** `creditos` con valle/pico. Pasa `null` de categoría. **Es el que bloquea la idea.** |
| `clases_fija_precio` (trigger) | se crea/edita una clase | **pisa** `creditos`. Pasa `null`. |
| `generar_clases_estudio` (cron 03:00) | todas las noches | ✅ **el PRECIO ya lo respeta**: `if coalesce(v_h.creditos,0) > 0 then v_creditos := v_h.creditos`. ⚠️ pero la **ETIQUETA** (`tipo_precio`) la recalcula siempre ⇒ un servicio fijo saldría marcado "valle" o "pico". |
| `admin_recalcular_precios_estudio` | cada vez que guardás precios en el backoffice | **pisa `clases` Y `horarios_fijos`**. El más peligroso: pasa por arriba de todo de una. |
| `admin_set_precio_clases_futuras` | manual | pone un número fijo a todas las futuras. |

> **La buena noticia:** el cron nocturno **no es el problema**. Ya respeta el
> precio del horario fijo (fix "D3"). El que pisa es el **trigger**, antes; el
> generador después propaga fielmente lo que el trigger dejó.

Los dos triggers salen por `if current_user not in ('authenticated','anon')`,
así que el cron (service_role) no los dispara. El daño ocurre **cuando el
estudio guarda desde la app**.

## 3. Dónde se guardaría el precio

⚠️ **No puede ir en `study_categories`: esa tabla es GLOBAL** (id, nombre,
activa — sin `estudio_id`) y ya tiene "Spa", "Recovery", "Meditación",
"Ceramica". El precio es **por estudio**, así que hace falta una tabla puente:

```
estudio_servicios_precio
  estudio_id  bigint  -> estudios(id)
  servicio    text                      -- la categoría/servicio
  creditos    int                       -- precio único
  activo      bool
  primary key (estudio_id, servicio)
```

Y `calcular_precio_clase` arranca con: *si hay fila activa para
(estudio, categoría) ⇒ devolver ese precio con `tipo = 'servicio'` y listo.*

## 4. Base vs Dart

👉 **Está en la sección 6b, completa.** Acá había un borrador del 26/8 que
quedó corto (le faltaban el `CHECK` de `tipo_precio`, el rechazo por trigger y
el filtro de categorías). Se sacó para que nadie lea la versión vieja.

Lo único de ese borrador que vale conservar acá, porque es una interacción con
otro arreglo: **el badge "PRECIO REDUCIDO" de Explorar compara contra
`estudios.creditos_max`**. Un servicio fijo de 14 en un estudio con techo 18
saldría marcado "precio reducido" siendo precio único. Hay que excluir
`tipo_precio = 'servicio'` del badge.

## 5. Las 9 decisiones — TODAS CERRADAS el 2026-08-27

### El caso real que define el diseño (palabras de la usuaria)

> Un estudio tiene: **yoga** (con pico/valle normal), **sauna**, **ice bath**, y
> **sauna+ice bath juntos** = 4 precios distintos. Yo, desde el backoffice,
> cuando ingresa ese estudio, configuro "sauna" con precio fijo (ej. 14
> créditos, siempre). **Otro estudio puede tener "sauna" a 18.** La misma
> categoría vale distinto según el estudio porque la configuro por estudio.
> **Sauna+ice bath juntos es su propia categoría con su propio precio.**

Dos cosas se desprenden y son parte del diseño:
- **El nombre del servicio es global, el precio es por estudio.** Por eso la
  tabla puente `estudio_servicios_precio (estudio_id, servicio, creditos)`.
  "Sauna" existe una vez; vale 14 en uno y 18 en otro.
- **Los combos son una categoría propia**, no una suma. "Sauna + Ice bath" es
  una fila más con su precio. Eso refuerza la regla de UNO SOLO por horario.

### Las 9, cerradas (la 9 está más abajo, después de la garantía)

| # | Decisión | **Cerrada así** |
|---|---|---|
| **1** | Qué campo identifica el servicio | **La categoría**, sin campo nuevo. Un trigger (`sync_categorias_*`, en las 3 tablas) deriva siempre `categoria := categorias[1]`, con tope de 5. Medido: **0 descoordinados en 115 horarios**. |
| **2** | Si hay varias categorías con precio fijo | **Rechazar el guardado** con mensaje claro: *"Elegiste dos servicios con precio fijo: Sauna (14 cr) y Ice bath (10 cr). Dejá uno solo."* ⚠️ **NO usar "gana la primera"**: el array se arma con `cats.add(c)`, o sea en el orden en que se va tildando, así que "la primera" es invisible y dos estudios que tildan distinto pagarían distinto sin enterarse. |
| **3** | Qué pasa con lo ya cargado | **Recalcular sólo las futuras SIN reserva.** Las que ya tienen reserva no se tocan. Es seguro: medido, tanto la liquidación (`netoReserva`) como las devoluciones (`cancelar_mi_reserva`, `estudio_cancelar_clase`) usan `reservas.creditos_usados` —el **snapshot** del momento de reservar—, no el precio actual de la clase. |
| **4** | ¿Saltea el bloqueo de "falta configurar el precio"? | **Sí.** Un estudio sólo-spa no tiene valle/pico y nunca los va a tener. Con un servicio fijo alcanza para cargar. |
| **5** | ¿Etiqueta propia? | **Sí**: `tipo_precio = 'servicio'`. Sin esto, Explorar miente (el badge de precio reducido compara contra `creditos_max`). |
| **6** | ¿Aplica a la clase suelta? | **Sí, a las dos.** No es por completitud: la clase suelta pasa por el mismo trigger `clases_fija_precio`, así que si el precio fijo vive dentro de `calcular_precio_clase` lo hereda gratis. Excluirla costaría trabajo y sería raro (cargar un sauna suelto es el caso típico). |
| **7** | ¿Misma comisión? | **Sí**, la de clase (`comision_aura`). No la de workshop. |
| **8** | ¿El sauna es una "clase"? | **Sí, se reusa `clases`.** Con cupo y duración propios. |
| **+** | Precio 0 = gratis | **Mismo mecanismo**, no se construyen dos. Cubre la clase gratis recurrente del running club. Medido: **`reservar_clase` ya soporta 0** (`if v_creditos > 0 then … consume`), o sea que reserva sin tocar el ledger y devuelve ok. No hay que tocar el camino de reserva. |

### ⚠️ La garantía: esto NO toca el pico/valle de nadie

El diseño es un **early return al principio de `calcular_precio_clase`**: si hay
fila de precio fijo para (estudio, categoría) devuelve eso; si no, cae en la
lógica de hoy **byte por byte igual**. Ambra, Citra, Sculpt, Tiwar, Yessi y YN
siguen exactamente igual.

**La precisión honesta:** para que funcione, los dos triggers tienen que
empezar a pasar la categoría en vez de `null`. Eso sí cambia un camino que hoy
usan todos. Pero la búsqueda sólo puede acertar si **existe una fila en la tabla
nueva**, y la tabla arranca **vacía** ⇒ ningún estudio actual cambia de precio
hasta que Aura cree una fila a propósito.

**Verificación obligatoria al aplicar:** recalcular todo y comprobar que los
precios dan **idénticos** a antes. Si algo se movió, la implementación está mal.

### 9 · Qué categorías ve cada estudio — CERRADA el 27/8

**Cada estudio ve las genéricas + SÓLO los servicios de precio fijo que Aura
configuró para ÉL.** El estudio de yoga **no** ve "Sauna"; el de wellness sí.
`study_categories` es global, así que sin este filtro "Sauna", "Ice bath" y
"Sauna + Ice bath" aparecerían en el multi-select de todos.

**Y esto sale 100% de BASE, sin build.** La lista no se lee de la tabla: sale
de la RPC `admin_list_studio_categories()`, que **no toma parámetros** y ya es
`SECURITY DEFINER` con `auth.uid()`. El filtro se mete adentro **sin tocar la
firma** ⇒ la app que los estudios ya tienen instalada empieza a ver la lista
filtrada sola.

⚠️ **Con una condición:** la misma RPC la usa el backoffice
(`admin_config_screen`, `admin_estudios_screen`), que necesita verlas TODAS
para poder asignarlas. El filtro tiene que ser condicional:
**si el caller es superadmin (`is_admin()`) → todas; si no → genéricas + las
suyas.**

## 6. Cómo lo ve el ESTUDIO al cargar — el diseño

**El problema a resolver:** hoy el estudio elige la categoría y el precio se
calcula solo por franja. Si elige "Sauna" (que Aura configuró a 14 fijos),
necesita **ver ahí mismo** que le va a salir 14 y que no cambia por horario —
sin tener que guardar y descubrirlo después.

### La pieza que ya existe y hace esto fácil

`PricingCalculator.calcular()` (`lib/utils/pricing.dart`) es el **espejo en
Dart** de `calcular_precio_clase`, y **ya recibe `String? categoria`… que
también ignora.** El mismo gancho está de los dos lados. Y `PricingResult` ya
trae `badge` y `detalle`, un sistema hecho para explicarle al estudio de dónde
salió el precio.

⇒ Alcanza con: sumar `TipoPrecio.servicio` al enum, cargar los servicios del
estudio en el panel, y pasarle la categoría elegida al cálculo.

### Lo que cambia en pantalla

**1. En el checklist de categorías — que se note ANTES de elegir.**
Las que tienen precio fijo para ese estudio llevan el precio en el propio chip:

```
  [ Yoga ]   [ Sauna · 14 cr ]   [ Ice bath · 10 cr ]   [ Sauna + Ice bath · 20 cr ]
             └── las de precio fijo se ven distintas y dicen cuánto
```

**2. En los chips de horario — el cambio principal.**
Hoy `_etiquetaHorario` arma `🌙 08:30 · 12 cr` (ícono de franja + precio de esa
franja). Con un servicio de precio fijo elegido, **desaparece el ícono de
franja** —porque no hay franja— y todos los horarios muestran lo mismo:

| | hoy (clase normal) | con "Sauna" elegida |
|---|---|---|
| chip 08:30 | `🌙 08:30 · 12 cr` | `08:30 · 14 cr` |
| chip 19:30 | `⚡ 19:30 · 18 cr` | `19:30 · 14 cr` |

Que dos horarios muy distintos muestren el mismo número **es la señal visual**
de que el precio no depende de la hora.

**3. Un renglón fijo arriba de la lista de horarios**, apenas se elige un
servicio de precio fijo:

```
  🏷️  Sauna · 14 créditos · precio único
      Este servicio no cambia por horario. Lo configura Aura.
```

Sale de `PricingResult.badge` / `.detalle`, que ya existen: sólo hay que
agregarles el caso `servicio`.

**4. En la confirmación día por día**, que ya lista los precios antes de crear,
la misma cifra repetida sin íconos de franja. Sin cambios de estructura.

**5. El mensaje de rechazo (decisión #2)**, al intentar guardar con dos
servicios de precio fijo:

```
  No se puede: elegiste dos servicios con precio fijo.
  Sauna (14 cr) y Ice bath (10 cr).
  Dejá uno solo, o pedile a Aura una categoría combinada.
```

La última línea es importante: le dice **cuál es la salida** (que Aura le cree
"Sauna + Ice bath" con su propio precio), en vez de dejarlo trabado.

### Lo que hay que traer que hoy no está

El panel **no conoce** los servicios de precio fijo del estudio. Hace falta
una lectura más en `_loadStudio` (una sola, junto a las que ya hace en
`Future.wait`): `{servicio → creditos}` para ese estudio. Con eso alcanza para
los 5 puntos de arriba.

**Regla de oro que ya rige en el archivo y acá también:** esto es sólo el
espejo para que la UI no mienta. **El precio final lo fija la base** con el
trigger. Si los dos no coinciden, manda la base y el espejo está mal.

## 6b. Qué sale de BASE y qué espera el BUILD

### 🟢 BASE — sale sin build, se puede tener andando antes

| Pieza | Detalle |
|---|---|
| Tabla `estudio_servicios_precio` + policies | `(estudio_id, servicio, creditos, activo)` |
| **Ampliar `clases_tipo_precio_check`** | ⚠️ **VA PRIMERO.** Hoy es `CHECK (tipo_precio in ('pico','valle','normal','experiencia'))`. Sin sumar `'servicio'`, el trigger revienta con **23514** en el primer guardado. |
| `calcular_precio_clase` | el *early return* del precio fijo |
| `horarios_fijos_fija_precio` | pasar la categoría en vez de `null` |
| `clases_fija_precio` | pasar la categoría en vez de `null` |
| `admin_recalcular_precios_estudio` | idem, para no pisar los fijos al guardar precios |
| `generar_clases_estudio` | que la etiqueta no pise `'servicio'` |
| **El rechazo de 2 servicios (decisión 2)** | mejor como **trigger en la base**, no sólo validación de Dart: así vale para cualquier camino |
| RPC `admin_set_servicio_precio` | para el backoffice |
| **El filtro de categorías (decisión 9)** | dentro de `admin_list_studio_categories()`, sin tocar la firma ⇒ **la app vieja lo aprovecha sola** |

### 🔵 DART — espera el próximo build

| Pieza | Detalle |
|---|---|
| Pantalla del backoffice | cargar servicio + precio por estudio (mientras tanto: por SQL) |
| `TipoPrecio.servicio` en el enum | + su `badge` y `detalle` en `PricingResult` |
| `PricingCalculator.calcular` | que **use** la `categoria` que ya recibe |
| Cargar los servicios en `_loadStudio` | una lectura más dentro del `Future.wait` |
| Los chips | precio en el chip de categoría · chips de horario sin ícono de franja |
| El renglón "precio único" | arriba de la lista de horarios |
| El mensaje de rechazo | el guard real vive en la base; esto es el texto amable |
| Explorar | que un `'servicio'` no muestre badge de valle/pico |

### ⚠️ El orden importa — y hay una trampa

**La mitad de base funciona sola: el precio va a salir bien.** Pero mientras
falte la mitad de Dart, **el estudio ve un número equivocado MIENTRAS carga**:
el espejo del panel (`PricingCalculator`) sigue calculando por franja, así que
el formulario le muestra `⚡ 19:30 · 18 cr` y la base guarda **14**. Al recargar
el panel aparece 14 (que es lo correcto), pero la confirmación día por día
—que lista los precios antes de crear— habría mentido.

**Recomendación operativa:** aplicar toda la base cuando quieras, pero
**no le entregues servicios de precio fijo a un estudio hasta que salga el
build**. Si necesitás uno andando antes, **cargale la grilla vos desde el
backoffice**: el precio queda bien y el estudio nunca ve el número equivocado.

**La única pieza de base que conviene aplicar YA, aparte:** el filtro de
categorías (decisión 9). No depende de nada más y mejora la app que los
estudios ya tienen instalada.

## 6c. PLAN DE CONSTRUCCIÓN — ✅ PASOS 1 y 2 HECHOS el 27/8 (la BASE está en producción)

**Aplicado:** `supabase/FEAT_SERVICIOS_PRECIO_FIJO_2026-08-27.sql` — los 8
ítems del paso 1, en orden. **El paso 2 (verificación) pasó entero:**

- **Huellas md5 idénticas** antes y después (clases futuras `3f7315d0…`, 977
  filas; horarios `314261c6…`, 115): ningún precio existente se movió. Además
  se corrió `admin_recalcular_precios_estudio` sobre los 11 estudios en una
  transacción descartada: mismo resultado.
- Con servicio "Spa" a 14 en Hot Clic: el horario nace a **14**, la clase nace
  a **14 · `tipo_precio='servicio'`**, y el **generador** crea sus clases a
  14/'servicio' (la etiqueta ya no pisa).
- **Dos servicios → rechazo** con el mensaje exacto: *"Elegiste dos servicios
  con precio fijo: Recovery (10 cr) y Spa (14 cr). Dejá uno solo, o pedile a
  Aura una categoría combinada."*
- Estudio **sin** servicio (Tiwar): la franja sigue mandando, trigger y regla
  coinciden.
- **Gratis:** servicio a 0 → la clase nace 0/'servicio' (running club listo
  del lado base).
- **Decisión 4:** un estudio sin créditos configurados no puede cargar
  ("Falta configurar…"), pero **con** un servicio sí — a su precio.
- **Filtro de categorías (decisión 9):** Tiwar no ve "Sauna PRUEBA", el admin
  de Hot Clic sí, el superadmin ve todas. **Ya rige para la app instalada.**
- **RPC `admin_set_servicio_precio`:** upsert + recalcula futuras SIN reserva
  (12→14/'servicio') y **respeta** la que tiene reserva (queda 12/'normal').
- Nada quedó suelto: 0 servicios cargados, 0 categorías de prueba, ledger
  87=87.

**⚠️ Sigue vigente la regla 3** (build 27 = **1.0.7**, el versionado que usa la
usuaria): NO entregarle el alta de servicios a ningún estudio hasta ese build.

✅ **Y que quede claro cuál NO es el motivo:** el 29/8 se verificó que
`tipo_precio = 'servicio'` **NO rompe las apps viejas**. El build 24 lee ese
campo como string suelto en un `if/else` de `==`, así que `'servicio'` cae en
el else y la clase se muestra sin badge. El `enum TipoPrecio` con su `switch`
nunca se construye desde esa columna (sale de `estudios.tipo_precio`, que es
`'fijo'`/`'rango'`), y no hay ningún `byName` que pudiera lanzar. **Ninguna
sesión debe frenar la carga de servicios por ese miedo.** El detalle en
RETOMAR.

El motivo real, el único: el espejo del panel todavía calcula por franja y
le mostraría un número equivocado mientras carga. Si hace falta uno antes, la
grilla la carga Aura desde el backoffice (el precio queda bien).

### El plan original (referencia)

**El proyecto está 100% definido: no queda ninguna decisión abierta.** Esta
sección es el orden de trabajo, no una lista de cosas a decidir.

### Reglas de la usuaria para esta construcción (2026-08-27)

1. **La base se aplica EN la sesión de construcción**, con todo junto. No antes,
   ni por partes.
2. **El filtro de categorías (decisión 9) NO se aplica suelto**, aunque salga
   sin build y mejore la app ya instalada. Va con el resto, para verificar las
   dos puntas bien de una sola vez.
3. **No se le entregan servicios de precio fijo a un estudio para que cargue él
   hasta que salga el build 27** (la parte visual). Ver la trampa del orden en
   6b.
4. **Si hace falta un estudio de servicios andando antes del build 27: la
   grilla la carga Aura desde el backoffice.** El precio queda bien y el
   estudio nunca ve el número equivocado.

### Orden sugerido

**Paso 1 — base, en este orden (el primero no es opcional):**
1. Ampliar `clases_tipo_precio_check` para aceptar `'servicio'`. **Si no va
   primero, el trigger revienta con 23514 en el primer guardado.**
2. Tabla `estudio_servicios_precio` + policies.
3. El *early return* en `calcular_precio_clase`.
4. Los dos triggers pasando la categoría; `admin_recalcular_precios_estudio`
   igual.
5. `generar_clases_estudio`: que no pise la etiqueta `'servicio'`.
6. El trigger que rechaza dos servicios de precio fijo en un mismo horario.
7. El filtro dentro de `admin_list_studio_categories()`, condicionado a
   `is_admin()`.
8. RPC `admin_set_servicio_precio`.

**Paso 2 — la verificación que NO se puede saltear:**
- **Recalcular todo y comprobar que los precios dan IDÉNTICOS a antes.** La
  tabla arranca vacía, así que ningún estudio actual puede cambiar. Si algo se
  movió, la implementación está mal. Números de referencia contra los que
  comparar (medidos el 26/8, re-medir antes de tocar):
  `normal 452 · valle 371 · pico 174` en clases futuras no canceladas.
- Las dos puntas con cuentas reales: un estudio **con** servicio fijo carga y
  le sale el precio único; un estudio **sin** servicio sigue con su valle/pico
  intacto.
- Que el rechazo de dos servicios frene de verdad, y que uno solo pase.
- Que el filtro de categorías: el estudio de yoga **no** ve "Sauna", el de
  wellness **sí**, y el backoffice sigue viéndolas **todas**.

**Paso 3 — Dart (build 27):** las 8 piezas de la tabla azul de 6b.

### ✅ 30/8 — Pieza 1 HECHA: `PricingCalculator` usa las categorías

El espejo del panel ya da **el mismo número que la base** para cualquier caso.
`lib/utils/pricing.dart`:

- `calcular(...)` recibe `categorias` (el array de los chips). Antes de todo
  —incluido el "falta configurar"— busca un servicio de precio fijo entre esas
  categorías en `estudio['estudio_servicios_precio']`, espejo exacto de
  `servicio_precio_fijo`: 0 → sigue como siempre · 1 → ese precio, tipo
  `servicio` · 2+ → `PricingResult.conflicto` con el **mismo texto** que lanza
  la base (no se lanza: corre dentro de `build()`).
- **Los servicios viajan dentro del row del estudio**, como `horarios_config`:
  `getCurrentStudio()` embebe `estudio_servicios_precio(servicio,creditos,activo)`
  por la FK real. RLS medida: la dueña de Hot Clic ve su fila, Citra ve 0.
- `TipoPrecio.servicio` con `badge` "Precio único" / `detalle` "Este servicio
  no cambia por horario. Lo configura Aura."
- Plomería en `mis_clases_screen.dart`: los 4 formularios pasan `cats` a
  `_precioDe`, `_creditosFinal`, `_PrecioCalculadoField` y al resumen día por
  día de la grilla. El campo de precio calcula ANTES de mirar la config (mismo
  orden que la base) y muestra el texto del conflicto si hay dos servicios.

**Verificado contra la base, no contra notas** — `test/pricing_test.dart`,
14 tests, con los números que devolvió producción el 30/8:

| Caso | Base | Espejo |
|---|---|---|
| Hot Clic + `['Spa']` (8) | 8 / servicio | 8 / servicio |
| `['Pilates','Spa']` | 8 / servicio | 8 / servicio |
| `['Pilates']` · `[]` · `null` · servicio inactivo · `'spa'` | 12 / normal | 12 / fijo |
| `['Spa','Recovery']` | excepción P0001 | `conflicto` con el mismo texto |
| sin `creditos_min` + `['Spa']` | 8 / servicio | 8 / servicio |
| experiencia + genérica / + servicio | 12 / experiencia · 8 / servicio | idem |
| Sculpt lun 09:15 · 19:00 · sáb 09:00 · 08:59 | 14 · 16 · 16 · 16 | idem |
| Citra mié 18:00 · Tiwar lun 08:30 · 12:30 | 18 · 11 · 14 | idem |
| **974 clases futuras reales** (foto en `test/fixtures/`) | lo guardado | **974 de 974** |

`flutter analyze` 0 errores · 16 tests OK · web compila.

### ✅ 30/8 — Piezas 2 y 3 HECHAS: chips con precio + renglón "precio único"

- **`CategoriasChecklist`** recibe `precios: {servicio → créditos}` (sale de
  `PricingCalculator.preciosServiciosDe(estudio)`, sólo activos). La categoría
  que es servicio se dibuja `Sauna · 14 cr`, en color primario, con el ícono
  🏷️ (`sell_outlined`) mientras no está marcada — marcada, el tilde lo
  reemplaza. **Con `precios` vacío el código es el de siempre**: los 3 usos del
  panel lo pasan; el backoffice y el perfil del estudio no lo pasan y no cambian.
- **`_ServicioPrecioBanner`** arriba de `_HorariosPorDiaEditor` en el form de
  grilla: `🏷️ Sauna · 14 créditos · precio único` + el `detalle` de
  `PricingResult`. Sin servicio no dibuja nada (`SizedBox.shrink`).
- **Cabo suelto de la pieza 1, cerrado:** el editor de horarios recibía
  `_etiquetaHorario` como tear-off, así que sus chips de hora NO tenían las
  categorías (el resumen sí). Ahora `etiqueta: (d, t) => _etiquetaHorario(d, t, cats)`.
- `test/categorias_checklist_test.dart` (5 tests): **el caso normal sin
  servicios muestra sólo los nombres, sin " cr" ni ícono**; con servicio, sólo
  ese chip cambia. 21 tests OK · analyze 0 · web compila.

### ✅ 30/8 — REGLA A: el servicio es la ÚNICA categoría (agujero cerrado)

**El agujero (catch de la usuaria, medido con la cuenta real de Hot Clic):**
el estudio podía tildar su servicio en cualquier clase — `['Yoga','Spa']` — y
cobrar el precio del servicio en una clase que no lo es. En las dos
direcciones: caro = la alumna paga de más; barato = baja la comisión (%) de
Aura. Era la única palanca de precio en manos del estudio.

**La regla, confirmada:** si hay servicio, es la única categoría. Sin atar el
nombre (texto libre, no participa del precio, atarlo no protege nada).

- **Base:** `FEAT_SERVICIO_CATEGORIA_UNICA_2026-08-30.sql` — el rechazo vive en
  `servicio_precio_fijo`, por donde pasan los 3 caminos (clase, grilla,
  recálculo). Aplicada y verificada 8/8: crear y editar `['Yoga','Spa']` →
  rechazo con mensaje claro · `['Spa']` sola → 8/servicio · `['Yoga','Pilates']`
  común → 12 como siempre · dos servicios → el mensaje del 27/8 intacto ·
  grilla mezclada → rechazo, sola → pasa · **huellas md5 idénticas** antes y
  después (974 clases, 121 horarios: ningún precio se movió).
- **Running club, decidido:** categoría **global** "Running club" con precio
  **0 por estudio** (la PK de la tabla puente ya es (estudio, servicio): el
  nombre nombra la cosa, el precio va aparte). Medido punta a punta en
  rollback: categoría + `admin_set_servicio_precio(_, 'Running club', 0)` +
  clase del estudio → **0 créditos · 'servicio'**. Nada de "GRATIS" pegado a
  otra categoría.
- **"GRATIS" desactivada del catálogo** (30/8, por `admin_toggle_studio_category`,
  0 usos medidos antes). Obsoleta con este diseño y peligrosa tildable.
- **Dart:** `servicioDe` espeja el rechazo con el mismo texto (test con el
  mensaje literal de producción), y el form **destilda solo**:
  `CategoriasChecklist.aplicarToggle` — tildar un servicio destilda lo demás,
  tildar una común destilda al servicio, tope de 5 intacto. 5 tests de la
  regla + 2 nuevos de pricing (mezcla → conflicto · running club a 0).
  ⚠️ El test "servicio + genérica → 8" del 30/8 a la mañana quedó obsoleto
  por la regla y ahora espera el rechazo — no es una regresión, es el cambio.

**Lo que sigue (piezas 4–8):** pantalla del backoffice para cargar
servicio+precio · snackbar de rechazo al guardar (el campo ya muestra el
conflicto) · Explorar sin badge "precio reducido" para `'servicio'` · chips de
horario sin ícono (✅ ya sale solo) · cargar servicios (✅ ya viene en el embed).

## 6d. ⏸️ Explorar busca por ESTUDIO, no por clase — decisión de diseño aparte (30/8)

Relevado el 30/8, **no se construye en esta tanda**. Sofía quiere que la
alumna pueda buscar "sauna" y encontrar los turnos. Hoy no funciona, y no es
un bug: Explorar fue diseñado para buscar **estudios**.

**Cómo es el modelo hoy:**
- Servicio y categoría **son la misma cosa** (decisión 1). "Sauna" es una fila
  de `study_categories` a la que Aura le colgó un precio para un estudio.
  El match del precio es `esp.servicio = any(clases.categorias)`.
- El estudio **elige, no escribe**: `CategoriasChecklist` son `FilterChip`s,
  no hay campo de texto. Y `admin_set_servicio_precio` rechaza un nombre que
  no esté en el catálogo. El string es idéntico por construcción.
- **Los chips de categoría de Explorar/Inicio/Mapa** salen de
  `study_categories` **sin filtro** (`estudios_service.getCategorias()`):
  "Sauna" aparecería como chip para todas las alumnas apenas exista.
- **Pero el filtro mira `estudios.categorias`** (el perfil del estudio), no
  `clases.categorias` (`explorar_screen.dart:154`, `mapa_screen.dart:78`). La
  lista de clases sólo se filtra por "clases de los estudios que pasaron"
  (`_clasesConEstudio`) + día + horario. La búsqueda de texto tampoco lee
  clases.
- **Ya está desincronizado hoy sin servicios:** Yessi declara "Fitness" y sus
  168 clases son "Gym / Funcional" ⇒ tocar ese chip no la muestra. Sculpt y YN,
  igual.
- Agujero menor de la decisión 9: el estudio edita las categorías de su
  **perfil** con `getCategorias()` sin filtro (`perfil_estudio_screen.dart:547`)
  ⇒ el de yoga puede tildar "Sauna" en el perfil.

**Los dos caminos, para la sesión de diseño:**
- **A · parche de base, sin build:** `admin_set_servicio_precio` suma el
  servicio a `estudios.categorias`. El chip "Sauna" muestra al estudio (con
  todas sus clases). Coherente con el modelo actual. **Se ve cuando se activen
  servicios, no antes.**
- **B · el diseño real (Dart):** Explorar filtra y busca **también por
  `clase.categorias` y `clase.nombre`**. Es decidir qué es Explorar (¿estudios,
  turnos, o las dos?). **Se piensa UNA vez para servicios + experiencias +
  running juntos.** La pregunta concreta para Sofía: *"cuando tocás Sauna,
  ¿querés ver estudios o querés ver turnos?"*

**Paso 4 — después del build:** recién ahí, entregarle el alta de servicios a
los estudios.

## 7. Conexión con el running club

Este mecanismo es también el que destraba la **clase gratis recurrente**
(ver `aura-running-club-caso-de-uso-modelo-c` en memoria): hoy es imposible
porque el trigger le pisa el precio con la franja. Un servicio de precio fijo
en 0 créditos es exactamente eso. Ya existe una categoría **"GRATIS"** suelta
en `study_categories` de esa exploración.
**Decidir si el mismo mecanismo cubre los dos casos** antes de construir dos.
