// La tarjeta de "DESTACADOS HOY" en Explorar.
//
// Tiene ALTO FIJO (el del carrusel) y contenido variable: nombre del estudio,
// barrio y dirección. Con un nombre de dos renglones —"Ambra Espacio
// Holístico", el más largo de producción— el nombre se comía el lugar y la
// dirección quedaba apretada o cortada. Estos tests miden el desborde real con
// los nombres que existen hoy.
import 'package:aura_app/models/estudio.dart';
import 'package:aura_app/screens/explorar/explorar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Estudio estudio({
  required String nombre,
  String barrio = 'Palermo',
  String? direccion = 'Av Córdoba 5151, Buenos Aires, Argentina',
  List<String> categorias = const ['Yoga'],
}) =>
    Estudio.fromMap({
      'id': 1,
      'nombre': nombre,
      'barrio': barrio,
      'direccion': direccion,
      'categorias': categorias,
    });

void main() {
  // El ancho real de la tarjeta en el carrusel.
  const anchoTarjeta = 166.0;

  Future<void> pump(WidgetTester tester, Estudio e) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: anchoTarjeta,
            child: debugFeaturedExploreCard(estudio: e),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  group('el nombre ya no se come la dirección', () {
    // Los cinco nombres más largos que hay en producción hoy.
    const nombresReales = [
      'Ambra Espacio Holístico',
      'BB Estudio Colegiales',
      'Yessi Funes Fitness',
      'BB Estudio Urquiza',
      'YN Pilates Studio',
      'Citra Barre',
    ];

    testWidgets('ninguno desborda la tarjeta', (tester) async {
      for (final nombre in nombresReales) {
        await pump(tester, estudio(nombre: nombre));
        expect(tester.takeException(), isNull, reason: 'desbordó con "$nombre"');
      }
    });

    testWidgets('la dirección se dibuja aunque el nombre sea el más largo',
        (tester) async {
      await pump(tester, estudio(nombre: 'Ambra Espacio Holístico'));
      expect(find.textContaining('Av Córdoba 5151'), findsOneWidget);
      expect(find.text('Palermo'), findsOneWidget);
    });

    testWidgets('el nombre corta con puntos suspensivos, no empuja', (tester) async {
      await pump(tester, estudio(nombre: 'Ambra Espacio Holístico'));
      final texto = tester.widget<Text>(find.text('Ambra Espacio Holístico'));
      expect(texto.overflow, TextOverflow.ellipsis);
      expect(texto.maxLines, 2);
    });

    testWidgets('con un nombre absurdo tampoco desborda', (tester) async {
      await pump(tester, estudio(
        nombre: 'Estudio de Pilates Reformer y Barre del Norte de Buenos Aires',
      ));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Av Córdoba 5151'), findsOneWidget);
    });

    testWidgets('sin dirección cargada muestra el texto de respaldo',
        (tester) async {
      await pump(tester, estudio(nombre: 'Citra Barre', direccion: null));
      expect(find.text('Ver estudio y ubicación'), findsOneWidget);
    });
  });

  group('el badge sobre la foto muestra UNA sola categoría', () {
    testWidgets('con varias categorías, sólo la principal', (tester) async {
      await pump(tester, estudio(
        nombre: 'Sculpt Club',
        categorias: ['Meditación', 'Pilates', 'Yoga', 'Fitness'],
      ));
      expect(find.text('MEDITACIÓN'), findsOneWidget);
      // Lo que se veía antes: el cartel largo con varias.
      expect(find.textContaining('·'), findsNothing);
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('con una sola, se ve esa', (tester) async {
      await pump(tester, estudio(nombre: 'Citra Barre', categorias: ['Barre']));
      expect(find.text('BARRE'), findsOneWidget);
    });

    testWidgets('sin categorías no rompe', (tester) async {
      await pump(tester, estudio(nombre: 'Citra Barre', categorias: const []));
      expect(tester.takeException(), isNull);
    });
  });
}
