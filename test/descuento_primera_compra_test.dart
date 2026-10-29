import 'package:aura_app/services/pricing_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// La app y el servidor (crear-checkout-pack) tienen que dar el MISMO monto:
/// si no, la app muestra un precio y el servidor rechaza el pago. Estos son
/// los valores que da la función del servidor, medidos el 29/10/2026.
void main() {
  test('20% sobre los cuatro packs de hoy', () {
    expect(precioConDescuento(22000, 20), 17600);
    expect(precioConDescuento(50000, 20), 40000);
    expect(precioConDescuento(95000, 20), 76000);
    expect(precioConDescuento(180000, 20), 144000);
  });

  test('redondea al peso igual que el servidor', () {
    expect(precioConDescuento(12345, 20), 9876);
  });

  test('sin descuento, o con un porcentaje inválido, no toca el precio', () {
    expect(precioConDescuento(22000, 0), 22000);
    expect(precioConDescuento(22000, -5), 22000);
    expect(precioConDescuento(22000, 100), 22000);
  });
}
