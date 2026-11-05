// iOS y Android: sin Analytics. Ver analytics.dart.

String? rutaInicial() => null;

void pageView(String ruta) {}

void appStoreClick(String url, String texto, String placement) {}

// Fuera de la web no hay clic de Meta guardado (sólo compras web, por ahora).
String? fbcGuardado() => null;

// El embudo de GA4 es sólo web (igual que Meta).
void evento(String nombre, String paramsJson) {}

void usuario(String? id) {}

void marcarInterna() {}

String datosCheckout() => '{}';
