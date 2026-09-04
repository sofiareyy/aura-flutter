// El cartel de borrado permanente: que sea IMPOSIBLE borrar con un toque, y
// que con historial de plata avise fuerte y ofrezca desactivar.
import 'package:aura_app/utils/eliminar_estudio_texto.dart';
import 'package:aura_app/widgets/admin/eliminar_estudio_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final conHistorial = ResumenBorrado.fromJson({
    'id': 4, 'nombre': 'Citra Barre', 'activo': true, 'clases': 391,
    'reservas': 5, 'reservas_futuras_vivas': 1, 'creditos_a_devolver': 18,
    'alumnas_afectadas': 1, 'liquidaciones': 0, 'resenas': 2, 'accesos': 3,
    'tiene_historial': true,
  });
  final limpio = ResumenBorrado.fromJson({
    'id': 7, 'nombre': 'BB Estudio Urquiza', 'activo': true, 'clases': 0,
    'reservas': 0, 'liquidaciones': 0, 'accesos': 2, 'tiene_historial': false,
  });

  Future<DecisionEliminarEstudio?> abrir(
      WidgetTester tester, ResumenBorrado r) async {
    DecisionEliminarEstudio? resultado;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              resultado = await EliminarEstudioDialog.show(ctx, r);
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return resultado;
  }

  bool eliminarHabilitado(WidgetTester tester) =>
      tester
          .widget<ElevatedButton>(find.byKey(const Key('boton_eliminar')))
          .enabled;

  testWidgets('el botón rojo arranca DESHABILITADO', (tester) async {
    await abrir(tester, conHistorial);
    expect(eliminarHabilitado(tester), isFalse);
  });

  testWidgets('un nombre parecido pero incompleto no lo habilita',
      (tester) async {
    await abrir(tester, conHistorial);
    await tester.enterText(find.byKey(const Key('campo_nombre')), 'Citra');
    await tester.pump();
    expect(eliminarHabilitado(tester), isFalse);
  });

  testWidgets('el nombre exacto lo habilita, aunque cambie la mayúscula',
      (tester) async {
    await abrir(tester, conHistorial);
    await tester.enterText(
        find.byKey(const Key('campo_nombre')), 'citra barre');
    await tester.pump();
    expect(eliminarHabilitado(tester), isTrue);
  });

  testWidgets('con historial: aviso rojo con los números y botón de desactivar',
      (tester) async {
    await abrir(tester, conHistorial);
    expect(find.byKey(const Key('advertencia_historial')), findsOneWidget);
    expect(find.textContaining('5 reservas'), findsOneWidget);
    expect(find.textContaining('18 créditos'), findsOneWidget);
    expect(find.byKey(const Key('boton_desactivar')), findsOneWidget);
  });

  testWidgets('sin historial: sin aviso rojo, se borra limpio', (tester) async {
    await abrir(tester, limpio);
    expect(find.byKey(const Key('advertencia_historial')), findsNothing);
    expect(find.textContaining('No se puede deshacer'), findsOneWidget);
  });

  testWidgets('"Mejor desactivar" devuelve desactivar sin escribir nada',
      (tester) async {
    DecisionEliminarEstudio? resultado;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              resultado = await EliminarEstudioDialog.show(ctx, conHistorial);
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('boton_desactivar')));
    await tester.pumpAndSettle();
    expect(resultado, DecisionEliminarEstudio.desactivar);
  });

  testWidgets('escribir el nombre y tocar el rojo devuelve eliminar',
      (tester) async {
    DecisionEliminarEstudio? resultado;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              resultado = await EliminarEstudioDialog.show(ctx, limpio);
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('campo_nombre')), 'BB Estudio Urquiza');
    await tester.pump();
    await tester.tap(find.byKey(const Key('boton_eliminar')));
    await tester.pumpAndSettle();
    expect(resultado, DecisionEliminarEstudio.eliminar);
  });
}
