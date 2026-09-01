// El historial de cobros que ve el estudio en su pantalla de Cobros.
//
// La regla (2/9/2026): la fila de `liquidaciones` SIEMPRE gana sobre el
// cálculo en vivo. Un mes pagado muestra los valores SELLADOS al momento del
// pago (monto_a_pagar, comision_aplicada) — si después Aura cambia una
// comisión, lo ya cobrado no se mueve. El cálculo en vivo queda sólo para los
// meses que todavía no tienen liquidación.
//
// Antes esta pantalla inventaba el estado: "si no es el mes actual, decí
// Pagado", sin mirar si Aura pagó. Los estados nuevos dicen la verdad y el
// momento (Aura paga el día 5 del mes siguiente):
//   · mes en curso                     -> 'En curso'      (todavía suma)
//   · mes cerrado sin liquidación      -> 'A cobrar el 5'
//   · liquidación en estado pendiente  -> 'A cobrar el 5'
//   · liquidación pagada               -> 'Pagado'
//
// Función pura a propósito: el test la corre con números reales de la base.

import 'package:intl/intl.dart';

import 'liquidacion.dart';

const kEstadoPagado = 'Pagado';
const kEstadoACobrar = 'A cobrar el 5';
const kEstadoEnCurso = 'En curso';

List<Map<String, dynamic>> armarHistorialCobros({
  required List<Map<String, dynamic>> reservas,
  required List<Map<String, dynamic>> liquidaciones,
  required Map<String, dynamic>? estudio,
  required DateTime ahora,
  int maxMeses = 4,
}) {
  final formatter = DateFormat('MMMM yyyy', 'es');
  final porMes = <String, Map<String, dynamic>>{};

  String claveDe(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  Map<String, dynamic> filaVacia(DateTime primerDia) => {
        'mes': toBeginningOfSentenceCase(formatter.format(primerDia)) ??
            formatter.format(primerDia),
        'reservas': 0,
        'monto': 0,
        '_date': primerDia,
        'comision': null,
      };

  // 1) El cálculo en vivo, agrupando reservas por mes (como siempre).
  for (final r in reservas) {
    final estado = r['estado']?.toString() ?? '';
    if (estado == 'cancelada') continue;
    final dt = DateTime.tryParse(r['created_at']?.toString() ?? '');
    if (dt == null) continue;
    final primerDia = DateTime(dt.year, dt.month, 1);
    final fila = porMes.putIfAbsent(claveDe(dt), () => filaVacia(primerDia));
    fila['reservas'] = (fila['reservas'] as int) + 1;
    fila['monto'] =
        (fila['monto'] as int) + Liquidacion.netoReserva(r, estudio);
  }

  // Estado de lo calculado: en curso o a cobrar, según si el mes cerró.
  final mesActual = claveDe(ahora);
  for (final e in porMes.entries) {
    e.value['estado'] =
        e.key == mesActual ? kEstadoEnCurso : kEstadoACobrar;
  }

  // 2) Las liquidaciones REALES pisan el cálculo de su mes.
  for (final l in liquidaciones) {
    final mes = l['mes']?.toString() ?? ''; // 'YYYY-MM'
    final partes = mes.split('-');
    if (partes.length != 2) continue;
    final anio = int.tryParse(partes[0]);
    final mesN = int.tryParse(partes[1]);
    if (anio == null || mesN == null) continue;
    final primerDia = DateTime(anio, mesN, 1);
    final fila = porMes.putIfAbsent(mes, () => filaVacia(primerDia));
    final pagada = l['estado']?.toString() == 'pagado';
    fila['reservas'] = (l['cantidad_reservas'] as num?)?.toInt() ?? 0;
    fila['monto'] = (l['monto_a_pagar'] as num?)?.toInt() ?? 0;
    fila['estado'] = pagada ? kEstadoPagado : kEstadoACobrar;
    // La comisión SELLADA, para mostrarla junto al mes pagado. Es la
    // constancia de con qué porcentaje se cobró, aunque hoy rija otro.
    if (pagada && l['comision_aplicada'] != null) {
      final c = double.tryParse(l['comision_aplicada'].toString());
      if (c != null) {
        fila['comision'] = c.truncateToDouble() == c
            ? '${c.toInt()}%'
            : '${c.toStringAsFixed(1)}%';
      }
    }
  }

  final filas = porMes.values.toList()
    ..sort((a, b) => (b['_date'] as DateTime).compareTo(a['_date'] as DateTime));
  return filas.take(maxMeses).toList();
}
