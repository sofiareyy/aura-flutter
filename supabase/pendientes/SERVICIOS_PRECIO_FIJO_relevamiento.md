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

**Base (sale sin build, se aplica cuando quieras):**
- la tabla nueva + sus policies
- `calcular_precio_clase`: la búsqueda al principio
- los 2 triggers: pasar la categoría en vez de `null`
- `admin_recalcular_precios_estudio`: pasar la categoría (o saltear los fijos)
- `generar_clases_estudio`: que la etiqueta no pise `'servicio'`
- RPC `admin_set_servicio_precio` para el backoffice

**Dart (necesita build):**
- backoffice: pantalla para cargar "servicio + precio" por estudio
- panel del estudio: que al elegir el servicio muestre *"Sauna · 8 créditos
  (precio único)"* en vez del rango
- Explorar: que un servicio de precio fijo **no** muestre badge de valle/pico

> Ojo con la interacción: el badge "PRECIO REDUCIDO" que arreglé hoy compara
> contra `estudios.creditos_max`. Un servicio fijo de 8 en un estudio con techo
> 18 daría "precio reducido" siendo precio único. Hay que excluirlo.

## 5. Las 8 decisiones — TODAS CERRADAS el 2026-08-27

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

### Las 8, cerradas

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

### 🆕 Consecuencia que apareció con el caso real — decidir al construir

`study_categories` es **global**. Al crear "Sauna", "Ice bath" y
"Sauna + Ice bath", esos nombres aparecen en el multi-select de **TODOS** los
estudios: un estudio de yoga vería "Sauna" entre sus opciones.

**Recomendado:** filtrar la lista que ve cada estudio = las categorías
genéricas de siempre **+ sólo los servicios que tienen precio fijo para ESE
estudio**. Sale casi gratis porque la tabla nueva ya es por estudio, y evita
que el catálogo se ensucie para todos.

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

## 7. Conexión con el running club

Este mecanismo es también el que destraba la **clase gratis recurrente**
(ver `aura-running-club-caso-de-uso-modelo-c` en memoria): hoy es imposible
porque el trigger le pisa el precio con la franja. Un servicio de precio fijo
en 0 créditos es exactamente eso. Ya existe una categoría **"GRATIS"** suelta
en `study_categories` de esa exploración.
**Decidir si el mismo mecanismo cubre los dos casos** antes de construir dos.
