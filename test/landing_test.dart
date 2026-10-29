import 'package:aura_app/screens/auth/landing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// La landing de la pauta (29/10/2026): pantalla grande desde 900 px y
/// movimiento. Lo que NO se puede romper: el botón "Empezar ahora" visible
/// antes del segundo, y nada moviéndose con "reducir movimiento".
Future<void> _abrir(
  WidgetTester tester,
  Size tamano, {
  bool sinMovimiento = false,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: tamano, disableAnimations: sinMovimiento),
        child: const LandingScreen(),
      ),
    ),
  );
}

/// La opacidad con la que se ve un texto (la de su animación de entrada).
double _opacidad(WidgetTester tester, String texto) {
  final opacidades = tester.widgetList<Opacity>(
    find.ancestor(of: find.text(texto), matching: find.byType(Opacity)),
  );
  return opacidades.fold(1.0, (v, o) => v * o.opacity);
}

void main() {
  testWidgets('el botón "Empezar ahora" se ve completo antes del segundo', (
    tester,
  ) async {
    await _abrir(tester, const Size(390, 844));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_opacidad(tester, 'Empezar ahora'), lessThan(1));
    // Cuadro a cuadro, como el navegador, hasta el segundo justo.
    for (var ms = 100; ms < 1000; ms += 20) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(_opacidad(tester, 'Empezar ahora'), 1);
    // Termina de entrar todo lo de arriba antes de cerrar el test.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('con "reducir movimiento" se ve todo de entrada', (tester) async {
    await _abrir(tester, const Size(390, 844), sinMovimiento: true);
    await tester.pump();
    expect(_opacidad(tester, 'Empezar ahora'), 1);
    expect(_opacidad(tester, 'Un pack.\nTodos los estudios.'), 1);
    expect(find.byType(Opacity), findsNothing);
  });

  for (final ancho in [390.0, 900.0, 1440.0]) {
    testWidgets('a $ancho px no se desborda nada', (tester) async {
      await _abrir(tester, Size(ancho, 900));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('celular: botón de ancho completo y fotos en 3 columnas', (
    tester,
  ) async {
    await _abrir(tester, const Size(390, 844));
    await tester.pump(const Duration(seconds: 2));
    final boton = tester.getSize(
      find.widgetWithText(ElevatedButton, 'Empezar ahora'),
    );
    expect(boton.width, 350); // 390 menos 20 de cada lado
    final citra = tester.getTopLeft(find.text('Citra Barre'));
    final yoyo = tester.getTopLeft(find.text('YOYO Yoga'));
    expect(yoyo.dy, greaterThan(citra.dy)); // segunda fila
  });

  testWidgets('computadora: botón de 330, fotos en una fila, pasos en 3 '
      'columnas y tarjeta de 430', (tester) async {
    await _abrir(tester, const Size(1440, 900));
    await tester.pump(const Duration(seconds: 2));
    final boton = tester.getSize(
      find.widgetWithText(ElevatedButton, 'Empezar ahora'),
    );
    expect(boton.width, 330);
    final citra = tester.getTopLeft(find.text('Citra Barre'));
    final fit = tester.getTopLeft(find.text('Fit Pilates'));
    expect(fit.dy, citra.dy); // misma fila
    final paso1 = tester.getTopLeft(find.text('Comprás un pack de créditos'));
    final paso3 = tester.getTopLeft(find.text('Reservás y vas'));
    expect(paso3.dy, paso1.dy); // uno al lado del otro
    final tarjeta = tester.getSize(
      find.widgetWithText(ElevatedButton, 'Quiero mis créditos'),
    );
    expect(tarjeta.width, lessThanOrEqualTo(430));
  });
}
