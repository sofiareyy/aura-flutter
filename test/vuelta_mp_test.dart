import 'package:aura_app/utils/vuelta_mp.dart';
import 'package:flutter_test/flutter_test.dart';

// Vuelta de Mercado Pago (16/11/2026): MP agrega su propio `status`.
void main() {
  Map<String, List<String>> q(String query) =>
      Uri.parse('aura://payment-result?$query').queryParametersAll;

  test('rechazado: nuestro failure + el rejected de MP → failure', () {
    final p = q(
      'status=failure&pago_id=1&collection_status=rejected'
      '&status=rejected&payment_id=123',
    );
    expect(estadoDeVueltaMp(p), 'failure');
  });

  test('tocó volver en MP: todo null → failure, sin id', () {
    final p = q(
      'status=failure&pago_id=1&collection_id=null'
      '&collection_status=null&status=null&payment_id=null',
    );
    expect(estadoDeVueltaMp(p), 'failure');
    expect(idDePagoMp(p), isNull);
  });

  test('aprobado → se confirma, con el id real', () {
    final p = q(
      'status=success&pago_id=1&collection_id=999'
      '&collection_status=approved&status=approved&payment_id=999',
    );
    expect(estadoDeVueltaMp(p), 'success');
    expect(idDePagoMp(p), '999');
  });

  test('pendiente (efectivo) → pending', () {
    final p = q(
      'status=pending&pago_id=1&collection_status=pending'
      '&status=pending&payment_id=5',
    );
    expect(estadoDeVueltaMp(p), 'pending');
  });

  test('sin status → se confirma igual', () {
    expect(estadoDeVueltaMp(q('pago_id=1')), 'success');
  });
}
