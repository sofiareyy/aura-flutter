# Modo visita — Pieza A (abrir el gate + browse null-safe)

Fecha: 2026-08-20. **Estado: EN PROGRESO, sin commitear** (los cambios están en el
working tree, en disco — no se pierden al abrir sesión nueva).

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

## ⏳ Falta (retomar acá)

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

## Feedback de la prueba real en Chrome (2026-08-20, la usuaria)

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
