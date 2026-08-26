import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_app/screens/clases/mis_clases_screen.dart';

void main() {
  testWidgets('el editor de horarios por día se construye y opera', (tester) async {
    final horarios = <int, List<TimeOfDay>>{};
    var cambios = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(builder: (ctx, setS) {
            return debugHorariosPorDiaEditor(
              dias: const [1, 3],
              horarios: horarios,
              onChanged: () => setS(() => cambios++),
            );
          }),
        ),
      ),
    ));
    expect(find.text('Horarios'), findsOneWidget);
    expect(find.text('sin horarios'), findsNWidgets(2));

    // + agregar en Lun → time picker 24h → OK
    await tester.tap(find.byTooltip('Agregar horario').first);
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('08:00'), findsOneWidget);
    expect(cambios, 1);

    // copiar a…
    await tester.tap(find.byTooltip('Copiar a otros días').first);
    await tester.pumpAndSettle();
    expect(find.text('Copiar Lun a…'), findsOneWidget);
    await tester.tap(find.text('Copiar'));
    await tester.pumpAndSettle();
    expect(find.text('08:00'), findsNWidgets(2));

    // completar un rango
    await tester.tap(find.text('Completar un rango…'));
    await tester.pumpAndSettle();
    expect(find.text('Completar un rango'), findsOneWidget);
    await tester.tap(find.textContaining('Agregar'));
    await tester.pumpAndSettle();
    expect(find.text('sin horarios'), findsNothing);
  });
}
