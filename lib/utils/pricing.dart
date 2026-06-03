// Pricing v3: precio por ESTUDIO (no por categoria).
//
// fitness:
//   precio_config   = {"min": 10, "max": 18, "pico_multiplier": 1.0}
//   horarios_config = {"pico":  [{"dia": 1, "rango": "tarde_noche"}],
//                      "valle": [{"dia": 2, "rango": "mediodia"}]}
//   - dia: isodow (1 = lunes ... 7 = domingo)
//   - rango: nombre del bloque horario en el que cae la hora_inicio.
//   - clase en pico  -> creditos = round(max * pico_multiplier)
//   - clase en valle -> creditos = round(min * 0.9)   (incentivo -10%)
//   - clase normal   -> creditos = min
//
// experiencia:
//   precio_config = {"min": 50, "max": 50, "pico_multiplier": 1.0}
//   precio fijo (= min) sin importar dia/hora.

enum TipoPrecio { pico, normal, valle, experiencia }

class PricingResult {
  final int creditos;
  final TipoPrecio tipo;
  const PricingResult({required this.creditos, required this.tipo});
}

/// Bloque horario con nombre. `desde` inclusive, `hasta` exclusivo (en horas).
class RangoHorario {
  final String key;
  final String label;
  final int desde;
  final int hasta;
  const RangoHorario(this.key, this.label, this.desde, this.hasta);
}

/// Rangos que se muestran como chips en el backoffice.
/// `madrugada` (0-6) existe en [PricingCalculator.rangoDeHora] para clasificar
/// clases muy temprano, pero no se ofrece como chip seleccionable.
const List<RangoHorario> kRangosHorarios = [
  RangoHorario('manana_temprano', '6 - 9hs', 6, 9),
  RangoHorario('manana', '9 - 12hs', 9, 12),
  RangoHorario('mediodia', '12 - 15hs', 12, 15),
  RangoHorario('tarde', '15 - 18hs', 15, 18),
  RangoHorario('tarde_noche', '18 - 21hs', 18, 21),
  RangoHorario('noche', '21 - 23hs', 21, 24),
];

class PricingCalculator {
  /// estudio: row de `estudios` con tipo_estudio, precio_config, horarios_config.
  /// hora: 'HH:mm' en formato 24h.
  /// dia: isodow (1 = lunes ... 7 = domingo).
  /// categoria: ignorado en v3 (el precio es por estudio); se mantiene por compat.
  static PricingResult calcular({
    required Map<String, dynamic> estudio,
    required String hora,
    required int dia,
    String? categoria,
  }) {
    final tipoStr =
        (estudio['tipo_estudio']?.toString() ?? 'fitness').toLowerCase();
    final config = estudio['precio_config'];
    final min = _readNum(config, 'min') ?? 10;
    final max = _readNum(config, 'max') ?? min;
    final mult = _readNum(config, 'pico_multiplier') ?? 1.0;

    if (tipoStr == 'experiencia') {
      return PricingResult(creditos: min.round(), tipo: TipoPrecio.experiencia);
    }

    final rango = rangoDeHora(hora);
    final horarios = estudio['horarios_config'];
    final esPico = _coincide(horarios, 'pico', dia, rango);
    final esValle = !esPico && _coincide(horarios, 'valle', dia, rango);

    if (esPico) {
      return PricingResult(creditos: (max * mult).round(), tipo: TipoPrecio.pico);
    }
    if (esValle) {
      return PricingResult(creditos: (min * 0.9).round(), tipo: TipoPrecio.valle);
    }
    return PricingResult(creditos: min.round(), tipo: TipoPrecio.normal);
  }

  /// Devuelve el `key` del rango horario en el que cae [hora] ('HH:mm').
  static String rangoDeHora(String hora) {
    final hh = int.tryParse(hora.split(':').first) ?? 8;
    if (hh < 6) return 'madrugada';
    if (hh < 9) return 'manana_temprano';
    if (hh < 12) return 'manana';
    if (hh < 15) return 'mediodia';
    if (hh < 18) return 'tarde';
    if (hh < 21) return 'tarde_noche';
    return 'noche';
  }

  /// Busca en horarios_config[key] una entrada que matchee (dia, rango).
  static bool _coincide(
      dynamic horarios, String key, int dia, String rango) {
    if (horarios is! Map) return false;
    final arr = horarios[key];
    if (arr is! List) return false;
    for (final e in arr) {
      if (e is! Map) continue;
      final d = (e['dia'] is num)
          ? (e['dia'] as num).toInt()
          : int.tryParse('${e['dia']}');
      if (d == dia && e['rango']?.toString() == rango) return true;
    }
    return false;
  }

  static double? _readNum(dynamic m, String key) {
    if (m is! Map) return null;
    final v = m[key];
    if (v is num) return v.toDouble();
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return null;
      return double.tryParse(s);
    }
    return null;
  }
}
