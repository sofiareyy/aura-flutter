# Auditoría de diseño visual — Aura

**Fecha:** 4/9/2026 · **Para:** Sofía · **Estado:** análisis, nada construido.
**Marco:** la gente compra por lo visual. Una app que se ve pro genera confianza y
la persona pone la plata; una que se ve amateur genera duda y abandono. Todo lo de
abajo está ordenado por cuánto mueve eso, no por cuánto me gusta.

Medido sobre el código real de las 9 pantallas de la alumna (Inicio, Explorar,
detalle de clase, registro, login, onboarding, perfil, confirmar reserva, reserva
confirmada) y los dos archivos de tema. Cada número de este documento sale de
contar, no de estimar.

---

## 0. El diagnóstico en tres frases

1. **Aura tiene una buena idea visual** —crema cálida, negro, un naranja con
   carácter, un anillo como símbolo— **pero no tiene un sistema**: en 9
   pantallas conviven 86 colores distintos escritos a mano, 19 tamaños de letra,
   14 radios de borde, 6 márgenes de página y 2 tipografías. Eso es lo que el
   ojo lee como "amateur" sin poder decir por qué.
2. **Lo que vende en este rubro es la foto, y Aura la trata como un dato más.**
   La primera pantalla completa del Inicio no tiene ninguna, y cuando aparecen
   están recortadas, repetidas y con fallbacks distintos en cada lugar.
3. **El sistema bueno ya existe adentro del repo.** Hay un segundo archivo de
   diseño (`aura_gestion_design.dart`) con tokens de espaciado, radio, sombra,
   una sola tipografía y un skeleton de carga. Lo usan **2 pantallas del
   estudio**. La alumna nunca lo ve.

---

## 1. Primera impresión: qué transmite hoy

Recorrido de una usuaria de la pauta, en el teléfono, por lo que ve antes de
tocar nada.

**Splash.** Fondo casi negro, un círculo marrón oscuro, el anillo naranja, "AURA."
con tracking abierto, y "MOVÉ. EXPLORÁ. VIVÍ." en gris. **Es lo más "marca" que
tiene la app**: contraste alto, un símbolo, una voz. Dura 2,2 segundos y después
nada de eso vuelve a aparecer.

**Onboarding.** Tres slides sobre crema, con título grande y una palabra en
naranja. Correcto, pero el artwork del tercero es una **X gris** de 44 px
(`Icons.close_rounded`), y no hay ni una foto de una persona haciendo algo. Para
una marca que se define como "gente que hace cosas", las primeras tres pantallas
no muestran a nadie haciendo nada.

**Inicio.** Saludo en 14 y 18 px, una tarjeta gris de "creá tu cuenta", una fila
de chips, y una tarjeta pidiendo ubicación. **La primera pantalla completa no
tiene una sola imagen.** La primera foto aparece en el segundo scroll, dentro de
tarjetas de 320 px donde la categoría, la dirección y la fecha están en grises
tan claros que en la calle no se leen (ver §3).

**Veredicto honesto:** se ve **limpia y ordenada, pero plana**. No se ve rota,
no se ve barata; se ve **genérica**: podría ser la app de cualquier cosa con
turnos. La personalidad que el splash promete no se sostiene. Da confianza
suficiente para no irse, pero no da ganas de quedarse. Y no muestra el producto
—la clase, el lugar, la gente— hasta bien abajo.

---

## 2. Identidad de marca: lo que hay y lo que falta

### Lo que está bien y hay que proteger

- **El naranja `#E8763A` con texto NEGRO en los botones.** Lo medí: negro sobre
  ese naranja da **5,87:1** de contraste; blanco daría **2,96:1**, que no pasa
  el mínimo. Es una decisión correcta y además distintiva —casi todas las apps
  ponen blanco sobre naranja. Es lo más "Aura" del sistema. **No cambiarlo.**
- **Crema + negro + un solo acento.** Es una paleta con temperatura, no un
  blanco de laboratorio. Bien.
- **El anillo del ícono.** Un símbolo simple, geométrico, memorable. Sirve.
- **DM Sans en los títulos**, con pesos 600/700. Es una buena elección: moderna,
  redonda, con carácter sin ser rara.

### Lo que rompe la identidad, con número

