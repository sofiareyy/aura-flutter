// El muro de registro del modo visita. Bug del 2/9: los dos botones no hacían
// NADA porque `GoRouterState.of()` no funciona dentro de un diálogo (es una
// ruta hermana, no cuelga de la página) y lanzaba GoError, que se comía el
// onPressed. Era conversión perdida: la invitada que quería reservar no podía
// ni registrarse ni entrar.
import 'package:aura_app/widgets/registro_muro.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Router mínimo con las tres rutas que importan.
GoRouter _router(List<String> visitadas) => GoRouter(
      initialLocation: '/clase/123',
      routes: [
        GoRoute(
          path: '/clase/:id',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => RegistroMuro.mostrar(
                  context,
                  motivo: MuroMotivo.reservar,
                ),
                child: const Text('Registrate para reservar'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) {
            visitadas.add(state.uri.toString());
            return const Scaffold(body: Text('PANTALLA LOGIN'));
          },
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) {
            visitadas.add(state.uri.toString());
            return const Scaffold(body: Text('PANTALLA REGISTRO'));
          },
        ),
      ],
    );

Future<void> _abrirMuro(WidgetTester tester, List<String> visitadas) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: _router(visitadas)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Registrate para reservar'));
  await tester.pumpAndSettle();
  expect(find.text('Crear cuenta'), findsOneWidget,
      reason: 'el muro tiene que abrirse');
}

void main() {
  group('descargar la app: SOLO en web desde iPhone', () {
    // La regla de los tres casos. Se prueba la función pura, así no depende
    // de simular navegadores.
    test('web + iPhone → ofrece App Store con el ct del muro', () {
      final d = RegistroMuro.descargaPara(TargetPlatform.iOS, esWeb: true);
      expect(d, isNotNull);
      expect(d!.tienda, 'App Store');
      expect(d.url, contains('ct=muro_web'));
      expect(d.url, contains('pt=128832642'));
      expect(d.url, contains('id6764207399'));
    });

    test('web + Android → NO ofrece nada (Play todavía no está publicado)',
        () {
      expect(
        RegistroMuro.descargaPara(TargetPlatform.android,
            esWeb: true, androidPublicado: false),
        isNull,
      );
    });

    test('web + escritorio → NO ofrece nada (no hay app)', () {
      for (final p in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(RegistroMuro.descargaPara(p, esWeb: true), isNull, reason: '$p');
      }
    });

    test('DENTRO de la app nativa → NO ofrece descargarla, ya la tiene', () {
      for (final p in [TargetPlatform.iOS, TargetPlatform.android]) {
        expect(RegistroMuro.descargaPara(p, esWeb: false), isNull,
            reason: '$p nativo');
      }
    });

    test('cuando Android se publique, alcanza con el booleano', () {
      final d = RegistroMuro.descargaPara(TargetPlatform.android,
          esWeb: true, androidPublicado: true);
      expect(d, isNotNull);
      expect(d!.tienda, 'Google Play');
      // Y el iPhone sigue igual.
      expect(
        RegistroMuro.descargaPara(TargetPlatform.iOS,
                esWeb: true, androidPublicado: true)!
            .tienda,
        'App Store',
      );
    });
  });

  testWidgets('"Crear cuenta" navega a /register y NO tira excepción',
      (tester) async {
    final visitadas = <String>[];
    await _abrirMuro(tester, visitadas);

    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('PANTALLA REGISTRO'), findsOneWidget);
    expect(find.text('Crear cuenta'), findsNothing,
        reason: 'el muro se cierra al navegar');
  });

  testWidgets('"Ya tengo cuenta" navega a /login y NO tira excepción',
      (tester) async {
    final visitadas = <String>[];
    await _abrirMuro(tester, visitadas);

    await tester.tap(find.text('Ya tengo cuenta'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('PANTALLA LOGIN'), findsOneWidget);
  });

  testWidgets('se lleva ?volver= con la ruta donde estaba la invitada',
      (tester) async {
    final visitadas = <String>[];
    await _abrirMuro(tester, visitadas);

    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();

    expect(visitadas.single, contains('volver='));
    expect(Uri.parse(visitadas.single).queryParameters['volver'],
        '/clase/123',
        reason: 'después de registrarse vuelve a la clase que la trajo');
  });

  testWidgets('la cruz cierra sin navegar: sigue explorando donde estaba',
      (tester) async {
    final visitadas = <String>[];
    await _abrirMuro(tester, visitadas);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(visitadas, isEmpty);
    expect(find.text('Registrate para reservar'), findsOneWidget);
  });
}
