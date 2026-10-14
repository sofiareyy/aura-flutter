// El precio de un workshop se arma con la comisión DE LA FECHA DEL EVENTO
// (14/10/2026).
//
// El agujero: `creditosDeWorkshop` ya aceptaba `fecha`, pero el formulario la
// llamaba sin pasarla, así que usaba la comisión de HOY. Y para un workshop
// ese valor es el que QUEDA GUARDADO: el trigger `clases_fija_precio` se
// abstiene con los workshops, a diferencia de las clases normales.
//
// Resultado: un estudio todavía en gracia que cargaba un workshop para
// después de su `fecha_inicio_cobro` lo guardaba sin comisión y terminaba
// recibiendo ~15% menos de lo que tipeó. Es el mismo error que la liquidación
// ya tenía cerrado desde el 16/9, repetido en el formulario.
//
// Al 14/10 hay 11 estudios en gracia y 0 workshops futuros: estaba dormido,
// pero el primero que se cargara lo despertaba.

import 'package:aura_app/utils/liquidacion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Un estudio en gracia hasta fin de noviembre, con los números que usa la
  // base: comisión de workshop 15%, crédito a $1.000.
  final enGracia = <String, dynamic>{
    'comision_aura': 30,
    'comision_workshop': 15,
    'valor_credito': 1000,
    'fecha_inicio_cobro': '2026-11-30',
  };

  test('un workshop DENTRO de la gracia no carga comisión', () {
    // Quiere recibir $100.000 y no hay comisión: 100 créditos.
    expect(
      Liquidacion.creditosDeWorkshop(
        100000,
        enGracia,
        fecha: DateTime(2026, 11, 1),
      ),
      100,
    );
  });

  test('el MISMO workshop después de la gracia sí la carga', () {
    // $100.000 / 0,85 = $117.647 → 118 créditos, para que al estudio le
    // queden sus $100.000 después de que Aura cobre el 15%.
    expect(
      Liquidacion.creditosDeWorkshop(
        100000,
        enGracia,
        fecha: DateTime(2026, 12, 1),
      ),
      118,
    );
  });

  test('la fecha cambia el precio: por eso hay que pasarla', () {
    // Si este test deja de distinguir, es que `fecha` dejó de importar y el
    // arreglo del formulario perdió sentido.
    final dentro = Liquidacion.creditosDeWorkshop(
      100000,
      enGracia,
      fecha: DateTime(2026, 11, 1),
    );
    final fuera = Liquidacion.creditosDeWorkshop(
      100000,
      enGracia,
      fecha: DateTime(2026, 12, 1),
    );
    expect(dentro, lessThan(fuera));
  });

  test('ida y vuelta: el estudio recibe lo que pidió', () {
    // La razón de ser de la fórmula. Con la comisión aplicada, convertir a
    // créditos y volver a pesos tiene que devolver el monto original.
    final fecha = DateTime(2026, 12, 1);
    final creditos = Liquidacion.creditosDeWorkshop(
      100000,
      enGracia,
      fecha: fecha,
    );
    final vuelta = Liquidacion.montoEstudioDeWorkshop(
      creditos,
      enGracia,
      fecha: fecha,
    );
    expect((vuelta - 100000).abs(), lessThan(1000));
  });

  test('un estudio sin fecha de cobro cobra comisión siempre', () {
    // Sin `fecha_inicio_cobro` no hay gracia que respetar.
    final sinGracia = <String, dynamic>{
      'comision_workshop': 15,
      'valor_credito': 1000,
    };
    expect(
      Liquidacion.creditosDeWorkshop(
        100000,
        sinGracia,
        fecha: DateTime(2026, 11, 1),
      ),
      118,
    );
  });
}
