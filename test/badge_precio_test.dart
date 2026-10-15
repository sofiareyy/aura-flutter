// El cartel "PRECIO REDUCIDO" (14/10/2026).
//
// Es la SEGUNDA corrección del mismo cartel, y las dos veces el error fue el
// mismo: dar por cierto un dato que el estudio DECLARA en vez de mirar lo que
// el estudio HACE.
//
//   26/8  — miraba el nombre de la franja ⇒ 823 de 997 clases (83%).
//   14/10 — comparaba contra `estudios.creditos_max`, que es la CONFIGURACIÓN
//           de precios, no un techo observado. Rock Palermo declara 16–18 y
//           cobra 16 en sus 252 clases, porque nunca marcó un horario como
//           pico: el cartel les salía en el 100%, prometiendo una rebaja
//           contra un precio que no cobran nunca. 487 clases, el 46% de
//           todos los carteles.
//
// Ahora se compara contra el rango REALMENTE publicado. Medido: de 1.051
// clases con cartel se pasa a 564.

import 'package:aura_app/screens/explorar/explorar_screen.dart';
import 'package:aura_app/utils/badge_precio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('es'));

  group('la regla', () {
    test('un estudio que cobra siempre lo mismo NO muestra el cartel', () {
      // Rock Studios Palermo, con los números reales: declara 16–18 en su
      // configuración pero sus 252 clases cuestan 16. Antes: cartel en todas.
      expect(
        esPrecioReducido(
          creditos: 16,
          tipoPrecio: 'valle',
          rango: const RangoPublicado(16, 16),
        ),
        isFalse,
      );
    });

    test('la clase más barata de un estudio con rango real SÍ lo muestra', () {
      // Tiwar Fitness: publica de 11 a 14 de verdad.
      expect(
        esPrecioReducido(
          creditos: 11,
          tipoPrecio: 'valle',
          rango: const RangoPublicado(11, 14),
        ),
        isTrue,
      );
    });

    test('la más cara de ese mismo estudio no lo muestra', () {
      expect(
        esPrecioReducido(
          creditos: 14,
          tipoPrecio: 'pico',
          rango: const RangoPublicado(11, 14),
        ),
        isFalse,
      );
    });

    test('un servicio de precio fijo nunca lo muestra', () {
      // Un sauna de 14 en un estudio que llega a 18 no tiene nada de
      // reducido: su precio es único por definición.
      expect(
        esPrecioReducido(
          creditos: 14,
          tipoPrecio: 'servicio',
          rango: const RangoPublicado(11, 18),
        ),
        isFalse,
      );
    });

    test('sin rango conocido no se promete nada', () {
      expect(
        esPrecioReducido(creditos: 11, tipoPrecio: 'valle', rango: null),
        isFalse,
      );
    });
  });

  group('encontrar el rango de la clase', () {
    const mapa = {58: RangoPublicado(16, 16), 4: RangoPublicado(11, 14)};

    test('lo encuentra por estudio_id suelto', () {
      expect(rangoDeLaClase({'estudio_id': 4}, mapa)?.max, 14);
    });

    test('y también adentro del embed de PostgREST', () {
      expect(
        rangoDeLaClase({
          'estudios': {'id': 58},
        }, mapa)?.max,
        16,
      );
    });

    test('un estudio que no está en el mapa da null, no un cartel', () {
      expect(rangoDeLaClase({'estudio_id': 999}, mapa), isNull);
    });
  });

  group('la tarjeta, renderizada', () {
    Map<String, dynamic> clase(int creditos) => {
      'id': 1,
      'nombre': 'Pilates Reformer',
      'creditos': creditos,
      'tipo': 'clase',
      'tipo_precio': 'valle',
      'fecha': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
      'estudio_id': 58,
      'estudios': {
        'id': 58,
        'nombre': 'Rock Studios Palermo',
        'barrio': 'Palermo',
      },
    };

    Future<void> montar(WidgetTester tester, RangoPublicado? rango) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              // 460 y no el ancho de un teléfono, por la FUENTE DE TEST.
              //
              // En `flutter test` todos los glifos miden lo mismo (una fuente
              // de ancho fijo), así que "🏷️ PRECIO REDUCIDO" mide bastante
              // más que con la tipografía real y la tarjeta desborda por
              // debajo de ~440 px. Es un artefacto del test: verificado en el
              // navegador a 320, 360 y 390 px, el cartel entra bien y el
              // texto de categoría se recorta para dejarle lugar.
              //
              // O sea: acá se mide la REGLA, no el layout. Para el layout hay
              // que mirar `tarjeta_explorar_test`, que trabaja con anchos, o
              // el navegador.
              child: SizedBox(
                width: 460,
                child: debugResultCard(clase: clase(16), rango: rango),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('sin rango real, la tarjeta no dice PRECIO REDUCIDO', (
      tester,
    ) async {
      await montar(tester, const RangoPublicado(16, 16));
      expect(find.textContaining('PRECIO REDUCIDO'), findsNothing);
    });

    testWidgets('con rango real, sí lo dice', (tester) async {
      await montar(tester, const RangoPublicado(16, 18));
      expect(find.textContaining('PRECIO REDUCIDO'), findsOneWidget);
    });
  });
}
