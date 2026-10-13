// Los números de "Reservas del mes" (13/10/2026).
//
// El bug: los tres contadores se calculaban sobre la lista entera, canceladas
// incluidas. La pantalla podía decir "12 reservas · 96 créditos" contando
// plata ya devuelta, y abajo mostrar esas mismas filas con el cartelito
// "Cancelada". Los números y la lista se contradecían a la vista.

import 'package:aura_app/core/constants/app_constants.dart';
import 'package:aura_app/utils/resumen_reservas_mes.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> reserva({
  required String estado,
  int creditos = 8,
  bool presente = false,
}) => {
  'estado': estado,
  'creditos_usados': creditos,
  'checked_in_at': presente ? '2026-10-03T12:00:00Z' : null,
};

void main() {
  test('una cancelada no suma reservas ni créditos, y se cuenta aparte', () {
    final r = resumirReservasDelMes([
      reserva(estado: 'completada', creditos: 8, presente: true),
      reserva(estado: 'cancelada', creditos: 8),
    ]);
    expect(r.reservas, 1);
    expect(r.creditos, 8);
    expect(r.presentes, 1);
    expect(r.canceladas, 1);
  });

  test('`cancelada_por_estudio` también es cancelada', () {
    // Las dos devuelven créditos. La escribe el servidor cuando el estudio
    // baja una clase, y en producción todavía no hay filas así.
    expect(esCancelada('cancelada_por_estudio'), isTrue);
    final r = resumirReservasDelMes([reserva(estado: 'cancelada_por_estudio')]);
    expect(r.reservas, 0);
    expect(r.creditos, 0);
    expect(r.canceladas, 1);
  });

  test('cuenta los mismos estados que Cobros y el Dashboard', () {
    // Si alguien agrega un estado liquidable, este test lo trae solo: el
    // criterio no se escribe dos veces.
    final filas = AppConstants.estadosLiquidables
        .map((e) => reserva(estado: e, creditos: 2))
        .toList();
    final r = resumirReservasDelMes(filas);
    expect(r.reservas, AppConstants.estadosLiquidables.length);
    expect(r.creditos, AppConstants.estadosLiquidables.length * 2);
    expect(r.canceladas, 0);
  });

  test('`pre_confirmada` no entra en ningún número', () {
    // Todavía no consumió crédito ni ocupa lugar firme. Aparece en la lista,
    // pero contarla como reserva sería prometer algo que no pasó.
    final r = resumirReservasDelMes([reserva(estado: 'pre_confirmada')]);
    expect(r.reservas, 0);
    expect(r.creditos, 0);
    expect(r.canceladas, 0);
  });

  test('presentes cuenta el check-in, no el estado', () {
    // 'completada' lo pone el cron cuando termina la clase, le hayan marcado
    // el presente o no: el cron no sabe si la persona fue.
    final r = resumirReservasDelMes([
      reserva(estado: 'completada', presente: true),
      reserva(estado: 'completada'),
    ]);
    expect(r.reservas, 2);
    expect(r.presentes, 1);
  });

  test('una fila sin créditos ni estado no rompe nada', () {
    final r = resumirReservasDelMes([
      {'estado': 'confirmada'},
      <String, dynamic>{},
    ]);
    expect(r.reservas, 1);
    expect(r.creditos, 0);
  });

  test('un mes vacío da todo en cero', () {
    final r = resumirReservasDelMes(const []);
    expect(r.reservas, 0);
    expect(r.presentes, 0);
    expect(r.creditos, 0);
    expect(r.canceladas, 0);
  });
}
