// Cuándo se le pregunta a la alumna "¿no pudiste ir o la clase no se dio?"
// (16/10/2026).
//
// El agujero que tapa: si el estudio no da la clase, la alumna pierde los
// créditos y el estudio cobra. Pasó tres veces y las tres se arreglaron a
// mano. Diseño cerrado en `supabase/pendientes/RETOMAR_ACA.md` (17/9).
//
// Esta es la mitad del cliente: cuándo mostrar la pregunta. La otra mitad
// —qué pasa al responder— vive en la RPC `reportar_mi_clase`, que vuelve a
// validar todo del lado del servidor. Estos tests NO son la seguridad: son la
// experiencia. La seguridad está en la base.

import 'package:aura_app/utils/reporte_clase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ahora = DateTime(2026, 10, 16, 20, 0);

  Map<String, dynamic> reserva({
    required DateTime fechaClase,
    int duracion = 60,
    String estado = 'completada',
    String? reporteAt,
    String? motivo,
  }) => {
    'id': 1,
    'estado': estado,
    'reporte_at': reporteAt,
    'reporte_motivo': motivo,
    'clases': {
      'id': 9,
      'fecha': fechaClase.toIso8601String(),
      'duracion_min': duracion,
    },
  };

  group('se puede avisar', () {
    test('apenas termina la clase', () {
      // Terminó hace media hora.
      expect(
        puedeReportar(
          reserva(fechaClase: DateTime(2026, 10, 16, 18, 30)),
          ahora: ahora,
        ),
        isTrue,
      );
    });

    test('hasta 48 h después de que termina', () {
      // Clase del 14 a las 19:00, termina 20:00 → justo 48 h.
      expect(
        puedeReportar(
          reserva(fechaClase: DateTime(2026, 10, 14, 19, 0)),
          ahora: ahora,
        ),
        isTrue,
      );
    });
  });

  group('NO se puede avisar', () {
    test('pasadas las 48 h: el mes se liquida y ya es tarde', () {
      expect(
        puedeReportar(
          reserva(fechaClase: DateTime(2026, 10, 14, 18, 59)),
          ahora: ahora,
        ),
        isFalse,
      );
    });

    test('si la clase todavía no terminó', () {
      // Empezó hace 10 minutos y dura una hora.
      expect(
        puedeReportar(
          reserva(fechaClase: DateTime(2026, 10, 16, 19, 50)),
          ahora: ahora,
        ),
        isFalse,
      );
    });

    test('si la clase ni siquiera empezó', () {
      expect(
        puedeReportar(
          reserva(fechaClase: DateTime(2026, 10, 17, 10, 0)),
          ahora: ahora,
        ),
        isFalse,
      );
    });

    test('si ya avisó: no se pregunta dos veces', () {
      expect(
        puedeReportar(
          reserva(
            fechaClase: DateTime(2026, 10, 16, 18, 30),
            reporteAt: '2026-10-16T19:00:00Z',
            motivo: 'no_se_dio',
          ),
          ahora: ahora,
        ),
        isFalse,
      );
    });

    test('si la reserva estaba cancelada: nadie perdió créditos', () {
      for (final e in ['cancelada', 'cancelada_por_estudio']) {
        expect(
          puedeReportar(
            reserva(fechaClase: DateTime(2026, 10, 16, 18, 30), estado: e),
            ahora: ahora,
          ),
          isFalse,
          reason: e,
        );
      }
    });

    test('si la fila viene sin clase o sin fecha, no se rompe', () {
      expect(puedeReportar({'id': 1}, ahora: ahora), isFalse);
      expect(
        puedeReportar({
          'id': 1,
          'clases': {'id': 9},
        }, ahora: ahora),
        isFalse,
      );
    });
  });

  test('la duración de la clase cuenta para el plazo', () {
    // Una clase larga termina más tarde, así que el plazo arranca después.
    // Empieza 14/10 18:30 y dura 120 min → termina 20:30, dentro de las 48 h.
    expect(
      puedeReportar(
        reserva(fechaClase: DateTime(2026, 10, 14, 18, 30), duracion: 120),
        ahora: ahora,
      ),
      isTrue,
    );
    // La misma hora de inicio con 60 min termina 19:30: ya pasaron 48 h y media.
    expect(
      puedeReportar(
        reserva(fechaClase: DateTime(2026, 10, 14, 18, 30)),
        ahora: ahora,
      ),
      isFalse,
    );
  });

  group('lo que ve quien ya avisó', () {
    test('"no se dio" queda en revisión', () {
      expect(
        etiquetaDeReporte({
          'reporte_at': '2026-10-16T19:00:00Z',
          'reporte_motivo': 'no_se_dio',
        }),
        'Lo estamos revisando',
      );
    });

    test('"no pude ir" queda registrado, sin drama', () {
      expect(
        etiquetaDeReporte({
          'reporte_at': '2026-10-16T19:00:00Z',
          'reporte_motivo': 'no_pude_ir',
        }),
        'Avisaste que no pudiste ir',
      );
    });

    test('quien no avisó no ve nada', () {
      expect(etiquetaDeReporte({'reporte_at': null}), isNull);
    });
  });
}
