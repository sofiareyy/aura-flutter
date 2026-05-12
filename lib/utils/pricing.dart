// Pricing dinamico por horario (mirror cliente del SQL
// public.calcular_precio_clase).
//
// Dado el config del estudio + categoria + dia + hora, devuelve cuantos
// creditos cuesta la clase y de que tipo ('pico'|'valle'|'normal').

enum TipoPrecio { pico, valle, normal }

class PricingResult {
  final int creditos;
  final TipoPrecio tipo;
  const PricingResult({required this.creditos, required this.tipo});
}

class PricingCalculator {
  /// estudio: el row de `estudios` (debe traer horarios_config, precio_min,
  /// precio_max, categoria).
  /// categoria: prefiere la de la clase si la tiene; sino la del estudio.
  /// dia: 1 (lunes) .. 7 (domingo).
  /// hora: 'HH:mm' en 24h.
  static PricingResult calcular({
    required Map<String, dynamic> estudio,
    required String? categoria,
    required int dia,
    required String hora,
  }) {
    final cat = (categoria ?? estudio['categoria']?.toString() ?? '')
        .trim()
        .toLowerCase();
    final precioMin = _readIntMap(estudio['precio_min']);
    final precioMax = _readIntMap(estudio['precio_max']);
    int? min = precioMin[cat];
    int? max = precioMax[cat];

    if (min == null && max == null) {
      return const PricingResult(creditos: 10, tipo: TipoPrecio.normal);
    }
    min ??= max;
    max ??= min;

    final config = estudio['horarios_config'];
    final picoList = _readRangos(config, 'pico');
    final valleList = _readRangos(config, 'valle');

    bool esPico = picoList.any((r) => _cae(r, dia, hora));
    bool esValle = !esPico && valleList.any((r) => _cae(r, dia, hora));

    if (esPico) {
      return PricingResult(creditos: max!, tipo: TipoPrecio.pico);
    }
    if (esValle) {
      return PricingResult(creditos: min!, tipo: TipoPrecio.valle);
    }
    return PricingResult(
      creditos: ((min! + max!) / 2).round(),
      tipo: TipoPrecio.normal,
    );
  }

  static Map<String, int> _readIntMap(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <String, int>{};
    raw.forEach((k, v) {
      final intV = (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '');
      if (intV != null) result[k.toString().toLowerCase()] = intV;
    });
    return result;
  }

  static List<Map<String, dynamic>> _readRangos(dynamic config, String key) {
    if (config is! Map) return const [];
    final lista = config[key];
    if (lista is! List) return const [];
    return lista
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  static bool _cae(Map<String, dynamic> rango, int dia, String hora) {
    final rDia = (rango['dia'] is num)
        ? (rango['dia'] as num).toInt()
        : int.tryParse(rango['dia']?.toString() ?? '');
    if (rDia != dia) return false;
    final inicio = rango['hora_inicio']?.toString() ?? '';
    final fin = rango['hora_fin']?.toString() ?? '';
    return inicio.compareTo(hora) <= 0 && hora.compareTo(fin) < 0;
  }
}
