// ¿Queda alguna pantalla de la alumna con el desorden viejo?
//
// Este test es el que cierra la Etapa 2: recorre TODAS las pantallas del lado
// de la alumna y exige que no queden radios escritos a mano, salvo las tres
// excepciones que se decidieron a propósito. Si mañana alguien agrega una
// pantalla nueva con `circular(18)`, este test la caza.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Las pantallas del lado de la alumna. El lado del estudio (gestión, cobros,
/// asistencia) y las de auth quedan fuera a propósito: son otro sistema y otra
/// etapa.
const pantallas = <String>[
  'home/home_screen',
  'explorar/explorar_screen',
  'clases/detalle_clase_screen',
  'estudios/detalle_estudio_screen',
  'perfil/mi_perfil_screen',
  'perfil/configuracion_screen',
  'perfil/editar_perfil_screen',
  'perfil/notificaciones_screen',
  'perfil/ayuda_screen',
  'perfil/cambiar_contrasena_screen',
  'plan/checkout_screen',
  'plan/cambiar_plan_screen',
  'plan/payment_result_screen',
  'creditos/comprar_creditos_screen',
  'creditos/mis_creditos_screen',
  'creditos/historial_creditos_screen',
  'reservas/confirmar_reserva_screen',
  'reservas/mis_reservas_screen',
  'reservas/reserva_confirmada_screen',
  'reservas/reserva_gestion_screen',
  'mapa/mapa_screen',
  'referidos/referidos_screen',
];

/// Los radios que SÍ pueden quedar a mano, con su motivo:
///  · 24 → las hojas modales, que son otra superficie;
///  · 30 → el mapa entero, idem;
///  ·  2 → las barritas de arrastre y los separadores de 4 px de alto.
const permitidos = {'24', '30', '2'};

void main() {
  test('ninguna pantalla de la alumna quedó con radios sueltos', () {
    final sucias = <String, List<String>>{};
    for (final p in pantallas) {
      final fuente = File('lib/screens/$p.dart').readAsStringSync();
      final crudos = RegExp(r'circular\((\d+)\)')
          .allMatches(fuente)
          .map((m) => m.group(1)!)
          .where((v) => !permitidos.contains(v))
          .toSet()
          .toList();
      if (crudos.isNotEmpty) sucias[p] = crudos..sort();
    }
    expect(sucias, isEmpty, reason: 'les falta el sistema: $sucias');
  });

  test('todas usan los tokens', () {
    final sinTokens = <String>[];
    for (final p in pantallas) {
      final fuente = File('lib/screens/$p.dart').readAsStringSync();
      final usa = fuente.contains('AuraRadio.') ||
          fuente.contains('AuraTipo.') ||
          fuente.contains('AuraEspacio.');
      // `cambiar_contrasena` no tiene ni un radio ni un tamaño propio: hereda
      // todo del tema. No tener tokens ahí es correcto, no un olvido.
      if (!usa && !p.endsWith('cambiar_contrasena_screen')) sinTokens.add(p);
    }
    expect(sinTokens, isEmpty);
  });

  test('el número grande de créditos sigue intacto en las tres pantallas', () {
    // La regla de Sofía. Un reemplazo global de la escala se los come.
    expect(
      File('lib/screens/home/home_screen.dart').readAsStringSync(),
      contains('fontSize: 50'),
      reason: 'la tarjeta de créditos del Inicio',
    );
    expect(
      File('lib/screens/creditos/mis_creditos_screen.dart').readAsStringSync(),
      contains('fontSize: 56'),
      reason: 'el saldo de Mis créditos',
    );
    expect(
      File('lib/screens/clases/detalle_clase_screen.dart').readAsStringSync(),
      contains('fontSize: 38'),
      reason: 'el precio en créditos de la clase',
    );
  });
}
