// A dónde va alguien después de loguearse cuando venía de una clase concreta.
//
// La propiedad que importa: el `?volver=` NUNCA puede sacar a un estudio, una
// profe o un admin de su panel. Sólo aplica cuando el rol daba el `/home`
// genérico, que es exactamente lo que `AuthService.destinoInicial()` devuelve
// para una usuaria sin accesos de estudio.
import 'package:aura_app/utils/destino_post_login.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // ── La vuelta del PAGO (4/9/2026) ──────────────────────────────────────
  //
  // El agujero que tapa: la usuaria llegaba al checkout desde una clase, pagaba
  // y el único botón era "Ir al inicio". Tenía que buscar de nuevo la clase que
  // acababa de pagar.
  group('después de pagar vuelve a la clase', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('guarda y devuelve la clase que abrió el paywall', () async {
      await DestinoPostLogin.recordarCompra('/clase/123');
      expect(await DestinoPostLogin.tomarCompra(), '/clase/123');
    });

    test('es de un solo uso: la compra siguiente no hereda la clase', () async {
      await DestinoPostLogin.recordarCompra('/clase/123');
      await DestinoPostLogin.tomarCompra();
      expect(await DestinoPostLogin.tomarCompra(), isNull);
    });

    test('compra suelta (sin clase) no guarda nada ⇒ el final es /home',
        () async {
      await DestinoPostLogin.recordarCompra(null);
      expect(await DestinoPostLogin.tomarCompra(), isNull);
      await DestinoPostLogin.recordarCompra('');
      expect(await DestinoPostLogin.tomarCompra(), isNull);
    });

    test('tampoco acá se puede colar un destino externo', () async {
      await DestinoPostLogin.recordarCompra('https://evil.com');
      expect(await DestinoPostLogin.tomarCompra(), isNull);
      await DestinoPostLogin.recordarCompra('//evil.com');
      expect(await DestinoPostLogin.tomarCompra(), isNull);
    });

    test('EL LOGIN Y EL PAGO NO SE PISAN: son dos cajas distintas', () async {
      // Un OAuth abandonado a mitad de camino no puede desviar el pago, ni al
      // revés. Por eso las claves están separadas.
      await DestinoPostLogin.recordar('/clase/login');
      await DestinoPostLogin.recordarCompra('/clase/pago');
      expect(await DestinoPostLogin.tomarCompra(), '/clase/pago');
      expect(await DestinoPostLogin.tomar(), '/clase/login');
    });

    test('consumir el del pago no borra el del login', () async {
      await DestinoPostLogin.recordar('/clase/login');
      await DestinoPostLogin.tomarCompra();
      expect(await DestinoPostLogin.tomar(), '/clase/login');
    });
  });

  group('conVolver arma el link sin repetir el encode en cada pantalla', () {
    test('pega el volver cuando hay algo que recordar', () {
      expect(DestinoPostLogin.conVolver('/comprar-creditos', '/clase/7'),
          '/comprar-creditos?volver=%2Fclase%2F7');
    });

    test('sin volver, la ruta queda intacta', () {
      expect(DestinoPostLogin.conVolver('/comprar-creditos', null),
          '/comprar-creditos');
      expect(DestinoPostLogin.conVolver('/login', '  '), '/login');
    });

    test('respeta una ruta que ya tenía query', () {
      expect(DestinoPostLogin.conVolver('/comprar-creditos?tab=gift', '/clase/7'),
          '/comprar-creditos?tab=gift&volver=%2Fclase%2F7');
    });

    test('un destino externo no se pega', () {
      expect(DestinoPostLogin.conVolver('/login', 'https://evil.com'), '/login');
    });
  });
}
