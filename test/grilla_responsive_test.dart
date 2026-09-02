import 'package:aura_app/utils/grilla_responsive.dart';
import 'package:flutter_test/flutter_test.dart';

/// Los números de las dos grillas de la web (2/9/2026).
///
/// Inicio = vidriera (foto arriba, 16:9, hasta 3 columnas en 1200).
/// Explorar = buscador (foto al costado, denso, hasta 2 columnas en 1100).
void main() {
  group('columnas de la vidriera (Inicio)', () {
    test('teléfono: una sola columna', () {
      expect(columnasVidriera(390), 1);
      expect(columnasVidriera(430), 1);
      expect(columnasVidriera(719), 1);
    });

    test('tablet: dos', () {
      expect(columnasVidriera(720), 2);
      expect(columnasVidriera(899), 2);
    });

    test('desktop: tres', () {
      expect(columnasVidriera(900), 3);
      expect(columnasVidriera(1200), 3);
      // Por más ancha que sea la pantalla no pasa de tres: el contenido topa
      // en 1200 y las columnas se quedan en ~390 px.
      expect(columnasVidriera(1880), 3);
    });
  });

  group('columnas del buscador (Explorar)', () {
    test('nunca más de dos', () {
      expect(columnasBuscador(390), 1);
      expect(columnasBuscador(719), 1);
      expect(columnasBuscador(720), 2);
      expect(columnasBuscador(1100), 2);
      expect(columnasBuscador(1880), 2);
    });
  });

  group('ancho de cada celda', () {
    test('una columna ocupa todo', () {
      expect(anchoCelda(346, 1), 346);
    });

    test('descuenta los espacios entre tarjetas', () {
      expect(anchoCelda(1100, 2), (1100 - gapGrilla) / 2);
      expect(anchoCelda(1160, 3), (1160 - gapGrilla * 2) / 3);
    });
  });

  group('la foto del buscador', () {
    test('tarjeta ancha: 3:2, la foto llena el alto', () {
      // Dos columnas dentro de 1100 -> 542 px de tarjeta.
      final ancho = anchoCelda(1100, 2);
      expect(anchoFotoBuscador(ancho) / altoCardBuscador(ancho), closeTo(1.5, 0.001));
      expect(anchoFotoBuscador(ancho), 186);
      expect(altoCardBuscador(ancho), 124);
    });

    test('una sola columna ancha también recibe la foto grande', () {
      // Una ventana de 700: entra una sola columna, pero es ancha.
      expect(anchoFotoBuscador(700 - 44), 186);
    });

    test('teléfono y carrusel: como hoy, 96 x 112', () {
      // Teléfono de 390 menos los 44 de padding.
      expect(anchoFotoBuscador(346), 96);
      expect(altoCardBuscador(346), 112);
      // La tarjeta del carrusel de experiencias mide 320 y no cambia.
      expect(anchoFotoBuscador(320), 96);
      expect(altoCardBuscador(320), 112);
    });
  });

  group('el hero de las pantallas de detalle', () {
    test('en teléfono queda igual que antes: 300 px fijos', () {
      // Cualquier teléfono, con o sin los 44 de padding.
      expect(altoHero(390), altoHeroMin);
      expect(altoHero(430), altoHeroMin);
      // El piso se sostiene hasta los 600 px de ancho.
      expect(altoHero(599), altoHeroMin);
      expect(altoHero(600), altoHeroMin);
    });

    test('en pantalla ancha crece con el ancho, no se aplana', () {
      expect(altoHero(720), 360);
      expect(altoHero(1100), 550);
    });

    test('nunca pasa de 2:1, por más ancho que haya', () {
      // El contenido topa en 1100: a partir de ahí el hero no crece más.
      const anchoReal = anchoMaxDetalle;
      expect(anchoReal / altoHero(anchoReal), proporcionHero);
      // Antes, con alto fijo 300 y sin tope, un monitor de 1920 daba 6,4:1.
      expect(1920 / 300, greaterThan(6));
    });

    test('de una foto apaisada 3:2 se ve mucho más que antes', () {
      // Cuánto del alto de la foto sobrevive al recorte = proporción de la
      // foto / proporción del marco.
      double visible(double marco) => 1.5 / marco;
      expect(visible(proporcionHero), closeTo(0.75, 0.001));
      expect(visible(1920 / 300), closeTo(0.234, 0.001));
    });
  });

  group('confirmar reserva', () {
    test('la caja es más angosta que las de detalle', () {
      // Es una tarjeta con un botón, no una página para recorrer.
      expect(anchoMaxFormulario, lessThan(anchoMaxDetalle));
    });

    test('la foto usa la misma proporción que los heroes', () {
      // La foto de cabecera se recorta igual en toda la app. Con la caja de
      // 640 y 20 px de padding de cada lado más 14 de la tarjeta, la foto
      // mide 572 x 286 en vez de 1880 x 154 (12,2:1).
      const anchoFoto = anchoMaxFormulario - 20 * 2 - 14 * 2;
      expect(anchoFoto / proporcionHero, closeTo(286, 1));
      expect(1880 / 154, greaterThan(12));
    });
  });

  group('alto de la tarjeta de vidriera', () {
    test('crece con el ancho, porque la foto es 16:9', () {
      expect(altoCardVidriera(320), 320 / (16 / 9) + altoTextoVidriera);
      expect(altoCardVidriera(640), greaterThan(altoCardVidriera(320)));
    });

    test('el carrusel usa el alto de una tarjeta de 320', () {
      expect(altoCarruselVidriera, altoCardVidriera(320));
      // Antes era 270 con la foto de alto fijo 132.
      expect(altoCarruselVidriera, greaterThan(270));
    });
  });
}
