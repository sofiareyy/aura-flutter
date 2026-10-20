// La cola de asistencia sin conexión (20/10/2026).
//
// Cubre el racimo de cinco defectos de la pantalla de Asistencia, que son el
// mismo error visto de cinco maneras: informaba éxito sin mirar qué hizo la
// base. Los dos que se pueden probar sin levantar la pantalla son los que más
// importan, porque son los que le dan vuelta la decisión al estudio:
//
//   · tratar un rechazo del servidor como "sin conexión"
//   · sincronizar como `presente` algo que se marcó `ausente`

import 'package:aura_app/utils/asistencia_offline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('qué es "sin conexión" y qué no', () {
    test('un rechazo de RLS NO es falta de conexión', () {
      // Es el caso que rompía: 42501 mostraba el popup verde "Guardado
      // offline" y el estudio se iba convencido de que la tomó.
      expect(
        esFallaDeRed(
          const PostgrestException(message: 'permission denied', code: '42501'),
        ),
        isFalse,
      );
    });

    test('un guard de la base tampoco', () {
      // P0001 es lo que tira `reservas_no_marcar_antes_de_tiempo`.
      expect(
        esFallaDeRed(
          const PostgrestException(message: 'Todavía no', code: 'P0001'),
        ),
        isFalse,
      );
    });

    test('un problema de sesión tampoco', () {
      expect(esFallaDeRed(const AuthException('jwt expired')), isFalse);
    });

    test('quedarse sin internet SÍ', () {
      // Lo que no vino de PostgREST es la red: si el servidor hubiera
      // contestado —aunque fuera para rechazar— habría una excepción suya.
      expect(esFallaDeRed(Exception('Failed host lookup')), isTrue);
    });
  });

  group('lo que se encola', () {
    test('se acuerda de SI era presente o ausente', () {
      // El bug: la cola guardaba sólo el QR y sincronizaba siempre
      // 'presente'. Un "marcar ausente" volvía como presente.
      final p = PendienteAsistencia(
        codigoQr: 'ABC',
        estado: 'ausente',
        cuando: DateTime(2026, 10, 20, 19),
      );
      expect(p.aUpdate()['estado'], 'ausente');
      expect(
        p.aUpdate()['checked_in_at'],
        isNull,
        reason: 'ausente no sella check-in',
      );
    });

    test('presente sella la hora del ESCANEO, no la de la sincronización', () {
      final p = PendienteAsistencia(
        codigoQr: 'ABC',
        estado: 'presente',
        cuando: DateTime(2026, 10, 20, 19),
      );
      expect(p.aUpdate()['checked_in_at'], contains('2026-10-20T19:00'));
    });

    test('sobrevive una ida y vuelta por JSON', () {
      final p = PendienteAsistencia(
        codigoQr: 'ABC',
        estado: 'ausente',
        cuando: DateTime(2026, 10, 20, 19),
      );
      final vuelta = PendienteAsistencia.deJson(p.aJson())!;
      expect(vuelta.codigoQr, 'ABC');
      expect(vuelta.estado, 'ausente');
      expect(vuelta.cuando, p.cuando);
    });

    test('lo encolado por la versión vieja no se pierde', () {
      // La cola anterior sólo tenía `codigo_qr`. Si al actualizar la app esos
      // se descartaran, se perdería asistencia ya tomada.
      final viejo = PendienteAsistencia.deJson({
        'codigo_qr': 'VIEJO',
        'timestamp': '2026-10-19T10:00:00.000',
      })!;
      expect(viejo.estado, 'presente');
    });

    test('una entrada rota no se lleva puesta a las demás', () {
      final cola = leerCola([
        {'codigo_qr': 'A', 'estado': 'presente'},
        'basura',
        {'sin_codigo': true},
        {'codigo_qr': 'B', 'estado': 'ausente'},
      ]);
      expect(cola.map((p) => p.codigoQr), ['A', 'B']);
    });
  });

  group('encolar', () {
    PendienteAsistencia p(String qr, String estado) => PendienteAsistencia(
      codigoQr: qr,
      estado: estado,
      cuando: DateTime(2026, 10, 20),
    );

    test('vale lo ÚLTIMO que decidió el estudio', () {
      // Marca presente, se arrepiente, marca ausente. Si viajaran las dos, el
      // orden de sincronización decidiría, que es lo peor posible.
      final cola = encolar(encolar([], p('A', 'presente')), p('A', 'ausente'));
      expect(cola.length, 1);
      expect(cola.single.estado, 'ausente');
    });

    test('dos personas distintas conviven', () {
      final cola = encolar(encolar([], p('A', 'presente')), p('B', 'presente'));
      expect(cola.map((x) => x.codigoQr), ['A', 'B']);
    });
  });
}
