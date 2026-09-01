// A dónde va alguien después de loguearse cuando venía de una clase concreta.
//
// La propiedad que importa: el `?volver=` NUNCA puede sacar a un estudio, una
// profe o un admin de su panel. Sólo aplica cuando el rol daba el `/home`
// genérico, que es exactamente lo que `AuthService.destinoInicial()` devuelve
// para una usuaria sin accesos de estudio.
import 'package:aura_app/utils/destino_post_login.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('la alumna vuelve a donde estaba', () {
    test('con /home genérico, gana la clase que la trajo', () {
      expect(DestinoPostLogin.resolver('/home', '/clase/123'), '/clase/123');
    });

    test('sin volver, se queda el destino del rol', () {
      expect(DestinoPostLogin.resolver('/home', null), '/home');
      expect(DestinoPostLogin.resolver('/home', ''), '/home');
      expect(DestinoPostLogin.resolver('/home', '   '), '/home');
    });

    test('otras rutas internas también valen (estudio, mapa)', () {
      expect(DestinoPostLogin.resolver('/home', '/estudio/9'), '/estudio/9');
      expect(DestinoPostLogin.resolver('/home', '/explorar?categoria=Yoga'),
          '/explorar?categoria=Yoga');
    });
  });

  group('EL REDIRECT POR ROL NO SE ROMPE', () {
    // Los destinos reales de AuthService.destinoInicial().
    const porRol = [
      '/admin/dashboard',
      '/estudio/dashboard',
      '/estudio/clases',
      '/seleccionar-acceso',
    ];

    test('ningún rol es desviado por un volver, ni malicioso', () {
      for (final destino in porRol) {
        expect(DestinoPostLogin.resolver(destino, '/clase/123'), destino,
            reason: '$destino tiene que ganar siempre');
        expect(DestinoPostLogin.resolver(destino, 'https://evil.com'), destino);
        expect(DestinoPostLogin.resolver(destino, null), destino);
      }
    });
  });

  group('no puede convertirse en un redirect abierto', () {
    test('rechaza lo que salga de Aura', () {
      for (final malo in [
        'https://evil.com',
        'http://evil.com',
        '//evil.com',
        'javascript:alert(1)',
        'evil.com',
        'mailto:a@b.com',
      ]) {
        expect(DestinoPostLogin.sanear(malo), isNull, reason: malo);
        expect(DestinoPostLogin.resolver('/home', malo), '/home',
            reason: 'con $malo tiene que quedarse en /home');
      }
    });

    test('acepta sólo rutas internas', () {
      expect(DestinoPostLogin.sanear('/clase/1'), '/clase/1');
      expect(DestinoPostLogin.sanear('  /clase/1  '), '/clase/1');
    });
  });
}
