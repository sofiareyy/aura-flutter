/// Datos de cobro de un estudio (CBU, alias, banco, titular, comisiones,
/// valor del crédito, día de pago).
///
/// Viven en la tabla `estudios_datos_cobro`, **separada de `estudios`**: el
/// catálogo es público (lo lee un invitado sin cuenta), así que el CBU y el
/// margen no pueden viajar ahí. La RLS de `estudios_datos_cobro` solo deja leer
/// a `is_admin()` o a `es_miembro_de_estudio(estudio_id)`.
///
/// `fecha_inicio_cobro` NO se movió: sigue siendo columna de `estudios`.
///
/// Estos helpers devuelven el mapa con la MISMA forma plana que tenía cuando
/// todo estaba en una sola tabla, así las pantallas que leen `estudio['cbu']` o
/// `Liquidacion.netoTotal(reservas, estudio)` no necesitan cambiar.
class DatosCobro {
  const DatosCobro._();

  /// Para el `.select()` de `estudios` cuando además hacen falta los datos de
  /// cobro (panel de estudio y backoffice; NUNCA en el browse).
  static const embedTodo = '*, estudios_datos_cobro(*)';

  /// Aplana el embed dentro del mapa del estudio.
  static Map<String, dynamic> aplanar(Map<String, dynamic> row) {
    final raw = row['estudios_datos_cobro'];
    final dc = raw is List ? (raw.isEmpty ? null : raw.first) : raw;
    final out = Map<String, dynamic>.from(row)..remove('estudios_datos_cobro');
    if (dc is Map) {
      for (final entry in Map<String, dynamic>.from(dc).entries) {
        // estudio_id es la PK del embed, no un dato: duplicaría `id`.
        if (entry.key == 'estudio_id') continue;
        out[entry.key] = entry.value;
      }
    }
    return out;
  }

  /// Igual que [aplanar] pero para una lista de filas.
  static List<Map<String, dynamic>> aplanarLista(Iterable<dynamic> rows) => rows
      .map((r) => aplanar(Map<String, dynamic>.from(r as Map)))
      .toList();
}
