// El botón de Google/Apple deja de girar al volver a la app (19/10/2026).
//
// EL BUG. `signInWithOAuth` con `externalApplication` abre el navegador y la
// pantalla se queda esperando el deep link. Si la persona vuelve sin terminar
// —cerró la pestaña, tocó atrás, se arrepintió— no pasa nada: no hay error,
// no hay callback, y el botón gira para siempre. La única salida era matar la
// app. En el embudo de alta, eso es una persona perdida.
//
// ALCANCE, medido en el código: Apple NATIVO en iOS ya estaba bien — la
// cancelación llega como `AuthorizationErrorCode.canceled` y ahí sí se apaga
// el spinner. El agujero era el camino del navegador: Google en todos lados
// y Apple en Android y web.
//
// POR QUÉ ESTE TEST Y NO UNO DE LA PANTALLA ENTERA. Login y Registro
// necesitan Supabase y el router para montarse, y el repo no tiene harness
// para eso. Lo que se puede aislar es la REGLA: un `State` que observa el
// ciclo de vida y apaga sus spinners al volver. Esta es la misma mecánica,
// con el mismo `WidgetsBindingObserver`, en un widget mínimo.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un calco de lo que hacen `_LoginScreenState` y `_RegisterScreenState`.
class _PantallaConSpinner extends StatefulWidget {
  const _PantallaConSpinner();

  @override
  State<_PantallaConSpinner> createState() => _PantallaConSpinnerState();
}

class _PantallaConSpinnerState extends State<_PantallaConSpinner>
    with WidgetsBindingObserver {
  bool loadingGoogle = false;
  bool loadingApple = false;

  /// Lo que hace el botón al tocarlo. Va por `setState`, como en las
  /// pantallas reales: poner el campo a mano no redibuja y el test mediría
  /// cualquier cosa.
  void prender({bool google = true}) => setState(() {
    if (google) {
      loadingGoogle = true;
    } else {
      loadingApple = true;
    }
  });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && (loadingGoogle || loadingApple)) {
      setState(() {
        loadingGoogle = false;
        loadingApple = false;
      });
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  Widget build(BuildContext context) => Text(
    loadingGoogle || loadingApple ? 'girando' : 'quieto',
    textDirection: TextDirection.ltr,
  );
}

void main() {
  Future<_PantallaConSpinnerState> montar(WidgetTester tester) async {
    await tester.pumpWidget(const _PantallaConSpinner());
    return tester.state<_PantallaConSpinnerState>(
      find.byType(_PantallaConSpinner),
    );
  }

  testWidgets('al volver a la app sin haber entrado, el botón se apaga', (
    tester,
  ) async {
    final s = await montar(tester);
    s.prender();
    await tester.pump();
    expect(find.text('girando'), findsOneWidget);

    // La persona volvió del navegador.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('quieto'), findsOneWidget);
  });

  testWidgets('también con Apple', (tester) async {
    final s = await montar(tester);
    s.prender(google: false);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('quieto'), findsOneWidget);
  });

  testWidgets('irse de la app NO apaga el spinner', (tester) async {
    // Al salir al navegador la app pasa por `paused`. Si eso apagara el
    // spinner, el botón volvería a verse disponible mientras el login está
    // en curso.
    final s = await montar(tester);
    s.prender();
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('girando'), findsOneWidget);
  });

  testWidgets('volver sin nada en curso no rompe nada', (tester) async {
    await montar(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('quieto'), findsOneWidget);
  });

  testWidgets('el observer se desengancha al salir de la pantalla', (
    tester,
  ) async {
    // Sin esto, el State queda escuchando el ciclo de vida después de
    // destruido y `setState` tira "called after dispose".
    await montar(tester);
    await tester.pumpWidget(
      const Text('otra', textDirection: TextDirection.ltr),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
