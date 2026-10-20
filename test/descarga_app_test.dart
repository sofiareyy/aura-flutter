// Los botones de descarga de la portada (16/10/2026).
//
// Android se publicó el 15/10: por primera vez existen las dos tiendas y la
// portada puede ofrecer las dos. La regla es destacar la del aparato desde el
// que están mirando, sin esconder la otra — alguien puede estar en la compu o
// en un iPhone y querer el link para su Android.

import 'package:aura_app/utils/descarga_app.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('en la web', () {
    test('en iPhone se destaca App Store, y queda primera', () {
      final t = tiendasParaLanding(TargetPlatform.iOS, esWeb: true);
      expect(t.first.tienda, Tienda.appStore);
      expect(t.first.destacado, isTrue);
      expect(t.last.tienda, Tienda.googlePlay);
      expect(t.last.destacado, isFalse);
    });

    test('en Android se destaca Google Play, y queda primera', () {
      final t = tiendasParaLanding(TargetPlatform.android, esWeb: true);
      expect(t.first.tienda, Tienda.googlePlay);
      expect(t.first.destacado, isTrue);
      expect(t.last.tienda, Tienda.appStore);
      expect(t.last.destacado, isFalse);
    });

    test('en compu van las dos iguales', () {
      for (final p in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        final t = tiendasParaLanding(p, esWeb: true);
        expect(t.length, 2, reason: '$p');
        expect(t.every((x) => x.destacado), isTrue, reason: '$p');
      }
    });

    test('nunca se ofrece una sola cuando las dos existen', () {
      for (final p in TargetPlatform.values) {
        expect(tiendasParaLanding(p, esWeb: true).length, 2, reason: '$p');
      }
    });

    test('los links llevan su propia etiqueta de campaña', () {
      // Separados de los del muro, para poder medir cuál empuja más.
      final t = tiendasParaLanding(TargetPlatform.macOS, esWeb: true);
      expect(t[0].url, contains('ct=landing_web'));
      expect(t[1].url, contains('utm_source%3Dlanding_web'));
    });
  });

  test('dentro de la app nativa no se ofrece nada', () {
    // Ya la tienen instalada. Mismo criterio que `RegistroMuro.descargaPara`.
    for (final p in TargetPlatform.values) {
      expect(tiendasParaLanding(p, esWeb: false), isEmpty, reason: '$p');
    }
  });

  group('si Android se volviera a apagar', () {
    // La condición queda para que bajar el flag esconda el botón sin tocar
    // nada más. Es el estado en el que vivió la app hasta el 15/10.
    test('en Android no se ofrece nada', () {
      expect(
        tiendasParaLanding(
          TargetPlatform.android,
          esWeb: true,
          androidPublicado: false,
        ),
        isEmpty,
      );
    });

    test('en iPhone y en compu queda sólo App Store', () {
      for (final p in [TargetPlatform.iOS, TargetPlatform.macOS]) {
        final t = tiendasParaLanding(p, esWeb: true, androidPublicado: false);
        expect(t.length, 1, reason: '$p');
        expect(t.single.tienda, Tienda.appStore, reason: '$p');
      }
    });
  });
}
