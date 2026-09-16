import 'dart:js_interop';

// ¿Este navegador puede compartir?
//
// La Web Share API (`navigator.share`) no está en todos lados: no está en
// Firefox de escritorio, ni en Chrome sobre Linux, ni en Safari viejo, ni en
// ningún origen inseguro. Preguntamos ANTES de intentar, porque share_plus no
// avisa cuando falta: en vez de fallar, abre un `mailto:` y devuelve OK.

@JS('navigator')
external _Navegador? get _navigator;

extension type _Navegador._(JSObject _) implements JSObject {
  external JSAny? get share;
}

bool hayCompartirNativo() {
  try {
    return _navigator?.share != null;
  } catch (_) {
    return false;
  }
}
