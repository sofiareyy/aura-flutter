import 'package:aura_app/services/analytics/analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Analytics.rutaAReportar', () {
    test('una pantalla nueva se reporta', () {
      expect(Analytics.rutaAReportar('/home', '/'), '/home');
      expect(Analytics.rutaAReportar('/clase/12', '/home'), '/clase/12');
    });

    test('la misma pantalla dos veces seguidas no duplica', () {
      expect(Analytics.rutaAReportar('/home', '/home'), isNull);
    });

    test('la ruta de carga no se repite: ya la midió el HTML', () {
      // Entró por somosaurapass.com/#/clase/12 → `rutaInicial` = /clase/12.
      expect(Analytics.rutaAReportar('/clase/12', '/clase/12'), isNull);
    });

    test('el splash no es una pantalla', () {
      expect(Analytics.rutaAReportar('/splash', '/'), isNull);
    });

    test('ruta vacía es la raíz', () {
      expect(Analytics.rutaAReportar('', '/home'), '/');
      expect(Analytics.rutaAReportar('', '/'), isNull);
    });
  });

  test('en mobile (stub) no lanza ni hace nada', () {
    Analytics.rutaCambio('/home');
    Analytics.appStoreClick(
      url: 'https://apps.apple.com/app/id6764207399',
      texto: 'Descargá Aura',
      placement: 'registration_wall',
    );
  });
}
