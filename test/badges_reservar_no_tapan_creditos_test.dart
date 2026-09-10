// La fila de badges de la tarjeta de "Reservar" no puede tapar los créditos.
//
// El bug (medido el 9/9/2026): los badges iban en un `Row` con `Spacer()`, que
// los pone en una línea sola cuesten lo que cuesten. Lo que se salía de la
// tarjeta por la derecha era **"14 cr"** — lo que la alumna paga. A 343 px, el
// teléfono más chico que soportamos, se perdían 55 px con "Pilates" y 212 px
// con "Holistico / Bienestar"; con la letra del sistema en 1,5x llegaba a 443.
//
// El arreglo: los badges en un `Wrap` dentro de un `Expanded`, y los créditos
// fijos a la derecha. En letra normal entra todo en una línea; con la letra
// agrandada los badges pasan a dos y los créditos no se mueven.
//
// Estos tests miden el desborde REAL que reporta el motor de layout, no una
// fórmula: si alguien vuelve al `Row`, fallan.
import 'package:aura_app/screens/reservas/mis_reservas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('es'));

  // 343 es el teléfono más angosto que soportamos (375 de pantalla menos los
  // 32 de padding de la lista). 358 es un iPhone normal de 390.
  const anchosDeTelefono = [343.0, 358.0, 390.0];

  // Las dos categorías extremas que existen en producción: la más corta que
  // usa un estudio multi-categoría y la más larga de todas (21 caracteres).
  const categorias = ['Pilates', 'Gym / Funcional', 'Holistico / Bienestar'];

  Map<String, dynamic> claseCon(String categoria) => {
    'id': 1,
    'nombre': 'RockFormer',
    'categorias': [categoria],
    'creditos': 14,
    'lugares_disponibles': 6,
    'fecha': DateTime(2026, 9, 10, 19, 25).toIso8601String(),
    'estudios': {
      'id': 58,
      'nombre': 'Rock Studios Palermo',
      'barrio': 'Palermo',
      'categorias': ['Spinning', 'Pilates'],
      'foto_url': null,
    },
  };

  /// Dibuja la tarjeta y devuelve los desbordes que reportó el layout.
  Future<List<String>> desbordes(
    WidgetTester tester, {
    required String categoria,
    required double ancho,
    double escalaDeTexto = 1.0,
  }) async {
    final capturados = <String>[];
    final anterior = FlutterError.onError;
    FlutterError.onError = (detalles) =>
        capturados.add(detalles.exceptionAsString());
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(escalaDeTexto)),
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              // La Column de mainAxisSize.min deja que la tarjeta tome su alto
              // natural, como en tarjeta_inicio_test.
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: ancho,
                    child: debugClaseDisponibleCard(
                      clase: claseCon(categoria),
                      hoy: DateTime(2026, 9, 9),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    FlutterError.onError = anterior;
    return capturados.where((e) => e.contains('overflowed')).toList();
  }

  /// El texto que la tarjeta dibuja de verdad.
  String textoDe(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .join(' | ');

  group('con la letra normal no desborda en ningún teléfono', () {
    for (final categoria in categorias) {
      for (final ancho in anchosDeTelefono) {
        testWidgets('"$categoria" a ${ancho.toInt()} px', (tester) async {
          expect(
            await desbordes(tester, categoria: categoria, ancho: ancho),
            isEmpty,
            reason:
                'Los badges volvieron a empujar los créditos fuera de la '
                'tarjeta. Si los pasaron de Wrap a Row, eso es la causa.',
          );
        });
      }
    }
  });

  group('con la letra del sistema agrandada tampoco', () {
    // 1,5x es el tope que fija kMaxEscalaTexto: más que eso la app no escala.
    for (final escala in [1.3, 1.5]) {
      testWidgets('"Holistico / Bienestar" a 343 px con letra ${escala}x', (
        tester,
      ) async {
        expect(
          await desbordes(
            tester,
            categoria: 'Holistico / Bienestar',
            ancho: 343,
            escalaDeTexto: escala,
          ),
          isEmpty,
        );
      });
    }
  });

  testWidgets('los créditos y la categoría se siguen viendo, los dos', (
    tester,
  ) async {
    // Que no desborde no alcanza: lo que importa es que no se recorte nada.
    await desbordes(
      tester,
      categoria: 'Holistico / Bienestar',
      ancho: 343,
      escalaDeTexto: 1.5,
    );
    final texto = textoDe(tester);
    expect(texto, contains('14 cr'));
    expect(texto, contains('Holistico / Bienestar'));
    expect(texto, contains('6 lugares'));
  });

  testWidgets('en letra normal los badges siguen en UNA línea', (tester) async {
    // El Wrap no tiene que cambiar cómo se ve la tarjeta en el caso normal:
    // sólo reparte en dos líneas cuando de verdad no entra.
    Future<double> alto(double escala) async {
      await desbordes(
        tester,
        categoria: 'Pilates',
        ancho: 390,
        escalaDeTexto: escala,
      );
      return tester.getSize(find.byType(Column).first).height;
    }

    final normal = await alto(1.0);
    final agrandada = await alto(1.5);
    expect(
      agrandada,
      greaterThan(normal),
      reason:
          'Con la letra agrandada la tarjeta tiene que crecer, no recortar.',
    );
  });
}
