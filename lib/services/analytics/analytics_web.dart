import 'dart:js_interop';

// Puente a `window.auraAnalytics`, que define web/aura-analytics.js. Si el
// script no está (un bloqueador se lo comió, o un index.html sin él) todo esto
// no hace nada: medir nunca puede romper la app.

@JS('auraAnalytics')
external _AuraAnalytics? get _aura;

extension type _AuraAnalytics._(JSObject _) implements JSObject {
  external void pageView(String ruta);
  external void appStoreClick(
    String linkUrl,
    String linkText,
    String placement,
  );
  external JSString? fbc();
  external void evento(String nombre, String paramsJson);
  external void usuario(String? id);
  external void marcarInterna();
  external JSString? datosCheckout();
}

/// La ruta con la que se abrió la página ("/#/clase/12" → "/clase/12"; sin
/// hash → "/"). Es la que ya midió el page_view de `config` en el HTML.
String? rutaInicial() {
  final fragment = Uri.base.fragment;
  if (!fragment.startsWith('/')) return '/';
  return fragment.split('?').first;
}

void pageView(String ruta) {
  try {
    _aura?.pageView(ruta);
  } catch (_) {}
}

void appStoreClick(String url, String texto, String placement) {
  try {
    _aura?.appStoreClick(url, texto, placement);
  } catch (_) {}
}

/// El clic de Meta que guardó aura-analytics.js (`fb.1.<ms>.<fbclid>`), o
/// null si la persona no llegó desde un anuncio (o el script no cargó).
String? fbcGuardado() {
  try {
    return _aura?.fbc()?.toDart;
  } catch (_) {
    return null;
  }
}

void evento(String nombre, String paramsJson) {
  try {
    _aura?.evento(nombre, paramsJson);
  } catch (_) {}
}

void usuario(String? id) {
  try {
    _aura?.usuario(id);
  } catch (_) {}
}

void marcarInterna() {
  try {
    _aura?.marcarInterna();
  } catch (_) {}
}

/// JSON con client_id, session_id y la campaña guardada; "{}" si no hay nada.
String datosCheckout() {
  try {
    return _aura?.datosCheckout()?.toDart ?? '{}';
  } catch (_) {
    return '{}';
  }
}
