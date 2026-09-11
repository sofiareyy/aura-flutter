import 'analytics_stub.dart'
    if (dart.library.js_interop) 'analytics_web.dart' as impl;

/// Google Analytics 4 de la web (somosaurapass.com).
///
/// Todo lo pesado vive en `web/aura-analytics.js`: el ID de medición, la carga
/// de gtag.js, el page_view de la carga (con los UTM) y el `app_store_click`
/// de los enlaces de las páginas estáticas. Esto es sólo el puente para lo que
/// pasa ADENTRO de la app Flutter: los cambios de ruta y los botones que abren
/// la App Store con `launchUrl`.
///
/// En iOS y Android no hace nada: no hay Firebase Analytics en las apps.
class Analytics {
  Analytics._();

  /// Ruta de GoRouter informada por última vez, para no mandar dos page_view
  /// seguidos de la misma pantalla (el delegate notifica más de una vez por
  /// navegación). Arranca con la ruta con la que se abrió la página, que ya la
  /// midió `config` en el HTML.
  static String? _ultimaRuta = impl.rutaInicial();

  /// Rutas que no son una pantalla para medir: el splash dura un instante y
  /// siempre redirige a otra.
  static const _rutasIgnoradas = {'/splash'};

  /// page_view si [ruta] es una pantalla nueva. Lo llama el listener del
  /// router en `app_router.dart`.
  static void rutaCambio(String ruta) {
    final destino = rutaAReportar(ruta, _ultimaRuta);
    if (destino == null) return;
    _ultimaRuta = destino;
    impl.pageView(destino);
  }

  /// Decide si [ruta] merece un page_view, dada la [anterior]. Devuelve la
  /// ruta a informar o `null`. Separado para poder testearlo.
  static String? rutaAReportar(String ruta, String? anterior) {
    final path = ruta.isEmpty ? '/' : ruta;
    if (_rutasIgnoradas.contains(path)) return null;
    if (path == anterior) return null;
    return path;
  }

  /// `app_store_click`: llamar ANTES de abrir la tienda. No espera nada — el
  /// hit sale por sendBeacon — así que no demora la apertura.
  static void appStoreClick({
    required String url,
    required String texto,
    required String placement,
  }) {
    if (!url.contains('apps.apple.com')) return;
    impl.appStoreClick(url, texto, placement);
  }
}
