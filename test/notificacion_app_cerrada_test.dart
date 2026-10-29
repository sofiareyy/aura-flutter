// Tocar una notificación con la app CERRADA (29/10/2026).
//
// Antes: el toque de un push de Firebase se perdía (llegaba antes de que
// hubiera quién lo atendiera) y, aunque llegara, el splash lo pisaba yendo al
// destino del rol (Inicio o el selector de acceso). Con la app cerrada ningún
// aviso llevaba a ningún lado.
import 'package:aura_app/core/auth_flow_state.dart';
import 'package:aura_app/services/notificaciones_service.dart';
import 'package:aura_app/utils/ruta_de_notificacion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a dónde lleva cada aviso (mismas rutas que antes)', () {
    test('se liberó un lugar: a SU pre-reserva', () {
      expect(rutaDeNotificacion({'tipo': 'pre_confirmada', 'codigo_qr': 'AURA-X-1'}),
          '/reserva-confirmada/AURA-X-1?from_notif=true');
    });
    test('se liberó un lugar sin código: a Mis reservas', () {
      expect(rutaDeNotificacion({'tipo': 'pre_confirmada'}), '/mis-reservas');
    });
    test('recordatorio de clase', () {
      expect(rutaDeNotificacion({'tipo': 'recordatorio_clase', 'codigo_qr': 'Q'}),
          '/reserva-confirmada/Q?from_notif=true');
      expect(rutaDeNotificacion({'tipo': 'recordatorio_clase'}), isNull);
    });
    test('reseñas y créditos', () {
      expect(rutaDeNotificacion({'tipo': 'recordatorio_resena'}), '/mis-reservas');
      expect(rutaDeNotificacion({'tipo': 'resena_nueva', 'estudio_id': 9}),
          '/estudio/9/resenas?dueno=1');
      expect(rutaDeNotificacion({'tipo': 'resena_nueva'}), '/estudio/dashboard');
      expect(rutaDeNotificacion({'tipo': 'inactividad_creditos'}), '/explorar');
    });
    test('tipo desconocido: sólo abre la app', () {
      expect(rutaDeNotificacion({'tipo': 'reserva_profe'}), isNull);
      expect(rutaDeNotificacion({}), isNull);
    });
  });

  group('el splash no pisa el aviso', () {
    setUp(NavegacionNotificacion.reiniciarParaTest);

    test('app cerrada: la ruta se guarda y el splash va ahí, no a Inicio', () {
      expect(NavegacionNotificacion.registrar('/reserva-confirmada/Q'), isFalse,
          reason: 'todavía no hay que navegar: lo hace el splash');
      expect(NavegacionNotificacion.resolverDestino('/home'), '/reserva-confirmada/Q');
    });

    test('cuenta con estudio: tampoco cae en el selector de acceso', () {
      NavegacionNotificacion.registrar('/mis-reservas');
      expect(NavegacionNotificacion.resolverDestino('/seleccionar-acceso'), '/mis-reservas');
    });

    test('sin aviso, el splash sigue yendo al destino del rol', () {
      expect(NavegacionNotificacion.resolverDestino('/home'), '/home');
      NavegacionNotificacion.reiniciarParaTest();
      expect(NavegacionNotificacion.resolverDestino('/estudio/dashboard'), '/estudio/dashboard');
    });

    test('la ruta se usa una sola vez', () {
      NavegacionNotificacion.registrar('/explorar');
      NavegacionNotificacion.resolverDestino('/home');
      expect(NavegacionNotificacion.pendiente, isNull);
    });

    test('app abierta o en segundo plano: navega en el momento', () {
      NavegacionNotificacion.resolverDestino('/home');
      expect(NavegacionNotificacion.registrar('/mis-reservas'), isTrue);
      expect(NavegacionNotificacion.pendiente, isNull);
    });

    test('sin sesión o actualización obligatoria: el aviso se descarta', () {
      NavegacionNotificacion.registrar('/mis-reservas');
      NavegacionNotificacion.descartar();
      expect(NavegacionNotificacion.pendiente, isNull);
      expect(NavegacionNotificacion.registrar('/explorar'), isTrue,
          reason: 'los toques siguientes navegan en el momento');
    });
  });

  group('el toque que llega antes de tiempo no se pierde', () {
    test('se entrega apenas hay quién lo atienda', () {
      final s = NotificacionesService.instance;
      s.simularToqueParaTest('{"tipo":"pre_confirmada"}');
      final recibidos = <String>[];
      s.setNotificationTapHandler(recibidos.add);
      expect(recibidos, ['{"tipo":"pre_confirmada"}']);
    });

    test('con handler ya registrado va directo, y no se repite', () {
      final s = NotificacionesService.instance;
      final recibidos = <String>[];
      s.setNotificationTapHandler(recibidos.add);
      s.simularToqueParaTest('a');
      expect(recibidos, ['a']);
      s.setNotificationTapHandler(recibidos.add);
      expect(recibidos, ['a'], reason: 'no hay nada guardado para re-entregar');
    });
  });
}
