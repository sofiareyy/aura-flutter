// Precio por clase: DOS MODOS por estudio. Espejo exacto de
// `calcular_precio_clase` (migración 20260807120000_precio_dos_modos.sql).
//
// Si tocás las fórmulas de acá, tocá también las de la base o el estudio ve un
// número y se guarda otro.
//
//   estudios.tipo_precio = 'fijo'  -> todas las clases valen creditos_min.
//   estudios.tipo_precio = 'rango' -> el precio sale del horario:
//        franja marcada valle -> creditos_min  (horario flojo)
//        todo lo demás        -> creditos_max  (horario lleno)
//
// NO hay precio promedio: son dos estados y nada más. Aura marca los horarios
// flojos y el resto es pico por definición.
//
// La grilla vive en estudios.horarios_config, en franjas de 1 hora:
//   {"valle": [{"dia": 1, "hora": 8}, {"dia": 1, "hora": 19}]}
//   dia  = isodow (1 = lunes ... 7 = domingo)
//   hora = 0..23, la hora en punto
//
// Solo se guarda `valle`: si no está ahí, es pico. Guardar también `pico`
// sería estado duplicado que se puede desincronizar.
//
// Horarios rotos: cada clase toma la franja de su hora en punto hacia abajo.
// 8:30 y 8:45 usan la franja de las 8; 9:15 usa la de las 9.
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
        // Ya no se usa en modo rango (no existe el promedio). Queda para el
        // caso fijo/experiencia que sigue reportando 'normal' en la base.
        return 'Precio del estudio';
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
        return 'Horario de mayor demanda: se cobra el máximo.';
      case TipoPrecio.valle:
        return 'Horario flojo: se cobra el mínimo.';
      case TipoPrecio.normal:
        return 'Todas las clases del estudio valen lo mismo. Lo define Aura.';
    }
  }
}

/// Primera y última hora que se ofrecen como franja marcable en el backoffice.
/// Fuera de este rango (madrugada) no hay chip: esas clases quedan en pico,
/// que es el default de todo lo no marcado.
const int kHoraGrillaDesde = 6;
const int kHoraGrillaHasta = 23;

/// Las horas marcables, de 6:00 a 23:00 inclusive.
List<int> get kHorasGrilla => [
      for (int h = kHoraGrillaDesde; h <= kHoraGrillaHasta; h++) h,
    ];

/// '8' -> '08:00'. Etiqueta de cada chip de la grilla.
String horaLabel(int hora) => '${hora.toString().padLeft(2, '0')}:00';

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

    // MODO RANGO: dos estados y nada más. Si la franja está marcada como
    // valle, el mínimo; si no, el máximo. No hay promedio.
    if (esValle(estudio?['horarios_config'], dia, horaDe(hora))) {
      return PricingResult(creditos: min, tipo: TipoPrecio.valle);
    }
    return PricingResult(creditos: max, tipo: TipoPrecio.pico);
  }

  /// Franja horaria en la que cae [hora] ('HH:mm'): la hora en punto hacia
  /// abajo. 8:30 y 8:45 -> 8. 9:15 -> 9. Espejo del floor que hace el trigger.
  static int horaDe(String hora) {
    final hh = int.tryParse(hora.split(':').first);
    if (hh == null || hh < 0 || hh > 23) return 8;
    return hh;
  }

  /// ¿La franja (dia, hora) está marcada como valle en horarios_config?
  /// Todo lo que no esté marcado es pico.
  static bool esValle(dynamic horarios, int dia, int hora) {
    if (horarios is! Map) return false;
    final arr = horarios['valle'];
    if (arr is! List) return false;
    for (final e in arr) {
      if (e is! Map) continue;
      if (_asInt(e['dia']) == dia && _asInt(e['hora']) == hora) return true;
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
