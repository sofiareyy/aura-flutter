# Modo visita — Piezas A y B

Fecha: 2026-08-20. **Estado: A y B COMPLETADAS, commiteadas y en producción.**
Falta la Pieza C (continuidad post-registro). Ver el detalle al final.

- Pieza A (gate del router + browse null-safe) → commit `19bd79f`
- Pieza B (muro cerrable + nav de invitado + home público) → probada en Chrome
  con los 9 puntos de la checklist, sin regresiones en el camino logueado.

Contexto: modo visita = un invitado (sin cuenta) puede navegar el marketplace de
SOLO LECTURA; para reservar/comprar tiene que registrarse. La seguridad ya está
cerrada (la capa de datos es read-only para el invitado por construcción: RPCs con
`auth.uid()`/`no_auth` grantadas solo a `authenticated`, checkouts que exigen JWT).
Pieza A es puro front (router + condicionar UI). Es CÓDIGO DE APP → va a un build.

## ✅ Completado (compila limpio, `flutter analyze` por archivo OK)

1. **Router** (`lib/core/router/app_router.dart`):
   - Helpers nuevos `_esBrowsePublica(loc)` y `_esEstudioDetalle(loc)`.
   - El gate (antes `if (!isLoggedIn) return '/login'`) ahora:
     `if (!isLoggedIn) return _esBrowsePublica(loc) ? null : '/login';`
   - Browse público para invitado: `/explorar`, `/mapa`, `/clase/:id`, `/estudio/<id numérico>`.
   - `/estudio/dashboard|clases|...` (palabra, no número) → sigue protegido (el panel NO se abre).
   - Todo lo demás (perfil, créditos, reservas, checkout, `/home`, admin) → sigue protegido.
   - El cambio vive 100% dentro del `if (!isLoggedIn)` → **logueado intacto**.

2. **Entrada "Explorar sin cuenta"** (link secundario, no reemplaza nada):
   - `lib/screens/auth/landing_screen.dart` (web): link crema debajo de los CTAs, arriba de "¿Ya tenés cuenta?". → `context.go('/explorar')`.
   - `lib/screens/auth/onboarding_screen.dart` (mobile): link gris al final, debajo de "Ya tengo cuenta". → `context.go('/explorar')`.

3. **Null-safe de las pantallas de browse:**
   - `mapa_screen.dart`: **0 cambios** — no usa al usuario, ya guest-safe.
   - `explorar_screen.dart`: **0 cambios** — la única dependencia (`_estudioAsociadoId` para el badge "Tu estudio") ya está null-guardeada (`if (_estudioAsociadoId != null)`), así que para invitado no muestra el badge, automático.
   - `detalle_estudio_screen.dart`: **ocultar el corazón de favorito** para invitado (envuelto en `if (currentUser != null)`). Reseñas se ven (se cargan siempre); botón "Dejar reseña" ya oculto por `if (canReview)` (false para invitado); `_registrarVista` ya null-safe (fire-and-forget).
   - `detalle_clase_screen.dart`: **dos cambios** — (a) guard al inicio de `_buildBottomAction`: invitado ve **"Registrate para reservar"** → `context.go('/register')` en vez del botón de reservar/waitlist; (b) ocultar la columna **"Tu saldo"** (envuelta en `if (currentUser != null) ...[divisor, saldo]`), dejando el **precio visible** (columna izquierda intacta). Cargas de usuario (yaReservado, esGratuita, enListaEspera, pre_confirmada, canReview) ya guardeadas por `userId.isNotEmpty`. Reseñas se ven.

Patrón en todo: `if (currentUser != null) { <UI de hoy exacta> } else { <invitado> }` → **el branch logueado no cambió una línea de comportamiento.**

## ✅ Pieza B — COMPLETADA (muro cerrable + nav + home público)

Resuelve los 3 problemas que salieron de la prueba real (ver sección de feedback).

1. **`lib/widgets/registro_muro.dart` (NUEVO)** — `RegistroMuro.mostrar(context,
   motivo:)` con `enum MuroMotivo { reservar, listaEspera, favorito, reservas,
   perfil }`. Es un `showDialog` (card centrada, máx 420) con **✕**, cerrable
   también tocando afuera y con el botón atrás.
   - **La raíz del bug**: antes era `context.go('/register')`, y `go` REEMPLAZA
     la ubicación → no quedaba nada a lo que volver y el invitado terminaba en
     el onboarding eligiendo "estudio o usuario". El muro **no navega**: se abre
     encima y al cerrarlo el invitado sigue donde estaba, con su scroll.
   - Los CTA usan `push` (no `go`) para que "atrás" desde el registro vuelva a
     la clase.
2. **Disparadores — solo ACCIONES, nunca navegación:**
   - `detalle_clase_screen`: reservar → muro `reservar`. Si la clase está llena,
     el botón dice "Registrate para anotarte" y abre el muro `listaEspera`
     (antes decía "reservar" aunque no hubiera lugar).
   - `detalle_estudio_screen`: el corazón **ahora SE MUESTRA al invitado**
     (antes estaba oculto, no sabía que la función existía) y abre el muro
     `favorito`.
3. **Nav de invitado (`main_shell.dart`)**: Reservas y Perfil abren el muro
   **sin navegar**. Inicio y Explorar libres. Navegar entre pestañas nunca
   expulsa a /login.
   - **Bug arreglado de paso**: `_selectedIndex` no conocía `/mapa` y caía al
     `return 0`, así que en el Mapa quedaba iluminado "Inicio". Ahora marca
     Explorar (el mapa es una vista de Explorar, se llega desde su toggle).
