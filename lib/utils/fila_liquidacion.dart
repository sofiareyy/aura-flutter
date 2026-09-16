// Una fila del backoffice de Liquidaciones: qué le debe Aura a un estudio por
// un mes, o qué le pagó.
//
// La regla (16/9/2026), la misma que ya tenía la pantalla de Cobros del
// estudio: si la liquidación está PAGADA, la fila muestra lo SELLADO
// (`monto_a_pagar`, `comision_aplicada`) y no recalcula nada. Antes el
// backoffice recalculaba en vivo hasta los meses pagados, así que si cambiaba
// una comisión o terminaba una gracia, Aura y el estudio veían números
// distintos del mismo mes ya cerrado.
//
// Función pura a propósito: el test la corre con los números reales de Citra.

import 'liquidacion.dart';
import '../services/valor_credito.dart';

Map<String, dynamic> filaLiquidacion({
  required int estudioId,
  required String nombre,
  required String mes,
  required List<Map<String, dynamic>> reservas,
  required Map<String, dynamic>? estudio,
  Map<String, dynamic>? liquidacion,
}) {
  final pagada = liquidacion?['estado']?.toString() == 'pagado';

  if (pagada) {
    final total =
        (liquidacion!['monto_total_reservas'] as num?)?.toInt() ?? 0;
    // Lo EFECTIVAMENTE pagado: la fila más sus asientos de corrección. La
    // fila no se toca nunca; si se pagó otra cosa, hay un asiento con motivo.
    final pagar = Liquidacion.montoPagadoEfectivo(liquidacion);
    final sellada = Liquidacion.comisionEfectivaSellada(liquidacion);
    final correcciones = Liquidacion.correccionesDe(liquidacion);
    return {
      'estudio_id': estudioId,
      'nombre': nombre,
      'mes': mes,
      'cantidad_reservas':
          (liquidacion['cantidad_reservas'] as num?)?.toInt() ?? 0,
      'monto_total': total,
      'monto_pagar': pagar,
      // La constancia manda; si una fila vieja no la tiene, se deriva de
      // los montos sellados (nunca de la comisión de hoy).
      'comision_pct': sellada ??
          (total > 0 ? (total - pagar) / total * 100 : 0.0),
      'estado': 'pagado',
      'fecha_pago': liquidacion['fecha_pago'],
      'comprobante_nota': liquidacion['comprobante_nota'],
      'liquidacion_id': liquidacion['id'],
      'sellada': true,
      'correcciones': correcciones.length,
      if (correcciones.isNotEmpty)
        'correccion_motivo': correcciones.last['motivo']?.toString(),
    };
  }

  // Cálculo en vivo: reserva por reserva, con la gracia decidida por la
  // fecha de cada clase (Liquidacion.netoReserva).
  var montoPagar = 0;
  var montoTotal = 0;
  for (final r in reservas) {
    final cred = (r['creditos_usados'] as num?)?.toInt() ?? 0;
    montoPagar += Liquidacion.netoReserva(r, estudio);
    montoTotal += cred * ValorCredito.deEstudio(estudio);
  }
  // Comisión efectiva derivada de los montos reales (promedio ponderado
  // para meses mixtos de gracia y para clases + workshops).
  final comisionPct = montoTotal > 0
      ? (montoTotal - montoPagar) / montoTotal * 100
      : Liquidacion.comision(estudio, esWorkshop: false);

  return {
    'estudio_id': estudioId,
    'nombre': nombre,
    'mes': mes,
    'cantidad_reservas': reservas.length,
    'monto_total': montoTotal,
    'monto_pagar': montoPagar,
    'comision_pct': comisionPct,
    'estado': liquidacion?['estado'] ?? 'pendiente',
    'fecha_pago': liquidacion?['fecha_pago'],
    'comprobante_nota': liquidacion?['comprobante_nota'],
    'liquidacion_id': liquidacion?['id'],
    'sellada': false,
  };
}
