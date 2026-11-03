/// Los ids de clases y de alumnas de las reservas que muestra el detalle de
/// un mes en Cobros, para buscar sus nombres.
///
/// Existe aparte para poder testearlo: el 3/11/2026 el detalle de un mes
/// pasado buscaba los ids del mes EN CURSO y casi todas las filas salían sin
/// nombre. Los ids tienen que salir de la misma lista que se dibuja.
(List<int>, List<String>) idsDelDetalle(List<Map<String, dynamic>> reservas) {
  final claseIds = reservas
      .map((r) => (r['clase_id'] as num?)?.toInt())
      .whereType<int>()
      .toSet()
      .toList();
  final userIds = reservas
      .map((r) => r['usuario_id']?.toString())
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();
  return (claseIds, userIds);
}
