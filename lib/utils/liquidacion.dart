import '../core/constants/app_constants.dart';
import '../services/valor_credito.dart';
import 'mes_argentino.dart';

/// Fuente única de la lógica de "cuánta plata recibe el estudio".
///
/// Antes cada pantalla (Cobros, Dashboard, Liquidaciones, el reporte mensual)
/// tenía su propia fórmula y no coincidían: unas ignoraban `fecha_inicio_cobro`,
/// otra hardcodeaba el valor del crédito o la comisión de workshops. Todo eso
/// pasa por acá para que las cinco vistas den el mismo número.
///
/// ⚠️ LA GRACIA SE EVALÚA CON LA FECHA DE LA CLASE (16/9/2026). Antes se
/// comparaba `fecha_inicio_cobro` contra HOY, así que cuando terminaba la
/// gracia la comisión se aplicaba hacia atrás: Citra (gracia hasta el 13/9)
/// pasó a mostrar $12.600 por una clase del 1/9 que valía $18.000, y agosto
/// entero se selló al 30%. Una clase dada antes de `fecha_inicio_cobro` es del
/// estudio al 100%, la mire quien la mire y la pague cuando se pague.
/// Espejo server-side: supabase/functions/_shared/liquidacion.ts.
class Liquidacion {
  const Liquidacion._();

  /// Comisión de clases por defecto si el estudio no la tiene seteada.
  /// Es solo un fallback: la comisión real es variable por estudio y puede
  /// ser 0 (promo sin comisión), más o menos que 30.
  static const double comisionClaseDefault = 30;

  /// Comisión de workshops por defecto. También configurable por estudio.
  static const double comisionWorkshopDefault = 15;

  /// Lo efectivamente pagado de una liquidación: `monto_a_pagar` más la
  /// suma de sus asientos de corrección (`liquidaciones_correcciones`,
  /// 16/9/2026). La fila de la liquidación nunca se toca; si se pagó otra
  /// cosa, queda en un asiento aparte con motivo y firma.
  static int montoPagadoEfectivo(Map<String, dynamic> liquidacion) {
    final base = (liquidacion['monto_a_pagar'] as num?)?.toInt() ?? 0;
    return base + correccionesDe(liquidacion).fold<int>(
        0, (acc, c) => acc + ((c['diferencia'] as num?)?.toInt() ?? 0));
  }

  /// Los asientos de corrección de una liquidación, más viejo primero.
  static List<Map<String, dynamic>> correccionesDe(
      Map<String, dynamic> liquidacion) {
    final raw = liquidacion['liquidaciones_correcciones'];
    if (raw is! List) return const [];
    final lista = raw
        .whereType<Map>()
        .map((c) => Map<String, dynamic>.from(c))
        .toList()
      ..sort((a, b) => (a['created_at']?.toString() ?? '')
          .compareTo(b['created_at']?.toString() ?? ''));
    return lista;
  }

  /// La comisión que rige después de las correcciones: la del último asiento
  /// si lo hay, si no la sellada en la fila. `null` si no hay ninguna.
  static double? comisionEfectivaSellada(Map<String, dynamic> liquidacion) {
    final correcciones = correccionesDe(liquidacion);
    final ultima = correcciones.isEmpty ? null : correcciones.last;
    final raw = ultima?['comision_real'] ?? liquidacion['comision_aplicada'];
    if (raw == null) return null;
    return double.tryParse(raw.toString());
  }

