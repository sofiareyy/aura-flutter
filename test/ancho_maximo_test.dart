// El tope de ancho en pantalla grande (6/9/2026).
//
// Lo que pasaba: Inicio, Explorar y los dos detalles ya topaban su ancho, pero
// el resto de la app no. En un monitor de 1920 las listas de reservas, el
// perfil y el backoffice se estiraban de lado a lado: renglones de 1900 px que
// el ojo no puede seguir.
import 'dart:io';

import 'package:aura_app/utils/grilla_responsive.dart';
import 'package:aura_app/widgets/ancho_maximo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Las pantallas con scroll de página del lado de la alumna, del estudio y del
/// backoffice. Si mañana se agrega una sin tope, el test la caza.
const pantallas = <String>[
  'reservas/mis_reservas_screen', 'reservas/reserva_confirmada_screen',
  'reservas/reserva_gestion_screen', 'reservas/confirmar_reserva_screen',
  'perfil/mi_perfil_screen', 'perfil/configuracion_screen',
  'perfil/editar_perfil_screen', 'perfil/notificaciones_screen',
  'perfil/ayuda_screen', 'perfil/cambiar_contrasena_screen',
  'creditos/mis_creditos_screen', 'creditos/comprar_creditos_screen',
  'creditos/historial_creditos_screen',
  'plan/checkout_screen', 'plan/cambiar_plan_screen',
  'plan/payment_result_screen', 'referidos/referidos_screen',
  'auth/login_screen', 'auth/register_screen', 'auth/reset_password_screen',
  'auth/seleccionar_acceso_screen',
  'home/home_screen', 'explorar/explorar_screen',
  'clases/detalle_clase_screen', 'estudios/detalle_estudio_screen',
  'admin/admin_liquidaciones_screen', 'admin/admin_dashboard_screen',
  'admin/admin_estudios_screen', 'admin/admin_usuarios_screen',
  'admin/admin_reservas_screen', 'admin/admin_pricing_screen',
  'admin/admin_historial_screen', 'admin/admin_config_screen',
  'admin/admin_empresas_screen',
  'cobros/cobros_screen', 'estudios/perfil_estudio_screen',
  'estudios/dashboard_estudios_screen', 'estudios/resenas_screen',
  'estudio/aura_gestion_screen', 'asistencia/asistencia_screen',
  'clases/mis_clases_screen',
];

void main() {
  test('ninguna pantalla con scroll quedó sin tope de ancho', () {
    final sinTope = <String>[];
    for (final p in pantallas) {
      final f = File('lib/screens/$p.dart').readAsStringSync();
      final tiene = f.contains('AnchoMaximo') ||
          f.contains('anchoMaxDetalle') ||
          f.contains('anchoMaxBuscador') ||
          f.contains('anchoMaxVidriera') ||
          f.contains('anchoMaxFormulario');
      if (!tiene) sinTope.add(p);
    }
    expect(sinTope, isEmpty, reason: 'se estiran en desktop: $sinTope');
  });

  testWidgets('en un monitor de 1920 el contenido NO se estira', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AnchoMaximo(
            child: SizedBox(width: double.infinity, height: 40, key: Key('c')),
          ),
        ),
      ),
    );
    expect(t.getSize(find.byKey(const Key('c'))).width, anchoMaxDetalle);
  });

  testWidgets('el formulario topa más angosto', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AnchoMaximo.formulario(
            child: SizedBox(width: double.infinity, height: 40, key: Key('c')),
          ),
        ),
      ),
    );
    expect(t.getSize(find.byKey(const Key('c'))).width, anchoMaxFormulario);
  });

  for (final ancho in [320.0, 390.0, 430.0, 800.0]) {
    testWidgets('a $ancho px (teléfono y tablet) NO cambia nada', (t) async {
      t.view.physicalSize = Size(ancho, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnchoMaximo(
              child: const SizedBox(
                width: double.infinity,
                height: 40,
                key: Key('c'),
              ),
            ),
          ),
        ),
      );
      // Por debajo del tope, ocupa todo: el teléfono se ve igual que antes.
      expect(t.getSize(find.byKey(const Key('c'))).width, ancho);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('una pantalla REAL a 1920: el contenido queda centrado en 1100', (
    t,
  ) async {
    // La estructura de una pantalla de la app: Scaffold con AppBar y un
    // ListView adentro. El fondo y la AppBar siguen ocupando los 1920; sólo
    // el contenido topa.
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Mis reservas')),
          body: AnchoMaximo(
            child: ListView(
              children: const [
                SizedBox(height: 80, key: Key('fila')),
                SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pump();
    expect(t.getSize(find.byKey(const Key('fila'))).width, 1100);
    // La AppBar NO se recorta: sigue de lado a lado.
    expect(t.getSize(find.byType(AppBar)).width, 1920);
    expect(t.takeException(), isNull);
  });
}
