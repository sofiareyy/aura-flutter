// Cuándo se muestra el onboarding de créditos (9/9/2026).
//
// El agujero que tapa: de 79 alumnas registradas sólo 4 compraron, y el
// onboarding que explica qué es un crédito se disparaba SÓLO desde el registro
// con mail. De las 79 cuentas, 28 entraron con Apple y 24 con Google: el 66%
// llegaba al muro de pago sin que nadie le hubiera explicado nada.
import 'dart:io';

import 'package:aura_app/utils/onboarding_creditos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
          .map(
            (m) => m
                .group(1)!
                .replaceAll(RegExp(r"'\s*'"), '')
                .replaceAll("'", ''),
          )
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

  // El agujero del 13/10: la decisión vivía suelta en el callback de OAuth de
  // `main.dart`, que cubre web y Android. Los tres caminos que resuelven el
  // destino por su cuenta —Apple nativo al registrarse, Apple nativo al
  // entrar, y el login con mail— se la salteaban. En iOS la hoja nativa de
  // Apple es EL camino, así que al 66% de login social el arreglo del 9/9 le
  // llegaba a medias.
  group('el destino después de autenticarse', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
      'una alumna que no lo vio va al onboarding, sin perder su destino',
      () async {
        final r = await destinoConOnboarding('/home', '/clase/42');
        expect(r, startsWith('/creditos-onboarding?volver='));
        expect(Uri.parse(r).queryParameters['volver'], '/clase/42');
      },
    );

    test('la que ya lo vio va derecho a donde iba', () async {
      SharedPreferences.setMockInitialValues({kPrefsOnboardingCreditos: true});
      expect(await destinoConOnboarding('/home', '/clase/42'), '/clase/42');
    });

    test('un estudio nunca lo ve, aunque no lo haya visto', () async {
      expect(
        await destinoConOnboarding('/estudio/dashboard', null),
        '/estudio/dashboard',
      );
    });
  });

  // Este test no mira comportamiento: mira que no vuelva a abrirse el agujero.
  // Lo que falló no fue la regla —que estaba bien y testeada— sino que tres
  // pantallas resolvían el destino sin pasar por ella. Un camino nuevo que
  // llame a `resolver` directo lo rompe acá y no en producción.
  test('ninguna pantalla resuelve el destino por su cuenta', () {
    final culpables = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('lib/utils/onboarding_creditos.dart')) continue;
      if (f.readAsStringSync().contains('DestinoPostLogin.resolver(')) {
        culpables.add(f.path);
      }
    }
    expect(
      culpables,
      isEmpty,
      reason:
          'tienen que llamar a destinoConOnboarding(), que resuelve el destino '
          'Y decide el onboarding en un solo lugar',
    );
  });
}