  /// La fecha de la clase de una reserva, si viene adjunta. Los servicios la
  /// pegan como `_clase_fecha` (igual que `_clase_tipo`); el backoffice la
  /// trae del embed de `clases`.
  static DateTime? fechaDeClase(Map<String, dynamic> reserva) {
    final raw = reserva['_clase_fecha'] ?? reserva['clase_fecha'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  /// True si a esa fecha el estudio ya está en período de cobro. Antes de
  /// `fecha_inicio_cobro`, Aura no cobra comisión (el estudio recibe el 100%).
  ///
  /// [fecha] es la fecha de la CLASE. Se compara por día calendario argentino
  /// contra `fecha_inicio_cobro` (que es un día, sin hora): una clase del
  /// 12/9 a las 23:30 ART está en gracia aunque en UTC ya sea 13/9.
  ///
  /// Sin [fecha] se usa hoy: sirve sólo para vistas previas ("vos recibís")
  /// donde todavía no hay clase. NUNCA para liquidar una reserva.
  static bool cobraComision(Map<String, dynamic>? estudio, {DateTime? fecha}) {
    final raw = estudio?['fecha_inicio_cobro']?.toString();
    if (raw == null || raw.length < 10) return true;
    final inicio = raw.substring(0, 10); // 'YYYY-MM-DD'
    if (DateTime.tryParse(inicio) == null) return true;
    final dia = diaArgentinoDe(fecha ?? DateTime.now());
    return dia.compareTo(inicio) >= 0;
  }

  /// Comisión efectiva (%) para una reserva, según tipo, fecha de la clase y
  /// período de cobro.
  static double comision(
    Map<String, dynamic>? estudio, {
    required bool esWorkshop,
    DateTime? fecha,
  }) {
    if (!cobraComision(estudio, fecha: fecha)) return 0;
    if (esWorkshop) {
      return (estudio?['comision_workshop'] as num?)?.toDouble() ??
          comisionWorkshopDefault;
    }
    return (estudio?['comision_aura'] as num?)?.toDouble() ??
        comisionClaseDefault;
  }

  static bool _esWorkshop(Map<String, dynamic> reserva) =>
      reserva['_clase_tipo']?.toString() == 'workshop';

  /// Neto que recibe el estudio por UNA reserva. 0 si el estado no se cobra
  /// (cancelada / cancelada_por_estudio / pre_confirmada).
  ///
  /// La gracia se decide con la fecha de la clase de ESTA reserva
  /// (`_clase_fecha`). Si no viene, cae a hoy, que es el comportamiento
  /// viejo: por eso todos los que llaman tienen que adjuntarla.
  static int netoReserva(
    Map<String, dynamic> reserva,
    Map<String, dynamic>? estudio,
  ) {
    final estado = reserva['estado']?.toString();
    if (!AppConstants.estadosLiquidables.contains(estado)) return 0;

    final creditos = (reserva['creditos_usados'] as num?)?.toInt() ?? 0;
    if (creditos <= 0) return 0;

    final valor = ValorCredito.deEstudio(estudio);
    final pct = comision(
      estudio,
      esWorkshop: _esWorkshop(reserva),
      fecha: fechaDeClase(reserva),
    );
    final bruto = creditos * valor;
    return (bruto * ((100 - pct) / 100)).round();
  }

  /// Suma del neto de una lista de reservas.
  static int netoTotal(
    Iterable<Map<String, dynamic>> reservas,
    Map<String, dynamic>? estudio,
  ) =>
      reservas.fold<int>(0, (acc, r) => acc + netoReserva(r, estudio));

  /// Pesos que recibiría el estudio por una clase de `creditos` créditos.
  /// Respeta el período de gracia (`fecha_inicio_cobro`): dentro de la gracia
  /// Aura no cobra comisión y el estudio recibe el 100%. Sirve para mostrar
  /// "vos recibís $X" en el form, con la misma fórmula que la liquidación real.
  /// [fecha] es la de la clase que se está armando; sin ella, hoy.
  static int netoDeCreditos(
    int creditos,
    Map<String, dynamic>? estudio, {
    bool esWorkshop = false,
    DateTime? fecha,
  }) {
    if (creditos <= 0) return 0;
    final valor = ValorCredito.deEstudio(estudio);
    final pct = comision(estudio, esWorkshop: esWorkshop, fecha: fecha);
    return (creditos * valor * ((100 - pct) / 100)).round();
  }

  // ── Workshops: precio en pesos que el estudio quiere RECIBIR ─────────────
  //
  // El estudio ingresa cuánta plata quiere recibir. El precio al usuario es
  //   precio_pesos = monto / (1 - comision_workshop)
  // así el estudio recibe exactamente su monto y Aura cobra su comisión real.
  // NO es monto * 1.15: eso dejaba al estudio recibiendo ~2,25% menos.

  /// Créditos que paga el usuario por un workshop de `montoEstudio` pesos.
  static int creditosDeWorkshop(
    int montoEstudio,
    Map<String, dynamic>? estudio, {
    DateTime? fecha,
  }) {
    if (montoEstudio <= 0) return 0;
    final valor = ValorCredito.deEstudio(estudio);
    if (valor <= 0) return 0;
    final pct = comision(estudio, esWorkshop: true, fecha: fecha);
    final factor = (100 - pct) / 100; // 0.85 con comisión 15
    if (factor <= 0) return 0;
    return (montoEstudio / factor / valor).round();
  }

  /// Inverso: cuánta plata recibe el estudio dados N créditos de workshop.
  /// Es la fórmula de liquidación real (créditos × valor × (1 − comisión)),
  /// así que coincide con lo que efectivamente cobra.
  static int montoEstudioDeWorkshop(
    int creditos,
    Map<String, dynamic>? estudio, {
    DateTime? fecha,
  }) {
    if (creditos <= 0) return 0;
    final valor = ValorCredito.deEstudio(estudio);
    final pct = comision(estudio, esWorkshop: true, fecha: fecha);
    return (creditos * valor * ((100 - pct) / 100)).round();
  }
}
