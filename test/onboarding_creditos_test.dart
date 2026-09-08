// Cuándo se muestra el onboarding de créditos (9/9/2026).
//
// El agujero que tapa: de 79 alumnas registradas sólo 4 compraron, y el
// onboarding que explica qué es un crédito se disparaba SÓLO desde el registro
// con mail. De las 79 cuentas, 28 entraron con Apple y 24 con Google: el 66%
// llegaba al muro de pago sin que nadie le hubiera explicado nada.
import 'dart:io';

import 'package:aura_app/utils/onboarding_creditos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('quién lo ve', () {
    test('una alumna nueva que entra con Google o Apple, SÍ', () {
      expect(debeVerOnboarding(destino: '/home', yaLoVio: false), isTrue);
    });

    test('la que venía mirando una clase, también', () {
      // El muro de registro la mandó a loguearse; vuelve con ?volver=/clase/42.
      expect(debeVerOnboarding(destino: '/clase/42', yaLoVio: false), isTrue);
    });

    test('la que ya lo vio, NO (una vez por dispositivo)', () {
      expect(debeVerOnboarding(destino: '/home', yaLoVio: true), isFalse);
    });
  });

  group('quién NO lo ve, aunque sea su primera vez', () {
    test('un estudio que entra a su panel', () {
      for (final r in [
        '/estudio/dashboard',
        '/estudio/clases',
        '/estudio/cobros',
        '/estudio/asistencia',
        '/estudio/perfil',
      ]) {
        expect(
          debeVerOnboarding(destino: r, yaLoVio: false),
          isFalse,
          reason: '$r es el panel del estudio: no compra créditos',
        );
      }
    });

    test('una cuenta con varias sedes, que cae en el selector', () {
      expect(
        debeVerOnboarding(destino: '/seleccionar-acceso', yaLoVio: false),
        isFalse,
      );
    });
  });

  group('la ficha pública de un estudio SÍ es de alumna', () {
    test('/estudio/56 es la ficha, no el panel', () {
      // Es la trampa de esta ruta: `/estudio/<id>` y `/estudio/dashboard`
      // empiezan igual. Una alumna puede estar mirando la ficha de YOYO.
      expect(esDestinoDeAlumna('/estudio/56'), isTrue);
      expect(esDestinoDeAlumna('/estudio/56/resenas'), isTrue);
      expect(esDestinoDeAlumna('/estudio/dashboard'), isFalse);
    });
  });

  group('el destino se conserva', () {
    test('la clase que la trajo viaja en ?volver=', () {
      expect(
        rutaOnboardingCon('/clase/42'),
        '/creditos-onboarding?volver=%2Fclase%2F42',
      );
    });

    test('y una ruta con query también, sin romperse', () {
      final r = rutaOnboardingCon('/explorar?categoria=Yoga');
      expect(r, startsWith('/creditos-onboarding?volver='));
      expect(
        Uri.parse(r).queryParameters['volver'],
        '/explorar?categoria=Yoga',
      );
    });
  });

  group('el copy', () {
    final fuente = File(
      'lib/screens/onboarding/creditos_onboarding_screen.dart',
    ).readAsStringSync();

    test('son las tres frases aprobadas', () {
      expect(fuente, contains('Una app, muchos estudios'));
      expect(fuente, contains('Elegís vos'));
      expect(fuente, contains('Sin cuota mensual'));
    });

    test('ya no está el copy viejo, que explicaba el mecanismo', () {
      expect(fuente.contains('¿Qué son los créditos?'), isFalse);
      expect(fuente.contains('la moneda de Aura'), isFalse);
    });

    test('cada pantalla entra en una frase', () {
      // Nadie lee onboardings largos. Ninguna supera las 30 palabras.
      final cuerpos = RegExp(r"body:\s*((?:'[^']*'\s*)+)")
          .allMatches(fuente)
          .map((m) => m.group(1)!.replaceAll(RegExp(r"'\s*'"), '').replaceAll("'", ''))
          .toList();
      expect(cuerpos.length, 3);
      for (final c in cuerpos) {
        expect(
          c.split(RegExp(r'\s+')).length,
          lessThanOrEqualTo(30),
          reason: 'demasiado largo: "$c"',
        );
      }
    });
  });
}
