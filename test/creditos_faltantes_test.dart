// Lo que se le dice a alguien cuando no le alcanzan los créditos, en los tres
// lugares donde pasa. La propiedad que se cuida: NUNCA un número negativo.
import 'package:aura_app/utils/creditos_faltantes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cuánto falta', () {
    test('lo que falta se dice en positivo', () {
      expect(creditosFaltantes(saldo: 0, precio: 8), 8);
      expect(creditosFaltantes(saldo: 2, precio: 10), 8);
    });

    test('si alcanza, no falta nada (nunca negativo)', () {
      expect(creditosFaltantes(saldo: 10, precio: 10), 0);
      expect(creditosFaltantes(saldo: 50, precio: 10), 0);
      expect(alcanzaElSaldo(saldo: 10, precio: 10), isTrue);
      expect(alcanzaElSaldo(saldo: 9, precio: 10), isFalse);
    });

    test('una clase gratis le alcanza a cualquiera', () {
      expect(creditosFaltantes(saldo: 0, precio: 0), 0);
      expect(alcanzaElSaldo(saldo: 0, precio: 0), isTrue);
    });
  });

  group('el renglón de saldo del detalle', () {
    test('EL BUG: ya no puede decir "Quedan -8"', () {
      expect(textoSaldoTrasReservar(saldo: 0, precio: 8),
          'Te faltan 8 créditos');
      expect(textoSaldoTrasReservar(saldo: 2, precio: 10),
          'Te faltan 8 créditos');
      for (var saldo = 0; saldo <= 30; saldo++) {
        for (var precio = 0; precio <= 30; precio++) {
          expect(textoSaldoTrasReservar(saldo: saldo, precio: precio),
              isNot(contains('-')),
              reason: 'saldo $saldo, precio $precio');
        }
      }
    });

    test('si alcanza, sigue diciendo cuánto queda', () {
      expect(textoSaldoTrasReservar(saldo: 20, precio: 8),
          'Quedan 12 tras reservar');
      expect(textoSaldoTrasReservar(saldo: 8, precio: 8),
          'Quedan 0 tras reservar');
    });

    test('singular', () {
      expect(textoSaldoTrasReservar(saldo: 0, precio: 1), 'Te faltan 1 crédito');
    });
  });

  group('el paywall le habla distinto a quien es nueva', () {
    test('sin créditos: le explica el modelo de Aura', () {
      expect(tituloPaywall(saldo: 0, precio: 10),
          'Necesitás créditos para reservar');
      final m = mensajePaywall(saldo: 0, precio: 10);
      expect(m, contains('Esta clase cuesta 10 créditos'));
      expect(m, contains('comprás un pack'));
      expect(m, contains('cualquier estudio'));
      expect(m, contains('sin cuota mensual'));
    });

    test('con créditos: va al número que le falta', () {
      expect(tituloPaywall(saldo: 2, precio: 10), 'Te faltan 8 créditos');
      expect(mensajePaywall(saldo: 2, precio: 10),
          'Esta clase cuesta 10 créditos y tenés 2. Comprá un pack y reservá al toque.');
    });

    test('ningún texto del paywall muestra un negativo', () {
      for (var saldo = 0; saldo <= 20; saldo++) {
        for (var precio = 0; precio <= 20; precio++) {
          expect(tituloPaywall(saldo: saldo, precio: precio),
              isNot(contains('-')));
          expect(mensajePaywall(saldo: saldo, precio: precio),
              isNot(contains('-')));
        }
      }
    });
  });

  group('el aviso de confirmar reserva', () {
    test('sin créditos: dice cuánto necesita y que vuelve', () {
      final a = avisoConfirmarReserva(saldo: 0, precio: 10);
      expect(a, contains('Necesitás 10 créditos'));
      expect(a, contains('volvés acá'));
    });

    test('con créditos: dice cuánto falta', () {
      expect(avisoConfirmarReserva(saldo: 2, precio: 10),
          'Te faltan 8 créditos para esta reserva.');
    });

    test('si alcanza no hay aviso', () {
      expect(avisoConfirmarReserva(saldo: 10, precio: 10), '');
    });

    test('nunca un negativo', () {
      for (var saldo = 0; saldo <= 20; saldo++) {
        for (var precio = 0; precio <= 20; precio++) {
          expect(avisoConfirmarReserva(saldo: saldo, precio: precio),
              isNot(contains('-')));
        }
      }
    });
  });
}
