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

@JS('gtag')
external JSFunction? get _gtag;

/// Cuenta cada error que se descarta como evento de GA4 `sentry_descartado`
/// (motivo + archivo de origen), para poder ver qué se está tapando.
/// Si GA4 no cargó, no pasa nada.
void registrarDescarte(String motivo, String origen) {
  try {
    final g = _gtag;
    if (g == null) return;
    final params = <String, Object>{
      'motivo': motivo,
      // GA4 corta los parámetros a 100 caracteres.
      'origen': origen.length > 100
          ? origen.substring(origen.length - 100)
          : origen,
    }.jsify();
    g.callAsFunction(null, 'event'.toJS, 'sentry_descartado'.toJS, params);
  } catch (_) {}
}
