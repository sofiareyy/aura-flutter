// La tarjeta de resultados de Explorar, medida DE VERDAD (no la fórmula sola).
//
// El cambio del 3/9/2026 ensanchó la foto del teléfono de 96 a 131 px, lo que
// le saca 35 px al texto que va al lado. Lo que estos tests cuidan:
//   · que la foto mida lo que tiene que medir en teléfono y en desktop,
//   · que el carrusel de experiencias NO haya cambiado,
//   · que nada desborde en el teléfono más chico con el peor texto real.
//
// Los datos son de producción (3/9/2026): el nombre de clase más largo que hay
// cargado y la dirección más larga de todos los estudios.
import 'package:aura_app/screens/explorar/explorar_screen.dart';
import 'package:aura_app/utils/grilla_responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('es'));

  // Peor caso REAL: "Yin Yoga + Mindfulness" es el nombre más largo en
  // producción y la dirección de YN Pilates tiene 115 caracteres.
  final peorCaso = <String, dynamic>{
    'id': 1,
    'nombre': 'Yin Yoga + Mindfulness',
    'creditos': 18,
    'tipo': 'clase',
    'tipo_precio': 'normal',
    'fecha': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
    'estudios': {
      'id': 8,
      'nombre': 'Ambra Espacio Holístico',
      'barrio': 'Palermo',
      'direccion':
          'Colectora Panamericana avenida 12 de octubre, Felix De Olazabal '
          '1141, B1629 Buenos Aires, Provincia de Buenos Aires',
      'categorias': ['Yoga', 'Holistico / Bienestar'],
      'creditos_min': 11,
      'creditos_max': 18,
      'foto_url': null,
    },
  };

  Future<void> pump(
    WidgetTester tester,
    double anchoCard, {
    bool compacta = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: anchoCard,
              child: debugResultCard(clase: peorCaso, fotoCompacta: compacta),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// El ancho real de la foto es el del ClipRRect que la envuelve, que es el
  /// primero de la Row.
  double anchoFotoReal(WidgetTester tester) =>
      tester.getSize(find.byType(ClipRRect).first).width;

  group('teléfono', () {
    testWidgets('la foto mide 131 px en un teléfono de 390', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pump(tester, 390 - 44);
      expect(anchoFotoReal(tester), 131);
      expect(tester.takeException(), isNull);
    });

    testWidgets('y también en el teléfono más chico, de 320', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pump(tester, 320 - 44);
      expect(anchoFotoReal(tester), 131);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nada desborda de 320 a 430 con el peor texto real', (
      tester,
    ) async {
      for (final pantalla in [320.0, 360.0, 375.0, 390.0, 414.0, 430.0]) {
        tester.view.physicalSize = Size(pantalla, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await pump(tester, pantalla - 44);
        // Un RenderFlex que desborda tira excepción: la franja amarilla.
        expect(
          tester.takeException(),
          isNull,
          reason: 'desbordó en una pantalla de $pantalla',
        );
      }
    });

    testWidgets('los cuatro renglones siguen dibujándose, no desaparecen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pump(tester, 320 - 44);
      // Nombre de la clase, dirección y precio: los tres presentes.
      expect(find.text('Yin Yoga + Mindfulness'), findsOneWidget);
      expect(find.textContaining('Colectora Panamericana'), findsOneWidget);
      expect(find.text('18 cr'), findsOneWidget);
      // La línea de categoría + barrio.
      expect(find.textContaining('PALERMO'), findsOneWidget);
    });

    testWidgets('el texto se corta con puntos suspensivos, no se rompe', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pump(tester, 320 - 44);
      final nombre = tester.widget<Text>(
        find.text('Yin Yoga + Mindfulness'),
      );
      expect(nombre.maxLines, 1);
      expect(nombre.overflow, TextOverflow.ellipsis);
      final dir = tester.widget<Text>(
        find.textContaining('Colectora Panamericana'),
      );
      expect(dir.maxLines, 1);
      expect(dir.overflow, TextOverflow.ellipsis);
    });
  });

  group('lo que NO tenía que cambiar', () {
    testWidgets('desktop sigue con la foto de 186 px', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // Dos columnas dentro de 1100.
      final ancho = anchoCelda(1100, 2);
      await pump(tester, ancho);
      expect(anchoFotoReal(tester), 186);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el carrusel de experiencias sigue con 96 px', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pump(tester, 320, compacta: true);
      expect(anchoFotoReal(tester), 96);
      expect(tester.takeException(), isNull);
    });
  });
}
