/// Estado compartido del flujo de auth que cruza el arranque de la app
/// (main.dart <-> splash_screen.dart).
///
/// Se usa para el deep link de "olvidé mi contraseña": el evento
/// `passwordRecovery` puede llegar ANTES de que el splash resuelva su redirect
/// normal. Sin coordinación, el splash (que ve la sesión temporal de recovery
/// como "logueado") pisaría la navegación a /reset-password mandando al usuario
/// a /home. Este flag deja que el splash respete ese caso.
///
/// Es un flag en memoria: en un arranque en frío (proceso nuevo) vuelve a
/// `false` solo. Dentro de un mismo proceso el splash corre una sola vez, así
/// que no hay riesgo de que un recovery en caliente lo deje "pegado" para un
/// arranque posterior.
class AuthFlowState {
  AuthFlowState._();

  /// Lo marca el handler de `passwordRecovery`. El splash lo consume: si está
  /// en `true`, navega a /reset-password en vez de a /home.
  static bool pendingPasswordRecovery = false;
}
