import 'package:aura_app/screens/home/home_screen.dart';
import 'package:aura_app/utils/grilla_responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// La tarjeta de Inicio (la "vidriera") con la foto en proporción 16:9.
///
/// El riesgo concreto que cubren estos tests: la foto dejó de tener alto fijo
/// (132) y ahora crece con el ancho. Dentro de los carruseles horizontales el
/// alto está FIJADO por el `SizedBox` que los envuelve, así que si ese número
/// se queda corto la tarjeta desborda (la franja amarilla y negra). Acá se
/// mide el alto real que necesita y se verifica contra el que usa la pantalla.
void main() {
  setUpAll(() async => initializeDateFormatting('es'));

  final clase = <String, dynamic>{
    'id': 1,
    'nombre': 'Barre Intermedio con nombre largo',
    'creditos': 14,
    'lugares_disponibles': 6,
    'fecha': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
    'estudios': {
      'nombre': 'Un estudio con nombre bien largo para forzar dos renglones',
      'categoria': 'Barre',
    },
  };

  Future<Size> medir(WidgetTester tester, double ancho) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            // La Column de afuera (mainAxisSize.min) es la que hace que la
            // tarjeta tome su alto NATURAL: sin ella se estira hasta el alto
            // de la pantalla de test. IntrinsicHeight NO sirve para medir acá
            // —con Texto adentro de un Row da un alto disparatado (592 px)—.
            child: SizedBox(
              width: ancho,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HomeNearbyClassCard(clase: clase, onTap: () {}),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return tester.getSize(find.byType(HomeNearbyClassCard));
  }

  testWidgets('la foto respeta 16:9 a cualquier ancho', (tester) async {
    for (final ancho in [320.0, 390.0, 543.0]) {
      await medir(tester, ancho);
      final foto = tester.getSize(find.byType(AspectRatio));
      expect(
        foto.width / foto.height,
        closeTo(proporcionFotoVidriera, 0.02),
        reason: 'a $ancho px de ancho la foto se salió de 16:9',
      );
      expect(foto.width, ancho - 2); // -2 por el borde de la tarjeta
    }
  });

  testWidgets('el alto reservado alcanza a cualquier ancho', (tester) async {
    // 320 = tarjeta del carrusel · 358 = una columna en un teléfono ·
    // 389 = tres columnas dentro de 1200 · 543 = dos columnas dentro de 1100.
    for (final ancho in [320.0, 358.0, 389.0, 543.0]) {
      final necesita = (await medir(tester, ancho)).height;
      final reservado = altoCardVidriera(ancho);
      expect(
        necesita,
        lessThanOrEqualTo(reservado),
        reason: 'a $ancho px la tarjeta necesita $necesita y la grilla '
            'reserva $reservado: desborda',
      );
      // Y que no sobre tanto como para dejar un hueco blanco visible.
      expect(reservado - necesita, lessThan(26), reason: 'sobra a $ancho px');
    }
  });

  testWidgets('no desborda dentro del carrusel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: altoCarruselVidriera,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              itemBuilder: (_, __) => SizedBox(
                width: 320,
                child: HomeNearbyClassCard(clase: clase, onTap: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
