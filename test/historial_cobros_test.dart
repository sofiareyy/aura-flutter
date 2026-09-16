// El historial de Cobros del estudio. Números tomados de la base el 2/9/2026:
// la liquidación real de Hot Clic (2026-08, pagada, $8.400, comisión sellada
// 30%, valor del crédito $1.000).
import 'package:aura_app/utils/historial_cobros.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  // La liquidación REAL de la base.
  final liqHotClic = {
    'mes': '2026-08',
    'estado': 'pagado',
    'monto_a_pagar': 8400,
    'cantidad_reservas': 1,
    'comision_aplicada': '30.00',
    'valor_credito_aplicado': 1000,
  };

  Map<String, dynamic> reserva(String creada, int creditos,
          {String estado = 'completada'}) =>
      {'created_at': creada, 'estado': estado, 'creditos_usados': creditos};

  // Estudio con comisión ACTUAL del 30% y sin gracia.
  Map<String, dynamic> estudio({num comision = 30}) => {
        'comision_aura': comision,
        'valor_credito': 1000,
        'fecha_inicio_cobro': '2026-01-01',
      };

  final ahora = DateTime(2026, 9, 2);

  test('EL SELLADO ES INMUTABLE: bajás la comisión y el mes pagado no se mueve',
      () {
    // La misma reserva de agosto, mirada con la comisión de HOY al 20%:
    // el recálculo daría 12 cr × $1000 × 0,80 = $9.600 ≠ $8.400.
    final reservasAgosto = [reserva('2026-08-31 20:00:00', 12)];

    final conComisionNueva = armarHistorialCobros(
      reservas: reservasAgosto,
      liquidaciones: [liqHotClic],
      estudio: estudio(comision: 20), // ← Aura bajó la comisión después
      ahora: ahora,
    );

    final agosto = conComisionNueva.single;
    expect(agosto['monto'], 8400,
        reason: 'tiene que mostrar lo SELLADO, no el recálculo (\$9.600)');
    expect(agosto['estado'], kEstadoPagado);
    expect(agosto['comision'], '30%',
        reason: 'la constancia dice con qué comisión se cobró');
  });

  test('EL BUG VIEJO: un mes cerrado SIN liquidación ya no dice "Pagado"', () {
    final julio = armarHistorialCobros(
      reservas: [reserva('2026-07-15 10:00:00', 10)],
      liquidaciones: const [], // Aura no registró ningún pago
      estudio: estudio(),
      ahora: ahora,
    ).single;
    expect(julio['estado'], kEstadoACobrar);
    expect(julio['estado'], isNot('Pagado'));
    // Y el monto sí es el cálculo en vivo (no hay nada sellado):
    expect(julio['monto'], 10 * 1000 * 70 ~/ 100);
  });

  test('el mes EN CURSO dice "En curso", nunca "a cobrar el 5"', () {
    final sept = armarHistorialCobros(
      reservas: [reserva('2026-09-01 09:00:00', 14)],
      liquidaciones: const [],
      estudio: estudio(),
      ahora: ahora,
    ).single;
    expect(sept['estado'], kEstadoEnCurso);
  });

  test('liquidación PENDIENTE registrada → "A cobrar el 5" con SUS números',
      () {
    final fila = armarHistorialCobros(
      reservas: const [],
      liquidaciones: [
        {
          'mes': '2026-08',
          'estado': 'pendiente',
          'monto_a_pagar': 5000,
          'cantidad_reservas': 3,
        }
      ],
      estudio: estudio(),
      ahora: ahora,
    ).single;
    expect(fila['estado'], kEstadoACobrar);
    expect(fila['monto'], 5000);
    expect(fila['comision'], isNull,
        reason: 'la constancia de comisión es sólo de lo pagado');
  });

  test('los tres estados conviven ordenados del más nuevo al más viejo', () {
    final filas = armarHistorialCobros(
      reservas: [
        reserva('2026-09-01 09:00:00', 14), // en curso
        reserva('2026-07-10 09:00:00', 10), // cerrado sin liquidar
      ],
      liquidaciones: [liqHotClic], // agosto pagado
      estudio: estudio(),
      ahora: ahora,
    );
    expect(filas.map((f) => f['estado']).toList(),
        [kEstadoEnCurso, kEstadoPagado, kEstadoACobrar]);
  });

  group('el detalle del mes: auditar de dónde sale el monto', () {
    test('cada fila lleva su mes, para poder abrir SU desglose', () {
      final filas = armarHistorialCobros(
        reservas: [
          reserva('2026-09-01 09:00:00', 14),
          reserva('2026-07-10 09:00:00', 10),
        ],
        liquidaciones: [liqHotClic],
        estudio: estudio(),
        ahora: ahora,
      );
      expect(filas.map((f) => f['_mes']).toList(),
          ['2026-09', '2026-08', '2026-07']);
    });

    test('el mes PAGADO lleva su monto sellado, para que el detalle cierre',
        () {
      final agosto = armarHistorialCobros(
        reservas: [reserva('2026-08-31 20:00:00', 12)],
        liquidaciones: [liqHotClic],
        estudio: estudio(comision: 20), // comisión cambiada después
        ahora: ahora,
      ).single;
      expect(agosto['_sellado'], 8400);
      expect(agosto['monto'], agosto['_sellado'],
          reason: 'la fila y el detalle tienen que decir lo mismo');
      expect(agosto['comision'], '30%');
    });

    test('un mes SIN liquidación no tiene sellado: el detalle calcula en vivo',
        () {
      final julio = armarHistorialCobros(
        reservas: [reserva('2026-07-15 10:00:00', 10)],
        liquidaciones: const [],
        estudio: estudio(),
        ahora: ahora,
      ).single;
      expect(julio['_sellado'], isNull);
    });
  });

  group('asistencia en el detalle: quién fue de verdad', () {
    // Mismo criterio que Mis Reservas: sólo checked_in_at prueba asistencia.
    String etiqueta(Map<String, dynamic> r) {
      final asistio = r['checked_in_at'] != null;
      final ausente = r['estado'] == 'ausente';
      return asistio ? 'Presente' : (ausente ? 'Ausente' : 'Finalizada');
    }

    test('completada CON check-in → Presente (el bug: antes decía otra cosa)',
        () {
      expect(
          etiqueta({
            'estado': 'completada',
            'checked_in_at': '2026-08-27 08:05:00'
          }),
          'Presente');
    });

    test('completada SIN check-in → Finalizada, no "Presente"', () {
      expect(etiqueta({'estado': 'completada', 'checked_in_at': null}),
          'Finalizada');
    });

    test('ausente → Ausente', () {
      expect(etiqueta({'estado': 'ausente', 'checked_in_at': null}), 'Ausente');
    });
  });

  test('las canceladas no suman', () {
    final fila = armarHistorialCobros(
      reservas: [
        reserva('2026-07-10 09:00:00', 10),
        reserva('2026-07-11 09:00:00', 10, estado: 'cancelada'),
      ],
      liquidaciones: const [],
      estudio: estudio(),
      ahora: ahora,
    ).single;
    expect(fila['reservas'], 1);
  });

  test('EL MES ES EL DE LA CLASE (16/9): reservada el 31/8 para el 2/9 va a septiembre',
      () {
    final r = {
      'created_at': '2026-08-31T20:00:00Z',
      '_clase_fecha': '2026-09-02T00:30:00Z', // 1/9 21:30 ART
      'estado': 'completada',
      'creditos_usados': 18,
    };
    final filas = armarHistorialCobros(
      reservas: [r],
      liquidaciones: const [],
      estudio: {
        'comision_aura': 30,
        'valor_credito': 1000,
        'fecha_inicio_cobro': '2026-09-13', // Citra
      },
      ahora: DateTime(2026, 9, 16),
    );
    expect(filas.single['_mes'], '2026-09');
    expect(filas.single['monto'], 18000,
        reason: 'clase antes del 13/9: gracia, aunque hoy sea el 16/9');
    expect(filas.single['estado'], kEstadoEnCurso);
  });

  test('EL ASIENTO DE CORRECCIÓN (16/9): Citra ve \$54.000, no los \$37.800 de la fila',
      () {
    final liqCitraAgosto = {
      'mes': '2026-08',
      'estado': 'pagado',
      'monto_a_pagar': 37800,
      'monto_total_reservas': 54000,
      'cantidad_reservas': 3,
      'comision_aplicada': '30',
      'liquidaciones_correcciones': [
        {
          'diferencia': 16200,
          'comision_real': '0.00',
          'motivo': 'Bug de la gracia retroactiva',
          'created_at': '2026-09-16T18:00:00Z',
        },
      ],
    };
    final filas = armarHistorialCobros(
      reservas: const [],
      liquidaciones: [liqCitraAgosto],
      estudio: estudio(),
      ahora: DateTime(2026, 9, 16),
    );
    final agosto = filas.single;
    expect(agosto['monto'], 54000);
    expect(agosto['_sellado'], 54000, reason: 'el detalle usa el mismo total');
    expect(agosto['comision'], '0%');
    expect(agosto['estado'], kEstadoPagado);
    expect(agosto['_correccion'], contains('Corregido el 16/9'));
  });
}
