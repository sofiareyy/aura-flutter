// La pantalla de bienvenida REAL con un aviso tocado con la app cerrada
// (29/10/2026). Reproduce el orden de un arranque en frío en el iPhone:
//   1. iOS entrega el toque ANTES de que exista quien lo atienda.
//   2. Se registra el handler (initState de la app).
//   3. El splash espera, resuelve el destino del rol y navega.
// Antes del arreglo terminaba en Inicio o en el selector de acceso.
import 'dart:convert';

import 'package:aura_app/core/auth_flow_state.dart';
import 'package:aura_app/screens/auth/splash_screen.dart';
import 'package:aura_app/services/notificaciones_service.dart';
import 'package:aura_app/utils/ruta_de_notificacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _avisoLugar = '{"tipo":"pre_confirmada","codigo_qr":"AURA-QR-1"}';
const _destinoAviso = '/reserva-confirmada/AURA-QR-1?from_notif=true';

GoRouter _router(SplashParaTest t) {
  Widget pantalla(String n) => Scaffold(body: Text('PANTALLA $n'));
  return GoRouter(initialLocation: '/splash', routes: [
    GoRoute(path: '/splash', builder: (_, __) => AuthSplashScreen(paraTest: t)),
    GoRoute(path: '/home', builder: (_, __) => pantalla('inicio')),
    GoRoute(path: '/seleccionar-acceso', builder: (_, __) => pantalla('selector')),
    GoRoute(path: '/mis-reservas', builder: (_, __) => pantalla('mis reservas')),
    GoRoute(path: '/actualizar', builder: (_, __) => pantalla('actualizar')),
    GoRoute(
      path: '/reserva-confirmada/:qr',
      builder: (_, s) => pantalla('pre-reserva ${s.pathParameters['qr']}'),
    ),
  ]);
}

/// Lo mismo que hace main.dart con cada toque.
void Function(String) _handler(GoRouter r) => (payload) {
      final ruta = rutaDeNotificacion(jsonDecode(payload) as Map<String, dynamic>);
      if (ruta != null) NavegacionNotificacion.ir(ruta, r.go);
    };

String _donde(GoRouter r) => r.routerDelegate.currentConfiguration.uri.toString();

Future<void> _arrancar(WidgetTester tester, GoRouter r) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: r));
  await tester.pump();
}

/// Deja correr el splash (2,2 s de logo + el destino) y los 15 s del respaldo.
Future<void> _esperarTodo(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  setUp(NavegacionNotificacion.reiniciarParaTest);

  testWidgets('app cerrada, cuenta con 2 estudios: el aviso lleva a la pre-reserva, no al selector',
      (tester) async {
    final r = _router(SplashParaTest(
      conSesion: true,
      destino: () => Future.delayed(const Duration(milliseconds: 600), () => '/seleccionar-acceso'),
    ));
    NotificacionesService.instance.simularToqueParaTest(_avisoLugar); // 1
    NotificacionesService.instance.setNotificationTapHandler(_handler(r)); // 2
    await _arrancar(tester, r); // 3
    await _esperarTodo(tester);
    expect(_donde(r), _destinoAviso);
    expect(find.text('PANTALLA pre-reserva AURA-QR-1'), findsOneWidget);
  });

  testWidgets('app cerrada, alumna común: el aviso lleva a la pre-reserva, no a Inicio',
      (tester) async {
    final r = _router(SplashParaTest(conSesion: true, destino: () async => '/home'));
    NotificacionesService.instance.simularToqueParaTest(_avisoLugar);
    NotificacionesService.instance.setNotificationTapHandler(_handler(r));
    await _arrancar(tester, r);
    await _esperarTodo(tester);
    expect(_donde(r), _destinoAviso);
  });

  testWidgets('el toque llega MIENTRAS el splash resuelve el rol: igual gana el aviso',
      (tester) async {
    final r = _router(SplashParaTest(
      conSesion: true,
      destino: () => Future.delayed(const Duration(seconds: 2), () => '/seleccionar-acceso'),
    ));
    NotificacionesService.instance.setNotificationTapHandler(_handler(r));
    await _arrancar(tester, r);
    await tester.pump(const Duration(milliseconds: 2500)); // logo terminado, rol resolviéndose
    NotificacionesService.instance.simularToqueParaTest(_avisoLugar);
    await _esperarTodo(tester);
    expect(_donde(r), _destinoAviso);
  });

  testWidgets('sin aviso, el splash sigue yendo al destino del rol', (tester) async {
    final r = _router(SplashParaTest(conSesion: true, destino: () async => '/seleccionar-acceso'));
    NotificacionesService.instance.setNotificationTapHandler(_handler(r));
    await _arrancar(tester, r);
    await _esperarTodo(tester);
    expect(_donde(r), '/seleccionar-acceso');
  });

  testWidgets('app ya abierta: el toque navega en el momento', (tester) async {
    final r = _router(SplashParaTest(conSesion: true, destino: () async => '/home'));
    NotificacionesService.instance.setNotificationTapHandler(_handler(r));
    await _arrancar(tester, r);
    await _esperarTodo(tester);
    expect(_donde(r), '/home');
    NotificacionesService.instance.simularToqueParaTest('{"tipo":"recordatorio_resena"}');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(_donde(r), '/mis-reservas');
  });

  testWidgets('actualización obligatoria: gana la pantalla de actualizar', (tester) async {
    final r = _router(SplashParaTest(
      hayQueActualizar: true,
      conSesion: true,
      destino: () async => '/home',
    ));
    NotificacionesService.instance.simularToqueParaTest(_avisoLugar);
    NotificacionesService.instance.setNotificationTapHandler(_handler(r));
    await _arrancar(tester, r);
    await _esperarTodo(tester);
    expect(_donde(r), '/actualizar');
  });
}