| Problema | Medido | Por qué importa para vender |
|---|---|---|
| **Dos tipografías.** El tema define DM Sans para títulos e **Inter para todo el cuerpo** (`app_theme.dart`, `bodyLarge/Medium/Small` y `label*`). | 2 familias | Inter es la tipografía por defecto de media internet. Cada párrafo, hint de input y etiqueta vuelve la app "cualquiera". Se cree que Aura usa DM Sans; usa DM Sans en 9 lugares y una fuente genérica en el resto. |
| **No existe un archivo de logo.** El único asset de imagen del repo es `google_logo.png`. El anillo del splash está **dibujado en código** (contenedores y bordes), y el ícono de la app es un PNG aparte. | 0 assets de marca | Sin un logo como archivo no hay consistencia entre app, web, App Store, mails, redes y la pauta misma. Cada superficie lo reinventa. |
| **Dos cremas.** `#F7F5F2` (25 usos) y `#F5F0E8` (10 usos). La que vos nombrás como "la crema de Aura" es la minoritaria. | 2 fondos | Sutil, pero es el tipo de cosa que hace que dos pantallas no "peguen" sin que nadie sepa por qué. |
| **86 colores escritos a mano** fuera de la paleta, en 9 pantallas. De ellos, **27 grises cálidos distintos** para "texto secundario" y **24 beiges** para fondos. | 86 hex · 196 usos | Ningún diseñador eligió 27 grises. Son 27 decisiones apuradas. El resultado es que los grises "vibran" entre tarjetas vecinas. |
| **El naranja casi no aparece fuera de los botones.** En Explorar, 13 usos en 1.563 líneas. | — | Las pantallas se leen beige-gris. El acento, que es lo que da energía, está racionado. |
| **Cero movimiento de marca.** 10 de 54 pantallas tienen alguna animación, todas funcionales (transición de slide, spinner). | 0 microinteracciones | Para una marca de "movimiento", nada se mueve. Un botón que no responde al toque se siente barato. |

**Conclusión de marca:** Aura tiene *materiales* de marca buenos (color, símbolo,
una tipografía) y **ninguna regla que los sostenga**. La identidad vive en el
splash y se disuelve a partir de la segunda pantalla.

---

## 3. Jerarquía visual y legibilidad: lo que el ojo no puede hacer

### El problema más caro y más barato de arreglar: texto invisible

Medí el contraste de los grises que la app usa para el texto secundario **sobre
el fondo crema**. El mínimo para texto normal es 4,5:1; para texto grande, 3:1.

| Dónde se usa | Color | Contraste | Estado |
|---|---|---|---|
| Categoría y barrio en la tarjeta de clase | `#D0C6BD` | **1,54:1** | invisible |
| `mutedText` de la paleta | `#B8B0A9` | **1,96:1** | invisible |
| Fecha y hora en la tarjeta de clase | `#B2A89F` | **2,15:1** | invisible |
| Dirección en la tarjeta de clase | `#A49B94` | **2,51:1** | no pasa |
| `grey` de la paleta (texto secundario general) | `#8A8A8A` | 3,17:1 | sólo para texto grande |
| Naranja como texto ("Ver todo", links) | `#E8763A` | **2,72:1** | no pasa |

**Traducido:** en la tarjeta de clase —la unidad de venta de la app— **tres de
los cinco renglones no pasan el mínimo de legibilidad**, y el link "Ver todo"
tampoco. En un teléfono al sol, la tarjeta muestra una foto, un nombre, y
manchas grises. Esto no es accesibilidad como trámite: es que **la información
que decide la reserva (cuándo, dónde) no se lee.**

### La jerarquía: todo pesa lo mismo

- **206 tamaños de letra escritos a mano contra 9 lecturas del tema** (23 a 1).
  Hay **19 tamaños distintos**, y **8 son contiguos**: 11, 12, 13, 14, 15, 16,
  17 y 18 px. Una escala tipográfica que va de a 1 px no es una escala: no hay
  saltos, así que nada resalta sobre nada.
- **El peso 700 se usa 96 veces y el 600, 42.** Casi todo es bold. Cuando todo
  es bold, nada lo es.
