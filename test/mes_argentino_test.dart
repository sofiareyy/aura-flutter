// El corte de facturación: MES CALENDARIO ARGENTINO (confirmado 2/9/2026).
// Los dos casos de frontera son literalmente los que pidió la usuaria.
import 'package:aura_app/utils/mes_argentino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LA FRONTERA: 30/9 23:59 ART es SEPTIEMBRE', () {
    // 30/9 23:59 ART = 1/10 02:59 UTC — con el corte viejo (UTC) caía en
    // octubre. Este era el bug.
    final utc = DateTime.utc(2026, 10, 1, 2, 59);
    expect(mesArgentinoDe(utc), '2026-09');
  });

  test('LA FRONTERA: 1/10 00:01 ART es OCTUBRE', () {
    // 1/10 00:01 ART = 1/10 03:01 UTC.
    expect(mesArgentinoDe(DateTime.utc(2026, 10, 1, 3, 1)), '2026-10');
  });

  test('el medio del mes no se mueve (los datos reales de hoy)', () {
    // created_at reales de la base: 31/8 20:13 UTC (= 17:13 ART, agosto) y
    // 1/9 16:30 UTC (= 13:30 ART, septiembre). Con el arreglo quedan donde
    // estaban: ninguna liquidación existente cambia de mes.
    expect(mesArgentinoDe(DateTime.utc(2026, 8, 31, 20, 13)), '2026-08');
    expect(mesArgentinoDe(DateTime.utc(2026, 9, 1, 16, 30)), '2026-09');
  });

  test('los límites para la base: [00:00 ART, 00:00 ART) como instantes UTC',
      () {
    final l = limitesMesArgentino('2026-09');
    expect(l.inicioUtc, DateTime.utc(2026, 9, 1, 3));
    expect(l.finExclusivoUtc, DateTime.utc(2026, 10, 1, 3));
    // La grieta del sub-segundo, cerrada: 23:59:59.5 ART del 30/9 es
    // < finExclusivo → cae en septiembre, no en ningún limbo.
    final grieta = DateTime.utc(2026, 10, 1, 2, 59, 59, 500);
    expect(grieta.isBefore(l.finExclusivoUtc), isTrue);
    expect(mesArgentinoDe(grieta), '2026-09');
  });

  test('diciembre → enero cruza el año bien', () {
    expect(mesArgentinoDe(DateTime.utc(2027, 1, 1, 2, 59)), '2026-12');
    final l = limitesMesArgentino('2026-12');
    expect(l.finExclusivoUtc, DateTime.utc(2027, 1, 1, 3));
  });

  test('EL ESCENARIO DE SOFÍA: paga sept el 5/10 a la mañana, cae una reserva '
      'a las 17h — es de octubre, no se cuela', () {
    // 5/10 17:00 ART = 20:00 UTC.
    final reservaNueva = DateTime.utc(2026, 10, 5, 20);
    expect(mesArgentinoDe(reservaNueva), '2026-10');
    // Y ni siquiera entra en el rango con que se armó septiembre:
    final sept = limitesMesArgentino('2026-09');
    expect(reservaNueva.isBefore(sept.finExclusivoUtc), isFalse);
  });
}
