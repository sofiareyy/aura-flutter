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

/// A dónde quería llevar una notificación tocada con la app CERRADA (29/10/2026).
///
/// El problema: al tocar el aviso, la app navegaba a los 200 ms, pero el
/// splash espera ~2 s y después hace `go(destino del rol)`, que pisaba esa
/// navegación. Resultado: con la app cerrada, ningún aviso llevaba a ningún
/// lado (Inicio, o el selector de acceso si la cuenta tiene estudio).
///
/// Ahora, mientras el splash no decidió, la ruta se GUARDA acá y el splash va
/// a ella en vez de al destino del rol. Si el splash ya decidió (app abierta o
/// en segundo plano), se navega en el momento, como antes.
class NavegacionNotificacion {
  NavegacionNotificacion._();

  static bool _splashResuelto = false;
  static String? _pendiente;

  static bool get splashResuelto => _splashResuelto;
  static String? get pendiente => _pendiente;

  /// Un toque de notificación quiere ir a [ruta]. Devuelve `true` si hay que
  /// navegar YA (el splash ya decidió); `false` si quedó guardada para el
  /// splash.
  static bool registrar(String ruta) {
    if (_splashResuelto) return true;
    _pendiente = ruta;
    return false;
  }

  /// El splash lo llama justo antes de navegar con sesión: devuelve la ruta
  /// de la notificación si había una, o la del rol.
  static String resolverDestino(String destinoDelRol) {
    _splashResuelto = true;
    final r = _pendiente;
    _pendiente = null;
    return r ?? destinoDelRol;
  }

  /// El splash decidió sin usar la notificación (sin sesión, actualización
  /// obligatoria, recuperar contraseña): la ruta guardada se descarta.
  static void descartar() {
    _splashResuelto = true;
    _pendiente = null;
  }

  /// Lleva a [ruta] por el toque de una notificación usando [navegar].
  /// Si el splash todavía no decidió, la deja guardada para él (y por las
  /// dudas, si a los 15 s nadie la usó, navega igual). Si ya decidió, navega
  /// en el momento, como siempre.
  static void ir(String ruta, void Function(String ruta) navegar) {
    if (!registrar(ruta)) {
      Future.delayed(const Duration(seconds: 15), () {
        if (_pendiente == ruta && !_splashResuelto) {
          try {
            navegar(ruta);
          } catch (_) {}
        }
      });
      return;
    }
    Future.delayed(const Duration(milliseconds: 200), () {
      try {
        navegar(ruta);
      } catch (_) {}
    });
  }

  /// Sólo para tests.
  static void reiniciarParaTest() {
    _splashResuelto = false;
    _pendiente = null;
  }
}
