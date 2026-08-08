// Precio por clase: DOS MODOS por estudio. Espejo exacto de
// `calcular_precio_clase` (migración 20260807120000_precio_dos_modos.sql).
//
// Si tocás las fórmulas de acá, tocá también las de la base o el estudio ve un
// número y se guarda otro.
//
//   estudios.tipo_precio = 'fijo'  -> todas las clases valen creditos_min.
//   estudios.tipo_precio = 'rango' -> el precio sale del horario:
//        franja marcada pico  -> creditos_max
//        franja marcada valle -> creditos_min
//        sin marcar (normal)  -> round((min + max) / 2)
//
// La grilla vive en estudios.horarios_config:
//   {"pico": [{"dia": 1, "rango": "tarde_noche"}], "valle": [...]}
//   dia = isodow (1 = lunes ... 7 = domingo)
//
// `precio_config` quedó DEPRECADO: solo se lee como fallback para estudios que
// todavía no tengan creditos_min/creditos_max cargados.

enum TipoPrecio { fijo, pico, valle, normal, experiencia }

class PricingResult {
  /// null = el estudio no tiene precio configurado todavía.
  final int? creditos;
  final TipoPrecio tipo;

  const PricingResult({required this.creditos, required this.tipo});

  bool get configurado => creditos != null;

  /// Etiqueta que explica de dónde salió el precio, para el campo read-only
  /// del panel del estudio.
  String get badge {
    switch (tipo) {
      case TipoPrecio.fijo:
        return 'Precio del estudio';
      case TipoPrecio.pico:
        return '⚡ Horario pico';
      case TipoPrecio.valle:
        return '🌙 Horario valle';
      case TipoPrecio.normal:
        return '🏷️ Horario normal';
      case TipoPrecio.experiencia:
        return 'Precio fijo';
    }
  }

  /// Aclaración de una línea debajo del campo.
  String get detalle {
    switch (tipo) {
      case TipoPrecio.fijo:
      case TipoPrecio.experiencia:
        return 'Todas las clases del estudio valen lo mismo. Lo define Aura.';
      case TipoPrecio.pico:
        return 'Este día y horario están marcados como pico.';
      case TipoPrecio.valle:
        return 'Este día y horario están marcados como valle.';
      case TipoPrecio.normal:
        return 'Horario sin marcar: se cobra el promedio del rango.';
    }
  }
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
/// clases muy temprano, pero no se ofrece como chip seleccionable: una clase a
/// las 5 AM cae siempre en "normal".
const List<RangoHorario> kRangosHorarios = [
  RangoHorario('manana_temprano', '6 - 9hs', 6, 9),
  RangoHorario('manana', '9 - 12hs', 9, 12),
  RangoHorario('mediodia', '12 - 15hs', 12, 15),
  RangoHorario('tarde', '15 - 18hs', 15, 18),
  RangoHorario('tarde_noche', '18 - 21hs', 18, 21),
  RangoHorario('noche', '21 - 23hs', 21, 24),
];

/// Config de precio de un estudio, ya normalizada.
class PricingConfig {
  final String modo; // 'fijo' | 'rango'
  final int? min;
  final int? max;
  final bool esExperiencia;

  const PricingConfig({
    required this.modo,
    required this.min,
    required this.max,
    required this.esExperiencia,
  });

  bool get configurado => min != null;
  bool get esRango => modo == 'rango';
}

class PricingCalculator {
  /// Lee la config de precio de un row de `estudios`, con fallback a la
  /// `precio_config` vieja.
  static PricingConfig configDe(Map<String, dynamic>? estudio) {
    if (estudio == null) {
      return const PricingConfig(
          modo: 'fijo', min: null, max: null, esExperiencia: false);
    }
    var modo = estudio['tipo_precio']?.toString() ?? 'fijo';
    if (modo != 'fijo' && modo != 'rango') modo = 'fijo';

    final config = estudio['precio_config'];
    int? min = _asInt(estudio['creditos_min']) ?? _readInt(config, 'min');
    int? max = _asInt(estudio['creditos_max']) ?? _readInt(config, 'max') ?? min;
    if (min != null && max != null && max < min) max = min;

    final esExperiencia =
        (estudio['tipo_estudio']?.toString() ?? 'fitness').toLowerCase() ==
            'experiencia';

    return PricingConfig(
      modo: modo,
      min: min,
      max: max,
      esExperiencia: esExperiencia,
    );
  }

  /// estudio: row de `estudios`.
  /// hora: 'HH:mm' en formato 24h.
  /// dia: isodow (1 = lunes ... 7 = domingo).
  /// categoria: ignorado (el precio es por estudio); se mantiene por compat.
  static PricingResult calcular({
    required Map<String, dynamic>? estudio,
    required String hora,
    required int dia,
    String? categoria,
  }) {
    final cfg = configDe(estudio);
    final min = cfg.min;
    if (min == null) {
      return const PricingResult(creditos: null, tipo: TipoPrecio.fijo);
    }
    final max = cfg.max ?? min;

    if (cfg.esExperiencia) {
      return PricingResult(creditos: min, tipo: TipoPrecio.experiencia);
    }

    // MODO FIJO: un único precio, sin importar el horario.
    if (!cfg.esRango) {
      return PricingResult(creditos: min, tipo: TipoPrecio.fijo);
    }

    // MODO RANGO: el precio sale de la franja horaria.
    final rango = rangoDeHora(hora);
    final horarios = estudio?['horarios_config'];
    if (_coincide(horarios, 'pico', dia, rango)) {
      return PricingResult(creditos: max, tipo: TipoPrecio.pico);
    }
    if (_coincide(horarios, 'valle', dia, rango)) {
      return PricingResult(creditos: min, tipo: TipoPrecio.valle);
    }
    // Sin marcar — incluye el caso "modo rango sin grilla cargada todavía".
    return PricingResult(
      creditos: ((min + max) / 2).round(),
      tipo: TipoPrecio.normal,
    );
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
  static bool _coincide(dynamic horarios, String key, int dia, String rango) {
    if (horarios is! Map) return false;
    final arr = horarios[key];
    if (arr is! List) return false;
    for (final e in arr) {
      if (e is! Map) continue;
      final d = _asInt(e['dia']);
      if (d == dia && e['rango']?.toString() == rango) return true;
    }
    return false;
  }

  static int? _readInt(dynamic m, String key) {
    if (m is! Map) return null;
    return _asInt(m[key]);
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return int.tryParse(s) ?? double.tryParse(s)?.round();
  }
}
