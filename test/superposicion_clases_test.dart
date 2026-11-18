import 'package:aura_app/utils/superposicion_clases.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('franjasSeCruzan', () {
    final a = DateTime(2026, 11, 19, 16);
    test('misma hora se cruza', () {
      expect(franjasSeCruzan(a, 45, a, 45), isTrue);
    });
    test('cruce parcial se cruza', () {
      expect(franjasSeCruzan(a, 45, DateTime(2026, 11, 19, 16, 30), 60), isTrue);
    });
    test('pegadas (una termina cuando empieza la otra) NO se cruzan', () {
      expect(franjasSeCruzan(a, 60, DateTime(2026, 11, 19, 17), 60), isFalse);
    });
    test('otro día no se cruza', () {
      expect(franjasSeCruzan(a, 45, DateTime(2026, 11, 20, 16), 45), isFalse);
    });
    test('duración nula o 0 cuenta como 1 minuto', () {
      expect(franjasSeCruzan(a, null, a, 0), isTrue);
    });
  });

  test('minutoDelDia', () {
    expect(minutoDelDia('08:30'), 510);
    expect(minutoDelDia('16:00:00'), 960);
    expect(minutoDelDia('x'), isNull);
    expect(minutoDelDia(null), isNull);
    expect(minutoDelDia('25:00'), isNull);
  });

  group('clasesQueSeCruzan', () {
    final clases = [
      {'id': 10821, 'fecha': '2026-11-19T16:00:00', 'duracion_min': 45},
      {'id': 10822, 'fecha': '2026-11-19T16:00:00', 'duracion_min': 45},
      {'id': 3, 'fecha': '2026-11-19T16:00:00', 'duracion_min': 45, 'cancelada': true},
      {'id': 4, 'fecha': '2026-11-19T18:00:00', 'duracion_min': 45},
    ];
    test('el caso de PHS del 19/11: la otra clase de las 16', () {
      final r = clasesQueSeCruzan(
        inicio: DateTime(2026, 11, 19, 16),
        duracionMin: 45,
        clases: clases,
        excluirId: 10822,
      );
      expect(r.map((c) => c['id']), [10821]);
    });
    test('ignora canceladas y a sí misma', () {
      final r = clasesQueSeCruzan(
        inicio: DateTime(2026, 11, 19, 18),
        duracionMin: 45,
        clases: clases,
        excluirId: 4,
      );
      expect(r, isEmpty);
    });
  });

  group('horarioFijoSeCruza', () {
    final horarios = [
      {'id': 1, 'dia_semana': 1, 'hora_inicio': '08:00:00', 'duracion_min': 60},
      {'id': 2, 'dia_semana': 1, 'hora_inicio': '10:00:00', 'duracion_min': 60, 'activo': false},
    ];
    // 23/11/2026 es lunes.
    final clases = [
      {'id': 50, 'fecha': '2026-11-23T19:00:00', 'duracion_min': 60, 'horario_fijo_id': 9},
      {'id': 51, 'fecha': '2026-11-23T12:00:00', 'duracion_min': 60, 'cancelada': true},
    ];
    test('se cruza con otro horario del mismo día', () {
      expect(
        horarioFijoSeCruza(dia: 1, minuto: 8 * 60 + 30, duracionMin: 60,
            horarios: horarios, clasesFuturas: clases),
        isTrue,
      );
    });
    test('otro día no', () {
      expect(
        horarioFijoSeCruza(dia: 2, minuto: 8 * 60, duracionMin: 60,
            horarios: horarios, clasesFuturas: clases),
        isFalse,
      );
    });
    test('un horario inactivo no cuenta', () {
      expect(
        horarioFijoSeCruza(dia: 1, minuto: 10 * 60, duracionMin: 60,
            horarios: horarios, clasesFuturas: clases),
        isFalse,
      );
    });
    test('se cruza con una clase suelta que cae ese día', () {
      expect(
        horarioFijoSeCruza(dia: 1, minuto: 19 * 60 + 30, duracionMin: 60,
            horarios: horarios, clasesFuturas: clases),
        isTrue,
      );
    });
    test('al editar, no choca consigo mismo ni con sus propias clases', () {
      expect(
        horarioFijoSeCruza(dia: 1, minuto: 19 * 60, duracionMin: 60,
            horarios: horarios, clasesFuturas: clases, excluirHorarioId: 9),
        isFalse,
      );
      expect(
        horarioFijoSeCruza(dia: 1, minuto: 8 * 60, duracionMin: 60,
            horarios: horarios, clasesFuturas: const [], excluirHorarioId: 1),
        isFalse,
      );
    });
    test('una clase cancelada no cuenta', () {
      expect(
        horarioFijoSeCruza(dia: 1, minuto: 12 * 60, duracionMin: 60,
            horarios: const [], clasesFuturas: clases),
        isFalse,
      );
    });
  });

  group('grillaSeCruza', () {
    test('dos franjas nuevas que se pisan entre sí', () {
      expect(
        grillaSeCruza(minutosPorDia: {1: [480, 510]}, duracionMin: 60,
            horarios: const [], clasesFuturas: const []),
        isTrue,
      );
    });
    test('franjas seguidas sin pisarse, sin nada cargado', () {
      expect(
        grillaSeCruza(minutosPorDia: {1: [480, 540, 600], 3: [480]},
            duracionMin: 60, horarios: const [], clasesFuturas: const []),
        isFalse,
      );
    });
    test('una franja nueva contra un horario existente', () {
      expect(
        grillaSeCruza(minutosPorDia: {1: [480]}, duracionMin: 60,
            horarios: [
              {'id': 1, 'dia_semana': 1, 'hora_inicio': '08:30', 'duracion_min': 45},
            ],
            clasesFuturas: const []),
        isTrue,
      );
    });
  });
}
