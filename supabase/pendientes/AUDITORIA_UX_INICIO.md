# Auditoría de UX/UI — Inicio, Explorar y el camino a la primera reserva

**Fecha:** 4/9/2026 · **Para:** Sofía · **Estado:** análisis, nada construido.

Leída del código actual (`home_screen.dart`, `explorar_screen.dart`, onboarding,
registro, detalle de clase, checkout, reserva) y contrastada con los datos de
producción del mismo día. Donde digo "hoy hay 0 clases" no es una opinión: es
lo que devolvió la base a las 22:40.

---

## 0. Los números que condicionan todo

Antes de opinar sobre pantallas, lo que la app tiene para mostrar **hoy**:

| Dato (4/9, 22:40 ART) | Valor |
|---|---|
| Estudios activos | 12 |
| Estudios con clases en los próximos 7 días | 7 |
| Clases en los próximos 7 días | 118 |
| Clases que quedan HOY | **0** |
| Experiencias futuras (el diferencial) | **0** |
| Clases con foto propia (no la del estudio) | **0** de 118 |
| Estudios con ubicación cargada (para "Cerca tuyo") | 8 de 12 |
| Reseñas en toda la app | 2, en 1 estudio |
| Estudios en Pilar / en CABA | 6 / 4 (Palermo 2, Colegiales, Belgrano, Urquiza) + Escobar |
| Categorías del catálogo | 13, de las cuales **6 no tienen ni una clase esta semana** |

Esto importa porque **varias secciones del Inicio se ven vacías no por diseño
sino por contenido**, y ninguna mejora de UI arregla un carrusel de
experiencias con cero experiencias. La mitad de las sugerencias de abajo son
de pantalla y la otra mitad son de *qué mostrar cuando hay poco*.

---

## 1. La primera impresión, tal como es hoy

Recorrido de una usuaria que llega de la pauta a las 21:00 de un jueves,
instala, abre. Todo leído del código.

**Segundo 0 a 2,2:** splash negro con "AURA." y "MOVÉ. EXPLORÁ. VIVÍ." Son
**2,2 segundos fijos** (`splash_screen.dart:36`) antes de siquiera consultar la
red. Después vienen las llamadas de versión y sesión. El arranque real es
2,2 s más red.

