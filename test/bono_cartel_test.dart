import 'package:aura_app/utils/bono_cartel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final hoy = DateTime(2026, 9, 14, 10);

  Map<String, dynamic> bono({
    int restante = 16,
    String? vence = '2026-11-13',
    bool vencido = false,
  }) =>
      {
        'tiene': true,
        'monto': 16,
        'restante': restante,
        'vence_el': vence,
        'vencido': vencido,
      };

  group('cuándo SÍ se muestra el cartel', () {
    test('tiene créditos sin usar y no venció', () {
      final c = BonoCartel.leer(bono(), hoy: hoy);
      expect(c, isNotNull);
      expect(c!.restante, 16);
      expect(c.venceEl, DateTime(2026, 11, 13));
    });

    test('lo usó a medias: se muestra por lo que queda', () {
      final c = BonoCartel.leer(bono(restante: 5), hoy: hoy);
      expect(c!.restante, 5);
    });

    test('sin fecha de vencimiento igual se muestra', () {
      final c = BonoCartel.leer(bono(vence: null), hoy: hoy);
      expect(c, isNotNull);
      expect(c!.venceEl, isNull);
    });

    test('el último día todavía cuenta', () {
      // Vence hoy: hasta las 23:59 sigue siendo usable.
      final c = BonoCartel.leer(bono(vence: '2026-09-14'), hoy: hoy);
      expect(c, isNotNull);
    });
  });

  group('cuándo NO', () {
    test('no tiene bono', () {
      expect(BonoCartel.leer({'tiene': false}, hoy: hoy), isNull);
    });

    test('ya lo gastó entero', () {
      expect(BonoCartel.leer(bono(restante: 0), hoy: hoy), isNull);
    });

    test('la base dice que venció', () {
      expect(BonoCartel.leer(bono(vencido: true), hoy: hoy), isNull);
    });

    test('la fecha ya pasó, aunque la bandera diga que no', () {
      // Defensa contra un reloj desfasado: mandan las dos señales.
      expect(BonoCartel.leer(bono(vence: '2026-09-13'), hoy: hoy), isNull);
    });
  });

  group('respuestas raras no rompen nada', () {
    test('null', () => expect(BonoCartel.leer(null, hoy: hoy), isNull));
    test('un string', () => expect(BonoCartel.leer('error', hoy: hoy), isNull));
    test('mapa vacío', () => expect(BonoCartel.leer({}, hoy: hoy), isNull));
    test('restante ausente', () {
      expect(BonoCartel.leer({'tiene': true}, hoy: hoy), isNull);
    });
    test('fecha ilegible: se muestra igual', () {
      final c = BonoCartel.leer(bono(vence: 'no-es-fecha'), hoy: hoy);
      expect(c, isNotNull);
      expect(c!.venceEl, isNull);
    });
  });
}
