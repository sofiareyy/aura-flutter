// Los chips de categoría: con servicios de precio fijo llevan el precio
// adentro; SIN servicios (todos los estudios de hoy) se ven exactamente como
// siempre, sin precio pegado ni ícono.
import 'package:aura_app/widgets/categorias_checklist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  const comunes = ['Barre', 'Pilates', 'Yoga'];

  testWidgets('caso normal: sin servicios, los chips son sólo el nombre',
      (tester) async {
    await tester.pumpWidget(_app(CategoriasChecklist(
      disponibles: comunes,
      seleccionadas: const ['Pilates'],
      onToggle: (_, _) {},
    )));
    for (final c in comunes) {
      expect(find.widgetWithText(FilterChip, c), findsOneWidget);
    }
    expect(find.textContaining(' cr'), findsNothing);
    expect(find.byIcon(Icons.sell_outlined), findsNothing);
  });

  testWidgets('con un servicio: ese chip lleva el precio; los demás no',
      (tester) async {
    await tester.pumpWidget(_app(CategoriasChecklist(
      disponibles: const [...comunes, 'Sauna'],
      seleccionadas: const [],
      precios: const {'Sauna': 14},
      onToggle: (_, _) {},
    )));
    expect(find.widgetWithText(FilterChip, 'Sauna · 14 cr'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Sauna'), findsNothing);
    for (final c in comunes) {
      expect(find.widgetWithText(FilterChip, c), findsOneWidget);
    }
    expect(find.textContaining(' cr'), findsOneWidget);
    // Sin marcar: ícono de etiqueta. Marcado: el tilde lo reemplaza.
    expect(find.byIcon(Icons.sell_outlined), findsOneWidget);
  });

  testWidgets('marcado, el servicio muestra el tilde y no el ícono',
      (tester) async {
    await tester.pumpWidget(_app(CategoriasChecklist(
      disponibles: const ['Yoga', 'Sauna'],
      seleccionadas: const ['Sauna'],
      precios: const {'Sauna': 14},
      onToggle: (_, _) {},
    )));
    expect(find.widgetWithText(FilterChip, 'Sauna · 14 cr'), findsOneWidget);
    expect(find.byIcon(Icons.sell_outlined), findsNothing);
  });

  testWidgets('un precio para una categoría que no está en la lista no dibuja nada',
      (tester) async {
    await tester.pumpWidget(_app(CategoriasChecklist(
      disponibles: comunes,
      seleccionadas: const [],
      precios: const {'Sauna': 14},
      onToggle: (_, _) {},
    )));
    expect(find.textContaining(' cr'), findsNothing);
  });

  test('etiquetaDe', () {
    final w = CategoriasChecklist(
      disponibles: const [],
      seleccionadas: const [],
      precios: const {'Sauna': 14},
      onToggle: (_, _) {},
    );
    expect(w.etiquetaDe('Sauna'), 'Sauna · 14 cr');
    expect(w.etiquetaDe('Yoga'), 'Yoga');
  });
}
