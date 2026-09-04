// La pasada del sistema de diseño por Explorar (4/9/2026).
//
// Tres cosas que se pueden romper sin que se note a ojo, y por eso se miden:
//   · la tarjeta de alto fijo, que ya desbordó una vez con la escala nueva;
//   · los grises, que en esta pantalla estaban en 1,80:1 (los chips y el
//     buscador, o sea los controles principales);
//   · que los encabezados de sección salgan del componente compartido y no
//     vuelva a haber uno escrito a mano.
import 'dart:io';

import 'package:aura_app/core/theme/aura_tokens.dart';
import 'package:aura_app/screens/explorar/explorar_screen.dart';
import 'package:aura_app/utils/grilla_responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('es'));

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

  group('la tarjeta con la escala nueva', () {
    Future<void> pump(WidgetTester tester, double ancho) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: ancho,
                child: debugResultCard(clase: peorCaso),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('la ANCHA no desborda con el peor texto real', (tester) async {
      // Se afirmó que en la tarjeta ancha "el texto tiene lugar de sobra" y por
      // eso no se le subió el alto. Esto lo comprueba en vez de suponerlo.
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      for (final ancho in [420.0, 520.0, 640.0]) {
        await pump(tester, ancho);
        expect(
          tester.takeException(),
          isNull,
          reason: 'desbordó con la tarjeta ancha de $ancho px',
        );
      }
    });

    test('la angosta creció lo justo, la ancha no se movió', () {
      expect(altoCardBuscador(300), 118, reason: 'angosta: 112 + 6');
      expect(altoCardBuscador(600), 124, reason: 'ancha: sin cambio');
    });
  });

  group('los grises de Explorar', () {
    /// El archivo fuente: alcanza para probar que los literales ilegibles ya no
    /// están, sin construir el tema (que sale a buscar fuentes).
    final fuente = File(
      'lib/screens/explorar/explorar_screen.dart',
    ).readAsStringSync();

    test('el gris de 1,80:1 de los chips y el buscador ya no está', () {
      // #C7C0B9 sobre blanco da 1,80:1. Era el color del texto de los chips
      // inactivos (el filtro principal de la pantalla) y del hint del buscador.
      expect(fuente.contains('0xFFC7C0B9'), isFalse);
    });

    test('tampoco los otros dos grises flojos', () {
      expect(fuente.contains('0xFF8C847C'), isFalse, reason: '3,68:1');
      expect(fuente.contains('0xFFB4ACA5'), isFalse, reason: '2,24:1');
    });

    test('las etiquetas usan un solo gris, el del sistema', () {
      // #403A35 no era ilegible (11,2:1): era OTRO gris. Lo traían los tres
      // encabezados de sección y las cuatro etiquetas de la hoja de filtros.
      expect(fuente.contains('0xFF403A35'), isFalse);
      expect(fuente.contains('AppColors.textoSecundario'), isTrue);
    });
  });

  group('el sistema quedó aplicado', () {
    final fuente = File(
      'lib/screens/explorar/explorar_screen.dart',
    ).readAsStringSync();

    test('las tres secciones usan el encabezado compartido', () {
      expect('TituloSeccion('.allMatches(fuente).length, 3);
    });

    test('no quedan radios a mano, salvo el de la hoja modal', () {
      final crudos = RegExp(
        r'circular\((\d+)\)',
      ).allMatches(fuente).map((m) => m.group(1)).toList();
      expect(crudos, ['24'], reason: 'el 24 es la hoja de filtros');
    });

    test('no quedan spinners: la carga se muestra con siluetas', () {
      expect(fuente.contains('CircularProgressIndicator'), isFalse);
      expect(fuente.contains('AuraSkeleton'), isTrue);
    });

    test('la escala tipográfica no tiene tamaños contiguos sueltos', () {
      final crudos = RegExp(r'fontSize: (\d+)')
          .allMatches(fuente)
          .map((m) => int.parse(m.group(1)!))
          .toSet();
      // Queda el 22 del título de pantalla, que hoy es igual en el Inicio.
      expect(crudos, {22});
    });

    test('el margen lateral es el de la app, no un 22 propio', () {
      expect(fuente.contains('fromLTRB(22, 18, 22, 24)'), isFalse);
      expect(fuente.contains('AuraEspacio.margen'), isTrue);
    });
  });

  test('los tokens que usa Explorar son los del sistema', () {
    expect(AuraRadio.tarjeta, 16);
    expect(AuraRadio.boton, 12);
    expect(AuraEspacio.margen, 20);
    expect(AuraTipo.secundario, 13);
  });
}
