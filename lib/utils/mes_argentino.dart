// El mes CALENDARIO ARGENTINO de un instante. Es el corte de facturación
// confirmado el 2/9/2026: una reserva del 30/9 23:59 (hora argentina) es de
// septiembre; una del 1/10 00:01, de octubre.
//
// Antes el corte era medianoche UTC: las reservas de 21:00 a 23:59 del último
// día del mes caían en el mes siguiente. Argentina no tiene horario de
// verano, así que el offset fijo -3 es correcto (mismo criterio que
// clases_service y el resto del código).

const _offsetArgentina = Duration(hours: 3);

/// 'YYYY-MM' del instante, en calendario argentino.
String mesArgentinoDe(DateTime instante) {
  final art = instante.toUtc().subtract(_offsetArgentina);
  return '${art.year}-${art.month.toString().padLeft(2, '0')}';
}

/// El primer día del mes 'YYYY-MM' para etiquetas.
DateTime primerDiaDe(String mes) {
  final p = mes.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), 1);
}

/// Los límites del mes argentino como instantes UTC, para filtrar
/// `created_at` en la base: [inicio, finExclusivo). El fin EXCLUSIVO cierra
/// la grieta del `lte 23:59:59`, donde una reserva de las 23:59:59.5 no caía
/// en ningún mes.
({DateTime inicioUtc, DateTime finExclusivoUtc}) limitesMesArgentino(
    String mes) {
  final p = mes.split('-');
  final y = int.parse(p[0]);
  final m = int.parse(p[1]);
  // 00:00 ART = 03:00 UTC del mismo día.
  return (
    inicioUtc: DateTime.utc(y, m, 1).add(_offsetArgentina),
    finExclusivoUtc: DateTime.utc(y, m + 1, 1).add(_offsetArgentina),
  );
}

/// El DÍA calendario argentino de un instante, como 'YYYY-MM-DD'.
///
/// Se usa como semilla de lo que tiene que rotar una vez por día y quedarse
/// quieto dentro del día (los destacados de Explorar). Mismo offset fijo que
/// el resto del archivo.
String diaArgentinoDe(DateTime instante) {
  final art = instante.toUtc().subtract(_offsetArgentina);
  final m = art.month.toString().padLeft(2, '0');
  final d = art.day.toString().padLeft(2, '0');
  return '${art.year}-$m-$d';
}
