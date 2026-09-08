// El rango de clases de cada pack (9/9/2026).
//
// Los precios son los REALES de producción: las clases futuras van de 11 a 18
// créditos. Los packs, 20 / 50 / 100 / 200.
import 'package:aura_app/utils/rango_clases_pack.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lo que hay cargado hoy: 11, 13, 14 y 18 créditos.
const preciosReales = [11, 13, 14, 18];

String? r(int cr) =>
    rangoDeClases(creditosDelPack: cr, preciosDeClase: preciosReales);

void main() {
  group('con la oferta real de hoy', () {
    test('Pack Prueba (20 cr) — para probar una clase', () {
      // 20 ÷ 18 = 1 y 20 ÷ 11 = 1: da exactamente una, y se dice cálido.
      expect(r(20), 'Para probar una clase');
    });

    test('Pack Esencial (50 cr) — entre 2 y 4', () {
      expect(r(50), 'Entre 2 y 4 clases');
    });

    test('Pack Popular (100 cr) — entre 5 y 9', () {
      expect(r(100), 'Entre 5 y 9 clases');
    });

    test('Pack Full (200 cr) — entre 11 y 18', () {
      expect(r(200), 'Entre 11 y 18 clases');
    });
  });

  group('se ajusta solo si cambian los precios', () {
    test('si entra un estudio más caro, el piso baja', () {
      // Un estudio de 25 créditos: el Esencial pasa de "2 a 4" a "2 a 4"...
      final con25 = rangoDeClases(
        creditosDelPack: 50,
        preciosDeClase: [11, 18, 25],
      );
      expect(con25, 'Entre 2 y 4 clases');
      // ...pero el Pack Prueba deja de alcanzar para la cara.
      expect(
        rangoDeClases(creditosDelPack: 20, preciosDeClase: [11, 18, 25]),
        'Para probar una clase',
      );
    });

    test('si todas valen lo mismo, no inventa un rango', () {
      expect(
        rangoDeClases(creditosDelPack: 100, preciosDeClase: [20, 20]),
        '5 clases',
      );
    });
  });

  group('no promete lo que no puede cumplir', () {
    test('si con la más cara no llega, dice "hasta"', () {
      // 30 créditos: con la de 18 da 1, con la de 11 da 2. No promete 2.
      expect(
        rangoDeClases(creditosDelPack: 30, preciosDeClase: [11, 18]),
        'Entre 1 y 2 clases',
      );
      // 20 créditos contra clases de 25 y 11: con la cara no alcanza.
      expect(
        rangoDeClases(creditosDelPack: 20, preciosDeClase: [11, 25]),
        'Para probar una clase',
      );
    });

    test('si no alcanza para ninguna, no dice nada', () {
      expect(rangoDeClases(creditosDelPack: 5, preciosDeClase: [11, 18]), isNull);
    });

    test('sin precios cargados, no inventa', () {
      expect(rangoDeClases(creditosDelPack: 50, preciosDeClase: []), isNull);
      expect(rangoDeClases(creditosDelPack: 50, preciosDeClase: [0]), isNull);
    });
  });
}
