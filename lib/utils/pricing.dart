// Pricing v2: dos tipos de estudio.
//
// fitness:    precio_config = {"pilates": {"normal": 12, "pico": 16}, ...}
//             horarios_pico = ["18:00","19:00",...]
//             clase en hora pico -> creditos pico
//             clase fuera         -> creditos normal
//
// experiencia: precio_config = {"ceramica": 50, "spa": 80, ...}
//              precio fijo por categoria.

enum TipoPrecio { pico, normal, experiencia }

class PricingResult {
  final int creditos;
  final TipoPrecio tipo;
  const PricingResult({required this.creditos, required this.tipo});
}

class PricingCalculator {
  /// estudio: row de `estudios` con tipo_estudio, horarios_pico, precio_config.
  /// categoria: si la clase tiene una, usar esa; sino la del estudio.
  /// hora: 'HH:mm' en formato 24h.
  static PricingResult calcular({
    required Map<String, dynamic> estudio,
    required String? categoria,
    required String hora,
  }) {
    final tipoStr =
        (estudio['tipo_estudio']?.toString() ?? 'fitness').toLowerCase();
    final cat = (categoria ?? estudio['categoria']?.toString() ?? '')
        .trim()
        .toLowerCase();
    final config = estudio['precio_config'];

    if (tipoStr == 'experiencia') {
      final precio = _readInt(config, cat) ?? 40;
      return PricingResult(creditos: precio, tipo: TipoPrecio.experiencia);
    }

    // fitness
    final horasPico = (estudio['horarios_pico'] as List?) ?? const [];
    final horaNorm = _normalizarHora(hora);
    final esPico = horasPico.any((h) => h?.toString() == horaNorm);

    final catConfig = (config is Map) ? (config[cat] as Map?) : null;
    if (esPico) {
      final precio = _readInt(catConfig, 'pico') ?? 18;
      return PricingResult(creditos: precio, tipo: TipoPrecio.pico);
    }
    final precio = _readInt(catConfig, 'normal') ?? 12;
    return PricingResult(creditos: precio, tipo: TipoPrecio.normal);
  }

  static int? _readInt(dynamic m, String key) {
    if (m is! Map) return null;
    final v = m[key];
    if (v is num) return v.toInt();
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return null;
      return int.tryParse(s);
    }
    return null;
  }

  static String _normalizarHora(String hora) {
    final parts = hora.split(':');
    if (parts.isEmpty) return '00:00';
    final h = parts[0].padLeft(2, '0');
    return '$h:00';
  }
}
