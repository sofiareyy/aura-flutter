# Pendiente (deuda de refactor): OAuth duplicado en las pantallas de auth

Fecha de la nota: 2026-08-19. Solo código, NO requiere CLI. No urgente.

## Qué se encontró

Los flujos de login social (Google + Apple) están **triplicados**:

- `lib/services/auth_service.dart` → `signInWithGoogle()` / `signInWithApple()`
- `lib/screens/auth/login_screen.dart` → `_loginWithGoogle()` / `_loginWithApple()`
- `lib/screens/auth/register_screen.dart` → `_loginWithGoogle()` / `_loginWithApple()`

`login_screen` y `register_screen` llaman a `Supabase.instance.client.auth.signInWithOAuth(...)`
**directo**, en vez de usar los métodos de `auth_service.dart`. Eso significa que
`auth_service.signInWithGoogle/Apple` **podrían ser código muerto** (verificar si
los llama alguien).

## Por qué importa

Cada cambio en el login (p.ej. el de `LaunchMode.inAppWebView` →
`externalApplication` del 2026-08-19) hay que hacerlo en **6 lugares** en vez de
uno. Es justo el tipo de duplicación donde un fix se aplica en 2 de 3 archivos y
queda un flujo roto sin que se note.

## Qué hacer (cuando se retome)

1. Confirmar si `auth_service.signInWithGoogle/Apple` se usa en algún lado.
2. Si es código muerto → borrarlo, o mejor: hacer que `login_screen` y
   `register_screen` llamen a `auth_service` y dejar UNA sola definición del
   flujo OAuth (con su `redirectTo`, `authScreenLaunchMode`, `queryParams`).
3. Al unificar, chequear que el manejo de `launched == false` y los SnackBars de
   error queden consistentes entre ambas pantallas.

No ampliar el alcance ahora: es refactor de estructura, no un bug activo.
