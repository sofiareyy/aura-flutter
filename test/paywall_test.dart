// La hoja que sube cuando los créditos no alcanzan.
//
// Lo que se cuida acá: que haya UNA sola acción principal (antes había dos
// botones con el mismo texto y el mismo destino), que exista una salida
// visible, y que a quien todavía no compró se le explique qué es un crédito.
import 'package:aura_app/screens/clases/detalle_clase_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> abrir(
    WidgetTester tester, {
    required int saldo,
    required int precio,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: debugPaywallSheet(
            creditosNecesarios: precio,
            creditosActuales: saldo,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  group('EL BUG: dos botones que parecían opciones distintas', () {
    testWidgets('ahora hay UNA sola acción principal', (tester) async {
      await abrir(tester, saldo: 2, precio: 10);
      expect(find.widgetWithText(ElevatedButton, 'Comprar créditos'),
          findsOneWidget);
      // Y ninguna otra cosa que diga lo mismo.
      expect(find.text('Comprar créditos'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('y una salida visible, que antes no existía', (tester) async {
      await abrir(tester, saldo: 2, precio: 10);
      expect(find.widgetWithText(TextButton, 'Ahora no'), findsOneWidget);
    });

    testWidgets('la salida cierra la hoja y no navega', (tester) async {
      // Se prueba sobre una ruta real (no un modal sheet) para ejercitar el
      // `Navigator.pop` de la hoja sin el andamiaje del bottom sheet.
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Center(child: Text('detrás'))),
      ));
      navKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: SingleChildScrollView(
            child: debugPaywallSheet(
              creditosNecesarios: 10,
              creditosActuales: 2,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Ahora no'), findsOneWidget);

      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();
      // La hoja se fue y quedó lo que había detrás: no navegó a ningún lado.
      expect(find.text('Ahora no'), findsNothing);
      expect(find.text('detrás'), findsOneWidget);
    });
  });

  group('el texto según quién mira', () {
    testWidgets('sin créditos: le explica el modelo de Aura', (tester) async {
      await abrir(tester, saldo: 0, precio: 10);
      expect(find.text('Necesitás créditos para reservar'), findsOneWidget);
      expect(find.textContaining('comprás un pack'), findsOneWidget);
      expect(find.textContaining('sin cuota mensual'), findsOneWidget);
    });

    testWidgets('con créditos: va derecho al número que falta', (tester) async {
      await abrir(tester, saldo: 2, precio: 10);
      expect(find.text('Te faltan 8 créditos'), findsOneWidget);
      expect(find.textContaining('y tenés 2'), findsOneWidget);
    });

    testWidgets('ya no dice "Créditos insuficientes"', (tester) async {
      await abrir(tester, saldo: 2, precio: 10);
      expect(find.text('Créditos insuficientes'), findsNothing);
    });

    testWidgets('NINGÚN texto de la hoja muestra un número negativo',
        (tester) async {
      for (final caso in [[0, 8], [2, 10], [1, 18], [0, 1]]) {
        await abrir(tester, saldo: caso[0], precio: caso[1]);
        final textos = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .join(' | ');
        expect(textos, isNot(contains('-')),
            reason: 'saldo ${caso[0]}, precio ${caso[1]} → $textos');
      }
    });
  });
}
