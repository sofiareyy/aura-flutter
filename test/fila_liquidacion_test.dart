// La fila del backoffice de Liquidaciones. Números reales de Citra Barre al
// 16/9/2026: gracia hasta el 13/9, 30%, crédito a $1.000, clases de 18.
import 'package:aura_app/utils/fila_liquidacion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final citra = <String, dynamic>{
    'id': 4,
    'nombre': 'Citra Barre',
    'comision_aura': 30,
    'comision_workshop': 15,
    'valor_credito': 1000,
    'fecha_inicio_cobro': '2026-09-13',
  };

  Map<String, dynamic> reserva(String claseUtc) => {
        'estado': 'completada',
        'creditos_usados': 18,
        '_clase_tipo': 'clase',
        '_clase_fecha': claseUtc,
      };

  // La liquidación REAL de agosto, pagada el 16/9 y sellada al 30% por el
  // bug: $37.800 en vez de $54.000.
  final agostoSellado = {
    'id': 'b9261732-e3a6-4f89-93bc-1f32c3be07a8',
    'estado': 'pagado',
    'monto_total_reservas': 54000,
    'monto_a_pagar': 37800,
    'cantidad_reservas': 3,
    'comision_aplicada': '30',
    'fecha_pago': '2026-09-16T15:27:32.66+00:00',
  };

  test('un mes PAGADO muestra lo sellado, aunque el recálculo diga otra cosa',
      () {
    // Con la gracia por fecha de clase, el recálculo en vivo daría $54.000.
    // Pero se pagó $37.800 y eso es lo que tiene que decir el backoffice.
    final fila = filaLiquidacion(
      estudioId: 4,
      nombre: 'Citra Barre',
      mes: '2026-08',
      reservas: [
        reserva('2026-08-20T00:00:00Z'),
        reserva('2026-08-26T00:30:00Z'),
        reserva('2026-08-27T14:00:00Z'),
      ],
      estudio: citra,
      liquidacion: agostoSellado,
    );
    expect(fila['monto_pagar'], 37800);
    expect(fila['monto_total'], 54000);
    expect(fila['cantidad_reservas'], 3);
    expect(fila['comision_pct'], 30.0);
    expect(fila['estado'], 'pagado');
    expect(fila['sellada'], isTrue);
  });

  test('sin liquidación se calcula en vivo, con la gracia por clase', () {
    final fila = filaLiquidacion(
      estudioId: 4,
      nombre: 'Citra Barre',
      mes: '2026-09',
      reservas: [reserva('2026-09-02T00:30:00Z')], // res 712: antes del 13/9
      estudio: citra,
    );
    expect(fila['monto_pagar'], 18000, reason: 'no \$12.600');
    expect(fila['monto_total'], 18000);
    expect(fila['comision_pct'], 0.0);
    expect(fila['estado'], 'pendiente');
    expect(fila['sellada'], isFalse);
  });

  test('un mes mixto da la comisión efectiva ponderada', () {
    final fila = filaLiquidacion(
      estudioId: 4,
      nombre: 'Citra Barre',
      mes: '2026-09',
      reservas: [
        reserva('2026-09-02T00:30:00Z'), // 100%
        reserva('2026-09-20T21:00:00Z'), // 70%
      ],
      estudio: citra,
    );
    expect(fila['monto_pagar'], 30600);
    expect(fila['comision_pct'], closeTo(15.0, 0.01));
  });

  test('una fila pagada vieja sin constancia deriva el % de sus montos', () {
    final fila = filaLiquidacion(
      estudioId: 3,
      nombre: 'Hot Clic',
      mes: '2026-08',
      reservas: const [],
      estudio: citra,
      liquidacion: {
        'id': 'x',
        'estado': 'pagado',
        'monto_total_reservas': 12000,
        'monto_a_pagar': 8400,
        'cantidad_reservas': 1,
        'comision_aplicada': null,
      },
    );
    expect(fila['monto_pagar'], 8400);
    expect(fila['comision_pct'], closeTo(30.0, 0.01));
  });

  test('una liquidación PENDIENTE no manda: se recalcula', () {
    final fila = filaLiquidacion(
      estudioId: 4,
      nombre: 'Citra Barre',
      mes: '2026-09',
      reservas: [reserva('2026-09-02T00:30:00Z')],
      estudio: citra,
      liquidacion: {'id': 'y', 'estado': 'pendiente', 'monto_a_pagar': 1},
    );
    expect(fila['monto_pagar'], 18000);
    expect(fila['estado'], 'pendiente');
  });

  test('un ASIENTO DE CORRECCIÓN suma sobre lo sellado, sin tocar la fila', () {
    // El asiento real del 16/9: la fila dice $37.800, se transfirieron $54.000.
    final fila = filaLiquidacion(
      estudioId: 4,
      nombre: 'Citra Barre',
      mes: '2026-08',
      reservas: const [],
      estudio: citra,
      liquidacion: {
        ...agostoSellado,
        'liquidaciones_correcciones': [
          {
            'monto_registrado': 37800,
            'monto_real': 54000,
            'diferencia': 16200,
            'comision_registrada': '30.00',
            'comision_real': '0.00',
            'motivo': 'Bug de la gracia retroactiva',
            'created_at': '2026-09-16T18:00:00Z',
          },
        ],
      },
    );
    expect(fila['monto_pagar'], 54000, reason: 'lo efectivamente pagado');
    expect(fila['comision_pct'], 0.0, reason: 'la del asiento, no la sellada');
    expect(fila['correcciones'], 1);
    expect(fila['correccion_motivo'], contains('gracia'));
    expect(fila['estado'], 'pagado');
  });
}
