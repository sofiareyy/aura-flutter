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
import 'mes_argentino.dart';

const kEstadoPagado = 'Pagado';

String _fechaCorta(Object? iso) {
  final d = DateTime.tryParse(iso?.toString() ?? '');
  if (d == null) return '';
  final art = d.toUtc().subtract(const Duration(hours: 3));
  return '${art.day}/${art.month}';
}
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


  Map<String, dynamic> filaVacia(DateTime primerDia) => {
        'mes': toBeginningOfSentenceCase(formatter.format(primerDia)) ??
            formatter.format(primerDia),
        'reservas': 0,
        'monto': 0,
        '_date': primerDia,
        'comision': null,
        // Para poder abrir el detalle de ESTE mes desde la fila.
        '_mes': '${primerDia.year}-${primerDia.month.toString().padLeft(2, '0')}',
        '_sellado': null,
      };

  // 1) El cálculo en vivo, agrupando reservas por mes.
  for (final r in reservas) {
    final estado = r['estado']?.toString() ?? '';
    if (estado == 'cancelada') continue;
    // El mes es el de la CLASE, no el de la reserva (16/9/2026): es el mismo
    // criterio con el que se decide la gracia, y que los dos usen fechas
    // distintas es pedir otro bug. `created_at` queda sólo como respaldo si
    // la reserva llegó sin la fecha de la clase adjunta.
    final dt = Liquidacion.fechaDeClase(r) ??
        DateTime.tryParse(r['created_at']?.toString() ?? '');
    if (dt == null) continue;
    // Corte por MES CALENDARIO ARGENTINO (2/9): la fecha llega en UTC y
    // agrupar por su mes corría al mes siguiente lo de 21:00 a 23:59 del
    // último día.
    final mesArg = mesArgentinoDe(dt);
    final fila =
        porMes.putIfAbsent(mesArg, () => filaVacia(primerDiaDe(mesArg)));
    fila['reservas'] = (fila['reservas'] as int) + 1;
    fila['monto'] =
        (fila['monto'] as int) + Liquidacion.netoReserva(r, estudio);
  }

  // Estado de lo calculado: en curso o a cobrar, según si el mes cerró.
  final mesActual = mesArgentinoDe(ahora);
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
    // Lo EFECTIVAMENTE pagado: la fila más sus asientos de corrección
    // (16/9). Agosto de Citra: la fila dice $37.800 por el bug de la gracia,
    // el asiento dice que se transfirieron $54.000, y eso es lo que se ve.
    final monto = pagada
        ? Liquidacion.montoPagadoEfectivo(l)
        : (l['monto_a_pagar'] as num?)?.toInt() ?? 0;
    fila['monto'] = monto;
    fila['estado'] = pagada ? kEstadoPagado : kEstadoACobrar;
    // La comisión SELLADA (o la del último asiento), para mostrarla junto al
    // mes pagado. Es la constancia de con qué porcentaje se cobró, aunque hoy
    // rija otro. El monto viaja aparte: el detalle lo usa como total para no
    // mostrar un número distinto del que dice esta fila.
    if (pagada) fila['_sellado'] = monto;
    final c = pagada ? Liquidacion.comisionEfectivaSellada(l) : null;
    if (c != null) {
      fila['comision'] = c.truncateToDouble() == c
          ? '${c.toInt()}%'
          : '${c.toStringAsFixed(1)}%';
    }
    // Y la nota, para que el estudio sepa que hubo un asiento y por qué.
    final correcciones = pagada ? Liquidacion.correccionesDe(l) : const [];
    if (correcciones.isNotEmpty) {
      final ultima = correcciones.last;
      fila['_correccion'] =
          'Corregido el ${_fechaCorta(ultima['created_at'])}: '
          '${ultima['motivo'] ?? ''}';
    }
  }

  final filas = porMes.values.toList()
    ..sort((a, b) => (b['_date'] as DateTime).compareTo(a['_date'] as DateTime));
  return filas.take(maxMeses).toList();
}
