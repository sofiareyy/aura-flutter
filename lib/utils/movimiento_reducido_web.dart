// ¿El navegador pide "reducir movimiento"? (29/10/2026)
//
// Flutter web NO pasa `prefers-reduced-motion` a
// MediaQuery.disableAnimations: medido con la landing, con la opción activada
// las animaciones corrían igual. Se lee directo del navegador.
//
// Mismo patrón que `sentry_bots_web.dart`: `dart:js_interop` directo, sin
// sumar dependencias.
import 'dart:js_interop';

@JS('window.matchMedia')
external _ResultadoMedia? _matchMedia(String consulta);

extension type _ResultadoMedia._(JSObject _) implements JSObject {
  external bool get matches;
}

bool navegadorPideMenosMovimiento() {
  try {
    return _matchMedia('(prefers-reduced-motion: reduce)')?.matches ?? false;
  } catch (_) {
    return false;
  }
}