4. **Home público (opción A)**: `/home` entró a `_esBrowsePublica`. El invitado
   ve clases de la semana, Experiencias y estudios cerca. Cambios en
   `home_screen.dart`: card de créditos → `_InvitadoCard` ("Estás explorando
   como invitada / Creá tu cuenta"), campana de notificaciones oculta, avatar
   abre el muro. El QR de hoy y el banner de vencimiento ya se ocultaban solos.
   - Home resultó casi guest-safe de fábrica: todas las cargas cortan con
     `uid.isEmpty` (`_cargarSugerencias`, `getClasesSugeridas`, historial de
     créditos). Solo faltaba la UI.

**Camino logueado: sin cambios.** Todo dentro de guards de invitado. `flutter
analyze` 0 errores, 8 warnings (baseline), y 83 issues en vez de 84 (se fue el
lint `curly_braces` de main_shell, que estaba en el bloque reescrito).

## ⏳ Falta — Pieza C: continuidad post-registro

**Lo único pendiente del modo visita.** Cerrar el muro devuelve al invitado
donde estaba ✅, pero si **completa** el registro, el flujo lo lleva a
`/creditos-onboarding` como siempre, no de vuelta a la clase que estaba mirando.

Idea: guardar la intención (ruta + acción) antes de abrir el registro y
retomarla al terminar — que despues de crear la cuenta caiga en la clase y, si
se puede, con el flujo de reserva ya abierto.

Piezas menores que quedaron fuera:
- **Comprar créditos**: no es alcanzable desde el browse de invitado todavía, así
  que no hay dónde poner el muro.
- **Dejar reseña**: ya oculto por `canReview` (requiere reserva previa).

## ⏳ Notas viejas de la Pieza A (ya resueltas, se dejan por contexto)

1. **MainShell** (`lib/widgets/main_shell.dart`) — la nav inferior. Condicionar las
   pestañas **Perfil** (y **Home** si aplica) para invitado: que manden a `/register`
   (o se oculten). Explorar/Mapa quedan libres. **Leer primero la estructura del shell**
   para elegir ocultar vs muro. (Es la última pieza del null-safe.)
2. **Probar las DOS PUNTAS en Chrome** (`flutter run -d chrome`), no commitear hasta esto:
   - **Invitado:** entrar por "Explorar sin cuenta" → navegar explorar/mapa/detalle-estudio/
     detalle-clase; en la clase ver "Registrate para reservar" (no el botón); el precio visible;
     sin corazón ni "Tu saldo"; reseñas visibles. Y que ir a mano a `/perfil`, `/estudio/dashboard`,
     `/checkout` **mande a login** (no se cuele).
   - **Logueado (no-regresión, lo más importante):** con sesión, ver TODO igual que hoy —
     home, perfil, créditos, botón de reservar, saldo, corazón, todo.
3. **`flutter analyze` full + `flutter build web`** al terminar MainShell.

## Feedback de la prueba real en Chrome (2026-08-20) — TODO RESUELTO en la Pieza B

Probado con la Pieza A a medias (MainShell sin hacer) y ANTES del paso 7 de
`SEPARAR_DATOS_COBRO.md` (o sea, con `anon` todavía sin poder leer `estudios`):

1. **"Explorar sin cuenta" → "no se encontraron resultados".** ✔ Síntoma
   esperado y ya diagnosticado: `anon` no tiene policy de SELECT sobre
   `estudios`, así que `getEstudios()` devuelve vacío y `_attachEstudios` deja
   cada clase sin estudio. **Lo arregla el paso 7**, no es un bug de la Pieza A.
2. **Tocar "Inicio" abre el login.** Correcto según el gate actual (`/home` no
   está en `_esBrowsePublica`), pero la usuaria espera **poder ver el Home sin
   cuenta**. ⇒ Sube de prioridad la **Pieza D** (home de invitado), que estaba
   marcada como opcional. Decidir: Home público con CTA a registro, o que la
   pestaña Inicio no exista para invitado.
3. **UX del muro (importante):** cuando salta el login/registro, no hay forma de
   **cerrar y volver a explorar** — te devuelve al principio y hay que volver a
   elegir "soy estudio / soy usuario". ⇒ La Pieza B tiene que incluir un botón
   de cerrar / "seguir explorando" en el muro, y volver a la pantalla anterior,
   NO al onboarding. Esto es lo que más molestó en la prueba.
4. **"Ninguna página se deja ver sin cuenta excepto Explorar."** En parte por
   diseño (solo `/explorar`, `/mapa`, `/clase/:id`, `/estudio/<id>` son
   públicas), y en parte por el punto 1: como Explorar no muestra resultados, no
   se puede clickear hacia el detalle de clase ni de estudio, y el Mapa queda
   sin pins. Revalidar los 4 destinos DESPUÉS del paso 7.
5. **Logueado: todo OK.** Sin regresiones.

## Notas técnicas para retomar
- Guard de invitado usado en la UI: `Supabase.instance.client.auth.currentUser == null`.
- Router: helper `_esBrowsePublica`.
- Archivos tocados (sin commitear): `app_router.dart`, `landing_screen.dart`,
  `onboarding_screen.dart`, `detalle_estudio_screen.dart`, `detalle_clase_screen.dart`.
- La **barra de progreso** (`mi_perfil_screen.dart` + `reservas_service.dart`) es de otro
  tema (Tanda 2) — se puede commitear aparte, ya está probada.
- Después de A: **Pieza B** (muros reusables `requireAuth` + convertir favorito/reseña en
  "registrate"), **Pieza C** (continuidad post-registro), **Pieza D** (home de invitado, opcional).
