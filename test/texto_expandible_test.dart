// El "Ver más" de las descripciones largas.
//
// Los textos son los REALES de producción (4/9/2026): la descripción de
// Yoguica (986 caracteres, la pared que vio Sofía), la del workshop "Rito del
// Útero Munay Ki" (1484, la más larga que hay) y la de YN Pilates (100, que
// tiene que verse entera y sin adorno).
import 'package:aura_app/widgets/texto_expandible.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un teléfono de 390, menos el margen de página.
const anchoTelefono = 390.0 - 40;

Future<void> pump(WidgetTester tester, String texto, {double? ancho}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // Con scroll, como en las pantallas reales: abierto, el texto más
        // largo de producción mide más que un teléfono.
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: ancho ?? anchoTelefono,
              child: TextoExpandible(texto),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  final largo = 'Somos un espacio de yoga en Pilar. ' * 28; // ~980
  const corto = 'Estudio de pilates reformer con clases reducidas en Pilar.';

  testWidgets('un texto corto se ve entero y SIN "Ver más"', (tester) async {
    await pump(tester, corto);
    expect(find.text('Ver más'), findsNothing);
    expect(find.text(corto), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uno largo se recorta y ofrece "Ver más"', (tester) async {
    await pump(tester, largo);
    expect(find.text('Ver más'), findsOneWidget);
    final t = tester.widget<Text>(find.text(largo));
    expect(t.maxLines, 4, reason: 'plegado muestra 4 renglones');
  });

  testWidgets('al tocarlo se abre entero y ofrece cerrarlo', (tester) async {
    await pump(tester, largo);
    await tester.tap(find.text('Ver más'));
    await tester.pump();
    expect(find.text('Ver menos'), findsOneWidget);
    expect(find.text('Ver más'), findsNothing);
    final t = tester.widget<Text>(find.text(largo));
    expect(t.maxLines, isNull, reason: 'abierto no recorta');
  });

  testWidgets('y se puede volver a plegar', (tester) async {
    await pump(tester, largo);
    await tester.tap(find.text('Ver más'));
    await tester.pump();
    // Abierto, el texto mide más que el alto de la pantalla de test: hay que
    // traer el link a la vista antes de tocarlo.
    await tester.ensureVisible(find.text('Ver menos'));
    await tester.pump();
    await tester.tap(find.text('Ver menos'));
    await tester.pump();
    expect(find.text('Ver más'), findsOneWidget);
    expect(tester.widget<Text>(find.text(largo)).maxLines, 4);
  });

  testWidgets('el mismo texto en una pantalla ancha puede no desbordar', (
    tester,
  ) async {
    // La decisión se toma por ancho real, no por cantidad de caracteres.
    const medio = 'Clases de barre en Palermo, grupos reducidos y turnos '
        'de mañana y de tarde toda la semana.';
    await pump(tester, medio, ancho: 200);
    expect(find.text('Ver más'), findsOneWidget);
    await pump(tester, medio, ancho: 760);
    expect(find.text('Ver más'), findsNothing);
  });

  testWidgets('nada desborda con el texto más largo de producción', (
    tester,
  ) async {
    final workshop = 'Un encuentro para reconectar con el ciclo. ' * 35;
    await pump(tester, workshop);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Ver más'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
