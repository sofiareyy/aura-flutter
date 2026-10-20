// El user agent, para saber si quien tuvo el error fue un crawler.
//
// Mismo patrón que `compartir_web.dart`: `dart:js_interop` directo, sin
// sumar dependencias.
import 'dart:js_interop';

@JS('navigator')
external _Navegador? get _navigator;

extension type _Navegador._(JSObject _) implements JSObject {
  external String? get userAgent;
}

String? userAgentActual() {
  try {
    return _navigator?.userAgent;
  } catch (_) {
    return null;
  }
}