**Segundo 3:** un onboarding de 3 slides. Textos correctos pero genéricos
("Tu mundo de experiencias", "Usá tus créditos como quieras", "Descubrí lugares
nuevos"). Detalles que bajan la calidad percibida:
- El slide 3 ilustra "Descubrí lugares nuevos" con **una X gris**
  (`Icons.close_rounded`, `onboarding_screen.dart:339`).
- "Más de 10 espacios en Buenos Aires" es un número chico, hardcodeado, y
  choca con el "Explorá cientos de clases" del otro onboarding.
- El botón que muestra producto, **"Explorar sin cuenta", es el de menor
  jerarquía** (texto gris). Los dos botones grandes llevan a un formulario.
- **No se marca como visto**: cada vez que abre sin sesión, vuelve a ver las
  3 slides.

**Camino que empuja la UI:** Siguiente → Siguiente → Empezar ahora → formulario
de registro. **Tres toques y todavía no vio una sola clase.** Una usuaria de
pauta que no está convencida se va acá.

**Si toca "Explorar sin cuenta"** cae en Explorar, no en Inicio. O sea que
**la vidriera, la pantalla pensada para enamorar, no la ve nadie que entre por
primera vez sin cuenta** salvo que toque la pestaña Inicio después.

**Cuando llega al Inicio como invitada, de arriba a abajo ve:**

1. "Buenas noches" / "Bienvenida ✦" y un avatar.
2. Una tarjeta gris: "Estás explorando como invitada. Creá tu cuenta y
   reservá tu primera clase" con Crear cuenta / Ingresar. **Es lo primero
   que ve, antes de cualquier clase.** Es un muro antes del contenido.
3. Una fila de chips de categoría. **13 chips**, entre ellos "Cerámica",
   "Recovery", "Spa", "Running club" y "Danza", que **no tienen ninguna
   clase esta semana**: tocar cualquiera de esos deja el Inicio en blanco
   ("No encontramos clases para esta semana en esta categoría"). Y aparece
   **"GRATIS"**, que en la base está desactivada: la consulta del Inicio no
   filtra las inactivas (`estudios_service.dart:16-22`).
4. **"CERCA TUYO"**: como no dio permiso de ubicación, ve una tarjeta pidiendo
   activarla. Cuando la active, el ranking es por distancia sobre 12
   estudios, **6 de los cuales están en Pilar**: desde Palermo, "cerca tuyo"
   muestra estudios a 50 km. Y 4 estudios no tienen coordenadas, así que
   nunca pueden salir cerca.
5. **"CLASES ESTA SEMANA"**: el carrusel más útil, con las 118 clases de la
   semana. Pero todas las tarjetas usan **la foto del estudio**, porque ninguna
   clase tiene foto propia: las 29 de Citra son 29 veces la misma imagen.
6. **"EXPERIENCIAS"**: hoy **no aparece** (0 experiencias). El diferencial de
   Aura no existe en la vidriera.
7. **"ESTUDIOS"**: carrusel de 12 tarjetas, orden alfabético.
8. **"TODAS LAS EXPERIENCIAS"**: **el título miente.** Esa sección lista
   `clasesFiltradas`, o sea **todas las clases**, en una grilla
   (`home_screen.dart:902` y `:982`). Una usuaria que busca experiencias baja
   hasta ahí y encuentra clases de funcional.

**Veredicto de primera impresión:** se entiende que es "una app para reservar
clases con créditos", pero **no se entiende qué la hace distinta**, la
pantalla arranca con un pedido (registrate) en vez de una promesa, y hay
tres cosas que huelen a inconsistencia en los primeros 30 segundos (chip
GRATIS, sección "experiencias" que son clases, la X del onboarding). La
sensación de "medio vacío" que describiste es real y tiene dos causas
distintas: una de contenido (experiencias 0, fotos repetidas, la mitad de
las categorías sin oferta) y una de orden (lo mejor está al medio, lo
administrativo arriba).

---

## 2. Diagnóstico del Inicio, por problema

### 2.1 Jerarquía invertida: lo administrativo arriba, la vidriera abajo
La primera pantalla completa (sin scroll) es: saludo, tarjeta de estado de la
cuenta, chips, y la tarjeta de ubicación. **Cero fotos.** La primera imagen de
una clase aparece recién en el segundo scroll. Para una pantalla cuyo trabajo
es enamorar, la foto tiene que ser lo primero.

### 2.2 Tres tarjetas de estado compiten por el mismo lugar
Invitada / plan con créditos / bienvenida sin créditos / sin créditos. Todas
ocupan el bloque de arriba y todas hablan de la cuenta, no de la oferta. Para
la usuaria nueva, dos de esas tarjetas son un pedido de plata antes de haber
visto qué compra. Hay además un bug: `_tieneHistorialCreditos` arranca en
`true` (`home_screen.dart:54`) y la cuenta recién creada **ve primero "Te
quedaste sin créditos"** (mensaje de alguien que gastó todo) y un instante
después "Bienvenida a Aura". Si la consulta falla, se queda con el mensaje
equivocado.

### 2.3 Los chips prometen categorías que no existen
13 chips para una oferta que hoy vive en 7. Cada chip vacío es un callejón.
"GRATIS" es directamente un dato interno que se filtró a la pantalla.

### 2.4 "Cerca tuyo" no es cerca para la mitad del país
Con la distribución actual, la sección funciona bien para una usuaria de
Pilar y mal para una de Palermo, que es probablemente a quien apunta la
pauta. Y pide permiso de ubicación como primera interacción de valor.

### 2.5 "Todas las experiencias" son clases
Es la sección más larga del Inicio y tiene el título equivocado. Es un bug de
copy con impacto de credibilidad: si dice experiencias y muestra funcional,
la usuaria aprende que los títulos no significan nada.

### 2.6 Las fotos se repiten
Con 0 clases con foto propia, un carrusel de una misma marca es la misma
imagen N veces. No es un problema de la app: es que las clases heredan la
foto del estudio. Pero se ve, y se ve en la sección principal.

### 2.7 Explorar tiene un "DESTACADOS HOY" que no es ni destacado ni de hoy
Son **los primeros 2 estudios en orden alfabético** de la lista filtrada
(`explorar_screen.dart:577`). Hoy: Ambra y Barre Estudio, siempre. El título
promete curaduría y entrega un `take(2)`. También hay un fallback de dirección
literal "Malabia 1510" (`explorar_screen.dart:1367`) que se mostraría si un
estudio no tuviera dirección cargada.

### 2.8 Sin prueba social
2 reseñas en toda la app, 1 estudio con rating. La pantalla de reseñas es
excelente, pero no hay nada que mostrar todavía. Mientras tanto, no hay ningún
otro elemento de confianza en el Inicio: ni "X personas reservaron esta
semana", ni fotos de gente, ni el nombre de una profe.

---

## 3. Qué le falta al Inicio para enamorar y convertir

Ordenado por lo que más mueve la aguja. La regla que seguí: **en una vidriera
con poco stock, se muestra lo mejor y se esconde lo que falta**, no al revés.

### 3.1 Un hero con una clase real, arriba de todo
No un banner de marketing: **la próxima clase reservable más linda**, a
pantalla completa de ancho, con foto, nombre, estudio, barrio, hora y precio
en créditos, y un botón "Reservar". Elegida por regla simple: la de mejor
foto (galería ≥ 3) más próxima en el tiempo con lugar. Rotando entre 3 o 4
con swipe. Es la diferencia entre "una app de reservas" y "quiero ir a esa".
**Por qué:** la primera pantalla pasa de cero fotos a una foto grande y una
acción. **Tamaño:** mediano. **Prioridad:** alta.

### 3.2 Mover la tarjeta de cuenta abajo del hero, y hacerla más chica
La invitada ve primero una clase, después el "creá tu cuenta". Para la
usuaria con cuenta, el saldo de créditos puede vivir como una línea en la
cabecera ("12 créditos · vencen el 25/9"), no como tarjeta. **Por qué:** el
Inicio deja de arrancar con un pedido. **Tamaño:** chico. **Prioridad:** alta.

### 3.3 Chips sólo de categorías con oferta esta semana
Se calculan de las 118 clases, no del catálogo. Hoy quedarían 7 chips, todos
con contenido. "GRATIS" desaparece solo. **Por qué:** cero callejones.
**Tamaño:** chico. **Prioridad:** alta. Es el arreglo más barato de la lista.

### 3.4 Arreglar el título "TODAS LAS EXPERIENCIAS" → "TODAS LAS CLASES"
O mejor, "ESTA SEMANA EN AURA". Una línea. **Tamaño:** trivial.
**Prioridad:** alta, por credibilidad.

### 3.5 Una sección de variedad: "Esta semana podés probar…"
Una fila de **categorías con foto y conteo real**: "Barre · 29 clases",
"Yoga · 22", "Funcional · 20". Es la forma de mostrar variedad cuando hay
7 estudios: la usuaria ve que hay de todo sin scrollear 118 tarjetas.
**Por qué:** responde "¿qué hay acá?" en un vistazo. **Tamaño:** mediano.
**Prioridad:** alta.

### 3.6 Experiencias: no mostrar la sección vacía, y cargar 2 o 3 reales
Hoy la sección se oculta sola cuando no hay (bien). Pero el diferencial de
Aura no puede estar ausente de la vidriera el día que entra la pauta. Esto
**no es Dart**: es conseguir que 2 o 3 estudios carguen una experiencia
(cerámica + vino, una salida de running, un taller) antes de encender la
pauta, y ahí sí darles el lugar de honor arriba de "Clases esta semana".
**Tamaño:** chico en código, grande en gestión. **Prioridad:** alta si la
pauta habla de experiencias; media si habla de fitness.

### 3.7 "Cerca tuyo" → "En tu zona", y sin pedir permiso primero
Reemplazar el ranking por GPS por un **selector de zona** con 3 o 4 opciones
reales según los estudios (Palermo / Norte de CABA / Pilar y zona norte /
Escobar). Sin permiso, sin sorpresa de 50 km, y la usuaria de Palermo ve sus
2 estudios y no 12. El GPS puede quedar como afinado opcional. **Por qué:**
saca el permiso del camino crítico y hace honesta la sección. **Tamaño:**
mediano. **Prioridad:** media-alta.

### 3.8 Foto propia por clase, o al menos por tipo de clase
Que el estudio pueda subir una foto por horario fijo (ya existe `imagen_url`
en clases y horarios; nadie la carga). Mientras tanto, **rotar la galería
del estudio** entre sus clases (8 estudios tienen ≥ 3 fotos): Citra tiene 5
fotos y hoy se usa siempre la primera. **Por qué:** el carrusel deja de
repetir. **Tamaño:** chico (rotar galería) / mediano (subida por clase).
**Prioridad:** media.

### 3.9 Prueba social honesta con lo que hay
Hasta que haya reseñas: mostrar en la tarjeta de clase **"Quedan 3 lugares"**
(el dato ya se trae, `lugares_disponibles`) cuando quedan pocos, y en la de
estudio **"12 clases esta semana"**. Son señales de actividad real, sin
inventar nada. **Tamaño:** chico. **Prioridad:** media.

### 3.10 Un mensaje de bienvenida con identidad, una sola vez
"Buenas noches / Bienvenida ✦" es correcto pero es de banco. Para la invitada,
un subtítulo bajo el saludo que diga qué es esto: **"118 clases y
experiencias esta semana en Buenos Aires. Reservá con créditos, sin cuota."**
Con el número real, calculado. Es la frase que hoy nadie dice en el Inicio.
**Tamaño:** trivial. **Prioridad:** alta.

---

## 4. El camino a la primera reserva: dónde se pierde gente

Mapeado toque por toque. Camino feliz en mobile, invitada a reserva:
**19 toques dentro de la app**, más el checkout de Mercado Pago, más el mail
de confirmación si aplica. Las fricciones, de más cara a más barata:

### 4.1 Después de pagar, se pierde la clase (el agujero más caro)
La usuaria llegó al checkout **desde una clase concreta** (paywall del
detalle). Al terminar, el único botón es **"Ir al inicio"**
(`checkout_screen.dart:236,680`). Nadie recuerda la clase. Tiene que volver a
Explorar, buscarla, entrar y reservar: **3 toques extra en el momento de
máxima intención, con la plata ya puesta.** El mecanismo para resolverlo ya
existe (`DestinoPostLogin` recuerda la ruta en el login); falta aplicarlo al
checkout. **Tamaño:** chico. **Prioridad:** máxima.

### 4.2 Registro con Google o Apple pierde la clase
El muro guarda `?volver=` y el registro por email lo respeta. **El registro
con Google/Apple no** (`register_screen.dart:49-140` nunca llama a
`DestinoPostLogin.recordar`). La usuaria que toca "Continuar con Google" cae
en Home sin la clase. Y si hay confirmación de mail, el "Entendido" también
la manda a login sin `?volver=`. **Tamaño:** chico. **Prioridad:** máxima.

### 4.3 Seis slides de tutorial antes de una clase
Tres del onboarding de auth y tres del de créditos, con el mismo mensaje sobre
créditos repetido. Recomendación: **un solo onboarding de 2 slides máximo**,
con foto real de fondo, y el de créditos convertirlo en **una línea dentro
del detalle de clase** ("Esta clase cuesta 18 créditos. 1 crédito ≈ $1.000")
que es donde la pregunta aparece de verdad. **Tamaño:** mediano.
**Prioridad:** alta.

### 4.4 El paywall tiene dos botones iguales
"Créditos insuficientes" muestra **dos veces "Comprar créditos"** con el
mismo destino (`detalle_clase_screen.dart:1712-1735`). Y el detalle muestra
**"Quedan -8 tras reservar"**, número negativo (`:984`). Los dos son bugs
visibles justo en el punto de venta. **Tamaño:** trivial. **Prioridad:** alta.

### 4.5 "Reservar" en toda la app, "Canjear" en el último botón
El botón de confirmación dice **"Canjear · 18 créditos"**
(`confirmar_reserva_screen.dart:462`). Es la primera vez que aparece la
palabra. Cambiar a "Confirmar reserva". Y si por algún camino se llega sin
saldo, esa pantalla es un callejón (botón muerto, sin link a comprar).
**Tamaño:** trivial. **Prioridad:** media-alta.

### 4.6 Después de la primera reserva, el botón grande es administrativo
"¡Reserva confirmada!" ofrece **"Ver mis reservas"** como primario (donde va
a haber una sola fila) y "Seguir explorando" como secundario. Invertirlos: el
momento de mayor entusiasmo es cuando se planta la segunda reserva.
**Tamaño:** trivial. **Prioridad:** media.

### 4.7 El detalle de clase no tiene barra de navegación
`/clase/:id` está fuera del shell: la invitada que entra desde un link de la
pauta a una clase **no ve las pestañas** y sólo puede volver atrás. Para
tráfico de pauta que llega a una clase directa, es la pantalla más
importante y es la más aislada. **Tamaño:** chico. **Prioridad:** media-alta
si la pauta linkea a clases.

### 4.8 Detalles de copy que restan
"Supabase" aparece en el texto del mail de confirmación
(`register_screen.dart:162`). El botón de Apple se muestra en Android y en web
de escritorio. El splash de 2,2 s. Ninguno mata la conversión; los tres bajan
la calidad percibida. **Tamaño:** trivial cada uno. **Prioridad:** media.

---

## 5. Calidad percibida: que se sienta pro y confiable

Cosas que no son features pero que la usuaria registra en los primeros 20
segundos.

- **Consistencia de títulos.** Hoy conviven "CERCA TUYO", "PARA VOS ✨",
  "CLASES ESTA SEMANA", "TODAS LAS EXPERIENCIAS", "DESTACADOS HOY". Un solo
  sistema: o todos describen el contenido con precisión, o ninguno lleva
  emoji. El "✨" solo en uno se lee como improvisado.
- **Fotos con tratamiento uniforme.** El fix de `resize=contain` del 2/9 ya
  arregló el recorte. Falta la consistencia de **proporción**: heroes 2:1,
  vidriera 16:9, buscador 3:2. Está bien que sean distintas por función, pero
  dentro de una misma pantalla que no convivan tres.
- **Estados vacíos con foto, no con texto.** "No encontramos clases para esta
  semana en esta categoría" es un texto gris en un hueco. Un estado vacío
  con una foto del estudio y "Todavía no hay Cerámica esta semana. Mirá
  Yoga →" convierte el callejón en un desvío.
- **Los números reales como lenguaje.** "Más de 10 espacios" suena a
  placeholder. "12 estudios, 118 clases esta semana" suena a producto vivo.
  Todo lo que sea un número, que salga de la base y no del código.
- **La X del slide 3.** Es el ejemplo perfecto de detalle que una sola
  persona nota y no olvida. Reemplazarla por una ilustración o una foto.
- **Densidad de Explorar.** Está bien que sea denso, es el buscador. Pero el
  bloque de arriba (título, subtítulo "Buenos Aires", buscador, chips,
  filtros, "DESTACADOS HOY") ocupa una pantalla entera antes del primer
  resultado en un teléfono de 375. Compactar a título + buscador + chips y
  mostrar resultados arriba del pliegue.

---

## 6. La lista, ordenada por impacto

| # | Qué | Por qué mejora | Tamaño | Prioridad |
|---|---|---|---|---|
| 1 | Checkout vuelve a la clase que motivó la compra (4.1) | Es el toque más caro: ya pagó y pierde la clase. 3 toques menos en el punto de máxima intención | Chico | **Máxima** |
| 2 | Registro con Google/Apple y confirmación de mail respetan `?volver=` (4.2) | Mismo agujero, en la puerta de entrada | Chico | **Máxima** |
| 3 | Hero con una clase real arriba del Inicio (3.1) | La primera pantalla pasa de cero fotos a una foto grande y un botón | Mediano | Alta |
| 4 | Tarjeta de cuenta abajo del hero, saldo como una línea (3.2) | El Inicio deja de arrancar con un pedido | Chico | Alta |
| 5 | Chips sólo con oferta real; chau GRATIS (3.3) | Cero callejones. Es el arreglo más barato de la lista | Chico | Alta |
| 6 | "TODAS LAS EXPERIENCIAS" → "ESTA SEMANA EN AURA" (3.4) | Un título que mentía | Trivial | Alta |
| 7 | Subtítulo de bienvenida con el número real (3.10) | Es la frase que hoy nadie dice: qué es Aura | Trivial | Alta |
| 8 | Un solo onboarding de 2 slides con foto; créditos explicados en el detalle (4.3) | De 6 slides a 2; la explicación de créditos aparece donde se pregunta | Mediano | Alta |
| 9 | Paywall sin botón duplicado; sin "Quedan -8" (4.4) | Dos bugs visibles en el punto de venta | Trivial | Alta |
| 10 | Fila "Esta semana podés probar…" con categorías + foto + conteo (3.5) | Muestra variedad con 7 estudios | Mediano | Alta |
| 11 | Cargar 2 o 3 experiencias reales antes de la pauta (3.6) | El diferencial no puede estar vacío el día que entra tráfico | Gestión | Alta si la pauta habla de experiencias |
| 12 | "En tu zona" con selector, GPS opcional (3.7) | Saca el permiso del camino y hace honesta la sección para CABA | Mediano | Media-alta |
| 13 | Detalle de clase con barra de navegación (4.7) | La pantalla a la que linkea la pauta no puede ser un callejón | Chico | Media-alta |
| 14 | "Canjear" → "Confirmar reserva"; y salida a comprar si no hay saldo (4.5) | Vocabulario consistente en el botón final | Trivial | Media-alta |
| 15 | Rotar la galería del estudio entre sus clases (3.8) | El carrusel deja de repetir la misma foto | Chico | Media |
| 16 | "Quedan 3 lugares" y "12 clases esta semana" en las tarjetas (3.9) | Prueba social honesta hasta que haya reseñas | Chico | Media |
| 17 | "Seguir explorando" como primario tras reservar (4.6) | Planta la segunda reserva en el pico de entusiasmo | Trivial | Media |
| 18 | Explorar: "DESTACADOS HOY" real o sacarlo; bloque superior más compacto (2.7, 5) | Hoy es un `take(2)` alfabético con nombre de curaduría | Chico | Media |
| 19 | Onboarding persistido como visto; splash a 800 ms (1) | 2,2 s y 3 slides repetidos en cada apertura sin sesión | Trivial | Media |
| 20 | Copy: sin "Supabase", Apple sólo donde corresponde, sin la X (4.8, 5) | Detalles que bajan la calidad percibida | Trivial c/u | Media |
| 21 | Estados vacíos con foto y desvío (5) | Convierte el callejón en camino | Chico | Nice to have |
| 22 | Títulos con un solo sistema, sin emoji suelto (5) | Coherencia | Trivial | Nice to have |
| 23 | Foto propia por horario fijo (3.8 largo) | Vidriera de verdad por clase | Mediano | Nice to have |

**Si sólo se hacen cinco antes de encender la pauta:** 1, 2, 5, 6 y 7. Son
todos chicos o triviales, no requieren decisiones de diseño, y entre los
cinco sacan los dos agujeros de conversión y las tres inconsistencias que se
ven en los primeros 30 segundos. El hero (3) es el que más cambia la cara,
pero es el primero que pide una decisión de diseño tuya.

---

## 7. Lo que está bien y no hay que tocar

Para que no se pierda entre tanto rojo:

- **El muro de registro cerrable** y el modo visita completo. Poder ver
  clases, estudios y reseñas sin cuenta es exactamente lo correcto para
  pauta. Y el muro vuelve a la clase (cuando el registro es por email).
- **Los mensajes de error de la reserva** ("La clase se llenó. Probá con otro
  horario o sumate a la lista de espera") son de los mejores textos de la app.
- **El permiso de ubicación no se pide solo**: aparece como tarjeta con
  explicación y botón. Mantener ese criterio si se hace la 3.7.
- **El permiso de push se pide después del login**, no en frío.
- **La pantalla de reserva confirmada** es completa: QR, cómo llegar, agregar
  al calendario, escribir al estudio. Sólo cambiar el orden de los botones.
- **Explorar como buscador denso** y el Inicio como vidriera es la decisión de
  producto correcta. Lo que falla no es la idea, es que la vidriera todavía
  no tiene vidriera: arranca con la cuenta y termina con un título equivocado.

---

*Todo lo de arriba se leyó del código del 4/9 y de la base ese mismo día. Los
números de la sección 0 cambian cada día; el orden de la lista, no.*
