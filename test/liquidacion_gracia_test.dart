// La gracia se decide con la FECHA DE LA CLASE, no con hoy ni con la fecha
// del pago. Números reales de la base al 16/9/2026: Citra Barre, gracia
// hasta el 13/9, comisión 30%, crédito a $1.000, clases de 18 créditos.
import 'package:aura_app/utils/liquidacion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final citra = <String, dynamic>{
    'comision_aura': 30,
    'comision_workshop': 15,
    'valor_credito': 1000,
    'fecha_inicio_cobro': '2026-09-13',
  };

  Map<String, dynamic> reserva(String claseUtc, {int creditos = 18}) => {
        'estado': 'completada',
        'creditos_usados': creditos,
        '_clase_tipo': 'clase',
        '_clase_fecha': claseUtc,
      };

  group('EL BUG DEL 16/9: la gracia no se aplica hacia atrás', () {
    test('la clase del 1/9 vale \$18.000 aunque hoy sea después del 13/9', () {
      // res 712 real: la que en el backoffice figuraba con $12.600.
      expect(Liquidacion.netoReserva(reserva('2026-09-02T00:30:00Z'), citra),
          18000);
    });

    test('las tres de agosto (411, 552, 673) suman \$54.000, no \$37.800', () {
      final agosto = [
        reserva('2026-08-20T00:00:00Z'),
        reserva('2026-08-26T00:30:00Z'),
        reserva('2026-08-27T14:00:00Z'),
      ];
      expect(Liquidacion.netoTotal(agosto, citra), 54000);
    });

    test('una clase del 13/9 ya paga el 30%: \$12.600', () {
      expect(Liquidacion.netoReserva(reserva('2026-09-13T21:00:00Z'), citra),
          12600);
    });
  });

  group('el corte es el DÍA ARGENTINO de la clase', () {
    test('12/9 a las 23:30 ART (= 13/9 02:30 UTC) sigue en gracia', () {
      expect(Liquidacion.cobraComision(citra,
              fecha: DateTime.parse('2026-09-13T02:30:00Z')),
          isFalse);
    });

    test('13/9 a las 00:30 ART (= 03:30 UTC) ya cobra', () {
      expect(Liquidacion.cobraComision(citra,
              fecha: DateTime.parse('2026-09-13T03:30:00Z')),
          isTrue);
    });

    test('el mismo día de inicio cobra (>=, no >)', () {
      expect(Liquidacion.cobraComision(citra,
              fecha: DateTime.parse('2026-09-13T15:00:00Z')),
          isTrue);
    });
  });

  group('un mes mixto se liquida reserva por reserva', () {
    test('septiembre de Citra: una antes y una después del 13/9', () {
      final sept = [
        reserva('2026-09-02T00:30:00Z'), // 100%
        reserva('2026-09-20T21:00:00Z'), // 70%
      ];
      expect(Liquidacion.netoTotal(sept, citra), 18000 + 12600);
    });
  });

  group('sin fecha de clase cae a hoy (sólo vistas previas)', () {
    test('sin gracia configurada siempre cobra', () {
      expect(Liquidacion.cobraComision({'fecha_inicio_cobro': null}), isTrue);
      expect(Liquidacion.cobraComision({'fecha_inicio_cobro': ''}), isTrue);
      expect(Liquidacion.cobraComision({'fecha_inicio_cobro': 'basura'}),
          isTrue);
    });

    test('gracia en el futuro lejano: hoy no cobra', () {
      expect(
          Liquidacion.cobraComision({'fecha_inicio_cobro': '2099-01-01'}),
          isFalse);
    });

    test('una reserva sin _clase_fecha usa hoy (comportamiento de respaldo)', () {
      final r = reserva('x')..remove('_clase_fecha');
      // Gracia vencida hace rato: cobra.
      expect(Liquidacion.netoReserva(r, {...citra, 'fecha_inicio_cobro': '2020-01-01'}),
          12600);
    });
  });

  test('los workshops respetan la gracia igual', () {
    final ws = reserva('2026-09-02T00:30:00Z')..['_clase_tipo'] = 'workshop';
    expect(Liquidacion.netoReserva(ws, citra), 18000);
    final wsDespues = reserva('2026-09-20T21:00:00Z')
      ..['_clase_tipo'] = 'workshop';
    expect(Liquidacion.netoReserva(wsDespues, citra), 15300); // 15%
  });
}