- **Los CTAs sí saltan** —el botón naranja lleno es claramente el más fuerte de
  cada pantalla— y eso está bien. Lo que compite con ellos no es otro botón, es
  el **ruido** alrededor: 5 grises distintos en una misma tarjeta.
- **Los títulos de sección** ("CERCA TUYO", "PARA VOS ✨", "CLASES ESTA
  SEMANA") están en 13 px con tracking, correcto como etiqueta, pero el emoji en
  uno solo rompe el sistema.

---

## 4. Espaciado y respiro: la diferencia pro/amateur, medida

Coincido con tu marco: el espaciado es lo que más separa "pro" de "amateur", y
acá hay números.

| Qué | Medido | Lectura |
|---|---|---|
| Márgenes horizontales de página | **6 distintos**: 12, 16, 18, 20, 22, 24 | El contenido no se alinea entre pantallas ni entre secciones de la misma pantalla. El ojo lo registra como "torcido". |
| Separaciones verticales (`SizedBox`) | 16 valores; **43% no son múltiplo de 4** | El segundo valor más usado es **18** (25 veces), que no pertenece a ninguna grilla. |
| Combinaciones de padding distintas | **64** | No hay tokens: cada tarjeta se acolchona a mano. |
| Radios de borde | **14 valores** distintos, de 2 a 24, y **tres literales para la misma pastilla** (999, 9999, 99) | Tarjetas vecinas con esquinas de 16, 18 y 20 no se ven "de la misma familia". |
| Sombras | 9 en total, **8 combinaciones únicas** | Cada tarjeta flota distinto. |

**El Inicio tiene 26 secciones apiladas.** No respira porque no tiene ritmo: la
separación entre secciones es 14, 18, 20, 22, 26 o 28 según el caso.

**El sistema del estudio ya resolvió esto.** `aura_gestion_design.dart` define
`horizontalPadding = 20`, `sectionSpacing = 24`, `cardRadius = 16`,
`buttonRadius = 12` y una sola `softShadow`. Es exactamente la disciplina que
le falta a la alumna, y está a un archivo de distancia.

---

## 5. Tarjetas, componentes y estados

### Estados: donde se ve el cuidado, o su ausencia

| Estado | Medido | Cómo se ve |
|---|---|---|
| **Carga** | 18 spinners sueltos. **0 skeletons** en pantallas de alumna. El paquete `shimmer` está instalado y sin usar; `AuraShimmerBox` existe y lo usan 3 lugares del estudio. En el Inicio, dos secciones **desaparecen** mientras cargan (`SizedBox.shrink`) y reaparecen de golpe. | Un círculo girando en un hueco crema. Las apps que se ven pro muestran la silueta de lo que viene. |
| **Vacío** | 7 estados vacíos son **un texto suelto**. Sólo uno (Explorar, "No encontramos resultados") tiene ícono, título, subtítulo y acción. | Un renglón gris en el vacío se lee como error, no como estado. |
| **Error** | 3 pantallas sin ningún estado de error (Inicio, Explorar, onboarding). Dos pantallas muestran `Center(Text('Clase no encontrada'))` **sin estilo**, en tipografía por defecto. | Cuando algo falla, la app deja de parecer Aura. |

### Fotos: cinco maneras de decir "no hay foto"

Para el mismo caso —falta la imagen— hay **5 estrategias**, **4 íconos
distintos** (`self_improvement`, `image`, `image_not_supported`, `broken_image`)
en **4 tamaños** (28, 42, 64, 86) sobre **4 colores de fondo** distintos,
incluido un **teal `#708B8E`** que no aparece en ningún otro lugar de la app. El
componente compartido `FotoRed`, que ya resuelve carga y reintento, está
adoptado en **2 de 9 pantallas**.

Y el problema de fondo, medido en la auditoría anterior: **0 de 118 clases
tienen foto propia**; todas heredan la del estudio. Un carrusel de Citra son N
tarjetas con la misma imagen.

### Las tarjetas en sí

La tarjeta de clase del Inicio (`HomeNearbyClassCard`) está **bien construida**:
foto 16:9 arriba, categoría, nombre en 16/700, estudio, fecha y pastilla de
créditos. La estructura es la correcta para el rubro. Lo que la hunde son los
tres puntos anteriores: grises ilegibles, radios y sombras propias, y la foto
repetida.

---

## 6. Referencias del rubro: qué hacen las que convierten

Sin inventar capturas que no vi, éstos son los patrones que comparten las apps
de reserva de fitness y experiencias boutique que se ven "pro", y qué tiene Aura
de cada uno:

| Patrón | Qué hace | Aura hoy |
|---|---|---|
| **La foto es el layout.** La tarjeta ES la foto, con el texto encima sobre un degradé oscuro abajo. La imagen ocupa el 100% y el texto vive dentro. | Vende el lugar antes que el dato. | La foto es un bloque arriba y el texto un bloque abajo, separados. Correcto, pero "de lista", no "de vidriera". |
| **Una tipografía, tres tamaños.** Título grande y pesado, cuerpo mediano, etiqueta chica en mayúsculas con tracking. Nada más. | La jerarquía se lee de un vistazo. | 19 tamaños, 2 familias. |
| **Un acento, usado poco y fuerte.** El color de marca aparece sólo en la acción principal y en un detalle por pantalla. | Cuando aparece, manda. | Bien en los botones; el resto es beige-gris sin energía. |
| **Mucho aire.** Márgenes de 20-24, secciones separadas por 32-40. | Aire = caro = confiable. | 6 márgenes, separaciones de 14 a 28. |
| **Skeletons al cargar.** Siluetas grises pulsando con la forma del contenido. | Percepción de velocidad y de cuidado. | Spinner suelto. |
| **Urgencia honesta.** "Quedan 2 lugares", "Hoy 18:30", una pastilla de color. | Empuja a decidir sin mentir. | El dato de lugares existe y no se muestra. |
| **CTA fijo abajo en el detalle.** "Reservar · 18 cr" siempre visible mientras se lee. | La acción no se pierde al scrollear. | Aura ya lo tiene. ✔ |
| **Microinteracciones.** La tarjeta se hunde al tocar, el botón confirma con un pulso, la reserva confirmada celebra. | La app "responde": se siente viva. | Cero. |
| **Fotos con personas.** Gente en movimiento, no salas vacías. | "Gente que hace cosas" tiene que verse. | Depende de lo que suba cada estudio; no hay guía. |

---

## 7. El hero del Inicio: cómo debería verse para enamorar

Esto es el Grupo B pendiente. Propuesta concreta, para que la mires y decidas.

### La idea en una frase

**Arriba de todo, una clase real a pantalla completa de ancho, con su foto grande,
sus datos encima y un botón de reservar.** No un banner de marketing: producto.

### Cómo se ve

```
 ┌──────────────────────────────────────────┐
 │ Buenas tardes                     [avatar]│   saludo chico, como hoy
 │                                          │
 │ ┌──────────────────────────────────────┐ │
 │ │                                      │ │
 │ │            FOTO DEL ESTUDIO          │ │   proporción 4:5 (más alta que
 │ │         (a sangre, sin borde)        │ │   ancha, como Instagram)
 │ │                                      │ │
 │ │  ░░░░░░░░ degradé oscuro abajo ░░░░  │ │
 │ │  BARRE · PALERMO                     │ │   etiqueta 11/600, tracking, crema
 │ │  Citra barre                         │ │   28/700 DM Sans, blanco
 │ │  Citra Barre · Mañana 18:30          │ │   14/400, crema al 80%
 │ │                                      │ │
 │ │  [ Reservar · 18 cr ]      ● ○ ○     │ │   botón naranja/negro + puntos
 │ └──────────────────────────────────────┘ │
 │                                          │
 │ VOLVÉ A TUS ESTUDIOS   ────────────────  │   lo que sigue, como hoy
```

- **Proporción 4:5** en el teléfono (en desktop, 2:1 como los heroes actuales).
  Es la proporción que el ojo asocia con "foto linda", no con "banner".
- **El texto va DENTRO de la foto**, sobre un degradé negro de abajo hacia
  arriba. Es el patrón del rubro y resuelve la legibilidad de una vez: blanco
  sobre negro al 70% siempre se lee.
- **Tres clases, deslizables**, con puntos. No rota sola: el movimiento
  automático en un hero distrae y baja la conversión.
- **La tarjeta de cuenta baja debajo del hero** y se achica a una línea en la
  cabecera ("12 créditos · vencen el 25/9"), como estaba en la auditoría de UX.

### Cómo se eligen las tres

Regla simple y honesta, sin curaduría manual:
1. Clases futuras de estudios activos, con lugar, en los próximos 7 días.
2. **Sólo estudios con galería de 3 fotos o más** (hoy 8 de 12): el hero no
   puede llevar una foto mala.
3. **Tres estudios distintos**, para que no sean tres horarios de Citra.
4. La más próxima de cada uno.
5. **Rotan por día** con la misma rueda pareja que ya usa "Destacados" en
   Explorar, para que el Inicio de hoy no sea el de ayer.

### Por qué esto convierte

Hoy la primera pantalla tiene cero fotos y un pedido de registro. Con esto, la
primera pantalla es **una foto grande de un lugar real, con una hora concreta y
un botón**. Es la diferencia entre "una app de reservas" y "quiero ir a esa".

### Lo que necesito que decidas

- La proporción (4:5 vs 3:4 vs 1:1).
- Si el hero muestra **una clase** o **un estudio** (mi propuesta: clase, porque
  tiene hora y botón de reservar; un estudio sólo tiene "ver").
- Si querés foto de "gente haciendo" en vez de la del estudio para los primeros
  3 o 4 estudios de la pauta: eso es pedirles fotos, no código.

Te armo una maqueta con 2 o 3 variantes antes de construir, como hicimos con la
foto de Explorar.

---

## 8. La lista, ordenada por impacto en conversión

Criterio de orden: **primero lo que cambia lo que la usuaria ve en los 10
primeros segundos y cuesta poco; después lo que cambia la percepción de calidad
en toda la app; al final lo cosmético.**

| # | Qué | Por qué mueve la aguja | Tamaño | Prioridad | ¿Decisión tuya? |
|---|---|---|---|---|---|
| 1 | **Arreglar los grises ilegibles de la tarjeta de clase** (categoría, fecha, dirección) y del link "Ver todo": un solo gris secundario que pase 4,5:1 (`#6E6761`, que ya existe en el código, da 5,1:1 sobre crema y 5,6:1 sobre blanco) | La unidad de venta hoy tiene 3 de 5 renglones que no se leen al sol. Es texto que decide la reserva. | Chico | **Máxima** | No |
| 2 | **Una sola tipografía: DM Sans en todo**, sacar Inter del tema | Cada párrafo y cada input dejan de ser "genéricos". Es un cambio de 6 líneas en el tema que se ve en 54 pantallas. | Chico | **Máxima** | No |
| 3 | **El hero del Inicio** (§7) | La primera pantalla pasa de cero fotos a una foto grande con un botón. Es el cambio de mayor impacto visual y de conversión de esta lista. | Grande | **Máxima** | **Sí**, ver §7 |
| 4 | **Una escala tipográfica de 5 tamaños en el tema** (11 etiqueta · 13 secundario · 15 cuerpo · 18 título · 26 display) y migrar los 206 literales | La jerarquía aparece sola: lo importante resalta porque hay saltos reales. | Mediano | Alta | No |
| 5 | **Unificar los dos sistemas de diseño.** Llevar los tokens de `aura_gestion_design.dart` (gutter 20, sección 24, radio 16/12, una sombra) al tema de la alumna, y **alinear el color del texto del botón a negro** en los dos (el del estudio usa blanco, que no pasa el contraste) | El sistema bueno ya existe; se trata de que la alumna también lo reciba. Cierra §4 entero. | Mediano | Alta | No |
| 6 | **Skeletons de carga** con `AuraShimmerBox` en Inicio, Explorar y detalle; y que ninguna sección "desaparezca" mientras carga | Es lo que más rápido hace que una app parezca cara. El componente existe. | Mediano | Alta | No |
| 7 | **Un solo fallback de foto** (`FotoRed` en todos lados, un ícono, un color) y **un tratamiento uniforme**: mismo degradé de legibilidad en todas las fotos con texto encima | Cinco maneras de decir "no hay foto" son cinco maneras de decir "no nos pusimos de acuerdo". | Chico | Alta | No |
| 8 | **Paleta a 12 tokens** y borrar los 86 hex a mano (27 grises → 2, 24 beiges → 3, 9 negros → 2, 5 naranjas → 1) | Los grises dejan de vibrar entre tarjetas vecinas. Es la limpieza que hace que todo parezca "de la misma marca". | Mediano | Alta | No |
| 9 | **Estados vacíos y de error con forma**: ícono + título + acción, un solo componente; y estilo para "Clase no encontrada" | Cuando algo falta o falla, la app sigue pareciendo Aura. | Chico | Media-alta | No |
| 10 | **El logo como asset** (SVG del anillo + logotipo "AURA."), usado en splash, web, mails y pauta; **una sola crema** (`#F7F5F2`) | Sin archivo de logo no hay marca consistente entre superficies. | Chico en código, decisión de marca | Media-alta | **Sí**: cuál de las dos cremas, y validar el logotipo |
| 11 | **"Quedan 2 lugares" y "Hoy 18:30" como pastillas** en la tarjeta de clase | Urgencia honesta con datos que ya viajan. | Chico | Media | No |
| 12 | **Tres microinteracciones**: la tarjeta se hunde al tocar (scale 0.98), el botón de reservar responde, y la pantalla de reserva confirmada tiene un pulso en el check | Para una marca de "movimiento", que algo se mueva. Barato y se siente en cada toque. | Chico | Media | No |
| 13 | **Un solo radio para pastillas** (999) y una escala de 3 radios (8 chip · 12 botón · 16 tarjeta); **una sola sombra** | Cierra los 14 radios y las 8 sombras. Cosmético pero visible. | Chico | Media | No |
| 14 | **Onboarding con foto real** de fondo en vez de la X, y "gente haciendo" en las 3 slides | Las primeras 3 pantallas tienen que mostrar el producto. | Chico en código, necesita 3 fotos | Media | **Sí**: las fotos |
| 15 | **Guía de foto para estudios**: 1 foto horizontal 3:2 de la sala con gente, 1 vertical 4:5 para el hero, sin texto ni logos encima | Es la única forma de que la vidriera tenga material bueno. No es código. | Gestión | Media | **Sí** |
| 16 | **El naranja como acento en una cosa más por pantalla** (la pastilla de créditos ya lo usa; sumar el subrayado del chip activo o el título de sección del hero) | Que la energía aparezca sin gritar. | Trivial | Baja | No |

**Si sólo se hacen tres antes de escalar la pauta: 1, 2 y 3.** El 1 y el 2 son
chicos, no piden decisiones y arreglan lo que más se nota en los primeros
segundos (texto que se lee, tipografía que no es la de todos). El 3 es el que
cambia la cara de la app, y es el que necesita que mires una maqueta.

**El bloque 4-5-6-7-8 es una sola tanda técnica**: "que la alumna reciba el
sistema de diseño que el estudio ya tiene". Es mediana, no pide decisiones, y
es la que convierte "limpia pero genérica" en "pro".

---

## 9. Lo que NO tocaría

- **Negro sobre naranja en los botones.** Está bien y es distintivo. La
  tentación de pasarlo a blanco hay que resistirla: no pasa el contraste.
- **La estructura de la tarjeta de clase.** Foto arriba, datos abajo, pastilla
  de créditos. Es la correcta; lo que falla es la ejecución alrededor.
- **El CTA fijo abajo en el detalle de clase**, con el hero 2:1 y su degradé.
  Es de lo mejor resuelto de la app.
- **Los mensajes de error en lenguaje humano** de la reserva.
- **La densidad de Explorar**: es un buscador y está bien que sea denso. Sólo
  hay que alinearle los márgenes.

---

## 10. Cómo se hizo esta auditoría

Leí el tema (`app_theme.dart`, `aura_gestion_design.dart`) y las 9 pantallas,
conté cada valor visual (colores, tamaños, radios, paddings, sombras, estados,
fallbacks de imagen) con un barrido automático sobre el código, y calculé los
contrastes con la fórmula estándar (WCAG). Miré el ícono de la app y el splash.
No usé un skill de "frontend-design" porque en esta sesión no existe con ese
nombre; el criterio estético es el de los patrones del rubro descritos en §6,
contrastado con lo medido.

*Los números cambian si se toca el código; el orden de la lista, no.*
