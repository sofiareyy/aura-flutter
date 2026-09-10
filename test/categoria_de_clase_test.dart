// La categoría que se le muestra a la alumna para una CLASE.
//
// El caso real que lo motivó (9/9/2026): Rock Studios Palermo es Spinning Y
// Pilates. Tiene dos clases, medidas en producción:
//
//   RockFormer  clases.categorias = {Pilates}
//   RockCycle   clases.categorias = {Spinning}
//   el estudio  estudios.categorias = {Spinning, Pilates}
//
// Siete pantallas leían la categoría del ESTUDIO, así que RockFormer —pilates—
// se anunciaba como "SPINNING · PILATES", y con el chip en "Pilates" salían las
// clases de spinning. Son 6 los estudios multi-categoría con clases cargadas,
// no sólo Rock: Ambra, Barre, Rock Palermo, Tiwar, Yessi Funes y YN Pilates.
import 'package:aura_app/screens/explorar/explorar_screen.dart';
import 'package:aura_app/screens/home/home_screen.dart';
import 'package:aura_app/screens/reservas/mis_reservas_screen.dart';
import 'package:aura_app/utils/categoria_de_clase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('es'));

  // Los dos estudios, tal como vienen del select de producción.
  const rockPalermo = <String, dynamic>{
    'id': 58,
    'nombre': 'Rock Studios Palermo',
    'categoria': 'Spinning',
    'categorias': ['Spinning', 'Pilates'],
  };

  Map<String, dynamic> claseDeRock(String nombre, String cat) => {
    'id': 1,
    'nombre': nombre,
    'categoria': cat,
    'categorias': [cat],
    'estudios': rockPalermo,
  };

  final rockFormer = claseDeRock('RockFormer', 'Pilates');
  final rockCycle = claseDeRock('RockCycle', 'Spinning');

  group('el badge dice la categoría de la clase', () {
    test('RockFormer es Pilates, no "Spinning · Pilates"', () {
      expect(categoriaDeClase(rockFormer), 'Pilates');
    });

    test('RockCycle es Spinning, en el mismo estudio', () {
      expect(categoriaDeClase(rockCycle), 'Spinning');
    });

    test('el badge es UNA categoría, no la lista del estudio', () {
      // El bug se veía exactamente así: dos categorías pegadas con " · ".
      expect(categoriaDeClase(rockFormer), isNot(contains('·')));
      expect(categoriaDeClase(rockFormer), isNot(contains('Spinning')));
    });
  });

  group('el filtro por chip usa la categoría de la clase', () {
    test('chip "Pilates": entra RockFormer, NO entra RockCycle', () {
      expect(claseEsDeCategoria(rockFormer, 'Pilates'), isTrue);
      expect(claseEsDeCategoria(rockCycle, 'Pilates'), isFalse);
    });

    test('chip "Spinning": al revés', () {
      expect(claseEsDeCategoria(rockCycle, 'Spinning'), isTrue);
      expect(claseEsDeCategoria(rockFormer, 'Spinning'), isFalse);
    });

    test('"Todos" deja pasar las dos', () {
      expect(claseEsDeCategoria(rockFormer, 'Todos'), isTrue);
      expect(claseEsDeCategoria(rockCycle, 'Todos'), isTrue);
    });

    test('no importan las mayúsculas ni los espacios', () {
      expect(claseEsDeCategoria(rockFormer, '  pilates '), isTrue);
    });

    test('una categoría que el estudio tiene pero la clase no, NO matchea', () {
      // Esta es la regresión: el estudio es Spinning, pero ESTA clase no.
      expect(rockPalermo['categorias'], contains('Spinning'));
      expect(claseEsDeCategoria(rockFormer, 'Spinning'), isFalse);
    });
  });

  group('sin categoría no se inventa nada', () {
    test('clase vacía: cadena vacía, no "YOGA"', () {
      // El detalle de clase y confirmar reserva tenían `?? \'YOGA\'` literal.
      // Una clase de spinning podía anunciarse como yoga.
      expect(categoriaDeClase(const {'nombre': 'Clase suelta'}), '');
      expect(categoriasDeClase(const {'nombre': 'Clase suelta'}), isEmpty);
    });

    test('lista vacía o con basura también da vacío', () {
      expect(categoriaDeClase(const {'categorias': <String>[]}), '');
      expect(
        categoriaDeClase(const {
          'categorias': ['', '  ', null],
        }),
        '',
      );
      expect(categoriaDeClase(const {'categoria': '   '}), '');
    });

    test('un chip cualquiera no matchea una clase sin categoría', () {
      expect(claseEsDeCategoria(const {'nombre': 'X'}, 'Pilates'), isFalse);
    });
  });

  group('el estudio es el último recurso, para datos viejos', () {
    test('sin categoría propia se usa la del estudio', () {
      // Hoy no pasa: las 1381 clases futuras tienen categorias cargada
      // (medido 9/9/2026). Queda por si alguien carga una clase sin categoría.
      final vieja = {'nombre': 'Clase de 2024', 'estudios': rockPalermo};
      expect(categoriaDeClase(vieja), 'Spinning');
      expect(claseEsDeCategoria(vieja, 'Pilates'), isTrue);
    });

    test('pero la clase SIEMPRE le gana al estudio', () {
      expect(categoriaDeClase(rockFormer), 'Pilates');
      expect(categoriasDeClase(rockFormer), ['Pilates']);
    });

    test('el escalar de la clase le gana al estudio', () {
      final soloEscalar = {'categoria': 'Pilates', 'estudios': rockPalermo};
      expect(categoriaDeClase(soloEscalar), 'Pilates');
    });

    test('una clase sin estudio no revienta', () {
      expect(categoriaDeClase(const {'estudios': null}), '');
      expect(categoriaDeClase(const {'estudios': 'no es un mapa'}), '');
    });
  });

  group('el resto de los estudios multi-categoría', () {
    test(
      'YN Pilates tiene 5 categorías y una clase de pilates dice Pilates',
      () {
        const yn = {
          'nombre': 'YN Pilates Studio',
          'categorias': [
            'Pilates',
            'Fitness',
            'Gym / Funcional',
            'Holistico / Bienestar',
            'Meditación',
          ],
        };
        final clase = {
          'nombre': 'Pilates Reformer',
          'categorias': ['Pilates'],
          'estudios': yn,
        };
        expect(categoriaDeClase(clase), 'Pilates');
        expect(claseEsDeCategoria(clase, 'Meditación'), isFalse);
      },
    );
  });

  // Los tests de arriba cuidan el helper. Estos cuidan las PANTALLAS: si
  // alguien vuelve a leer `estudios['categorias']` en una tarjeta, el helper
  // sigue bien y el bug vuelve igual. Acá se lee el texto que se renderiza.
  group('las tarjetas reales, renderizadas', () {
    final rockFormerCompleta = <String, dynamic>{
      ...rockFormer,
      'fecha': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
      'creditos': 14,
      'lugares_disponibles': 6,
      'tipo': 'clase',
      'tipo_precio': 'normal',
      'estudios': {...rockPalermo, 'barrio': 'Palermo', 'foto_url': null},
    };

    /// Todo el texto visible de la tarjeta, junto.
    String textoDe(WidgetTester tester) => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' | ');

    Future<void> pump(
      WidgetTester tester,
      Widget card, {
      // 360 es un teléfono normal. Las tres tarjetas entran sin desbordar
      // desde que los badges de "Reservar" pasaron a Wrap (9/9/2026).
      double ancho = 360,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [SizedBox(width: ancho, child: card)],
            ),
          ),
        ),
      ),
    );

    testWidgets('Explorar: RockFormer dice PILATES, nunca SPINNING', (
      tester,
    ) async {
      await pump(tester, debugResultCard(clase: rockFormerCompleta));
      final texto = textoDe(tester);
      expect(texto, contains('PILATES'));
      // El bug exacto: la tarjeta decía "SPINNING · PILATES".
      expect(texto, isNot(contains('SPINNING')));
    });

    testWidgets('Inicio: RockFormer dice PILATES, nunca SPINNING', (
      tester,
    ) async {
      await pump(
        tester,
        HomeNearbyClassCard(clase: rockFormerCompleta, onTap: () {}),
      );
      final texto = textoDe(tester);
      expect(texto, contains('PILATES'));
      expect(texto, isNot(contains('SPINNING')));
    });

    testWidgets('Reservar: RockFormer dice Pilates, nunca Spinning', (
      tester,
    ) async {
      await pump(
        tester,
        debugClaseDisponibleCard(
          clase: rockFormerCompleta,
          hoy: DateTime(2026, 9, 9),
        ),
      );
      final texto = textoDe(tester);
      expect(texto, contains('Pilates'));
      expect(texto, isNot(contains('Spinning')));
    });

    testWidgets('sin categoría no aparece ningún badge vacío', (tester) async {
      final sinCat = {...rockFormerCompleta}
        ..remove('categoria')
        ..remove('categorias')
        ..['estudios'] = {
          'id': 58,
          'nombre': 'Rock Studios Palermo',
          'barrio': 'Palermo',
          'foto_url': null,
        };
      await pump(tester, HomeNearbyClassCard(clase: sinCat, onTap: () {}));
      final texto = textoDe(tester);
      expect(texto, isNot(contains('YOGA')));
      expect(texto, isNot(contains('PILATES')));
      // La tarjeta igual se dibuja: sigue mostrando el nombre de la clase.
      expect(texto, contains('RockFormer'));
    });
  });
}
