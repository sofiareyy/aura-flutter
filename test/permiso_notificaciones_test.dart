import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_app/services/notificaciones_service.dart';

void main() {
  test('cada estado de iOS se traduce a un valor que la base acepta', () {
    expect(permisoDesdeEstadoIos(AuthorizationStatus.authorized), 'prendido');
    expect(permisoDesdeEstadoIos(AuthorizationStatus.denied), 'apagado');
    expect(permisoDesdeEstadoIos(AuthorizationStatus.provisional), 'provisorio');
    expect(permisoDesdeEstadoIos(AuthorizationStatus.notDetermined), 'sin_decidir');
  });
}
