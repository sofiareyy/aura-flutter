import '../core/constants/app_constants.dart';
import '../services/valor_credito.dart';

/// Fuente única de la lógica de "cuánta plata recibe el estudio".
///
/// Antes cada pantalla (Cobros, Dashboard, Liquidaciones, el reporte mensual)
/// tenía su propia fórmula y no coincidían: unas ignoraban `fecha_inicio_cobro`,
/// otra hardcodeaba el valor del crédito o la comisión de workshops. Todo eso
/// pasa por acá para que las cinco vistas den el mismo número.
class Liquidacion {
  const Liquidacion._();

  /// Comisión de clases por defecto si el estudio no la tiene seteada.
  /// Es solo un fallback: la comisión real es variable por estudio y puede
  /// ser 0 (promo sin comisión), más o menos que 30.
  static const double comisionClaseDefault = 30;

  /// Comisión de workshops por defecto. También configurable por estudio.
  static const double comisionWorkshopDefault = 15;

  /// True si el estudio ya está en período de cobro. Antes de
  /// `fecha_inicio_cobro`, Aura no cobra comisión (el estudio recibe el 100%).
  static bool cobraComision(Map<String, dynamic>? estudio) {
    final raw = estudio?['fecha_inicio_cobro']?.toString();
    if (raw == null || raw.isEmpty) return true;
    final desde = DateTime.tryParse(raw);
    if (desde == null) return true;
    return !DateTime.now().isBefore(desde);
  }

  /// Comisión efectiva (%) para una reserva, según tipo y período de cobro.
  static double comision(Map<String, dynamic>? estudio, {required bool esWorkshop}) {
    if (!cobraComision(estudio)) return 0;
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
  static int netoReserva(
    Map<String, dynamic> reserva,
    Map<String, dynamic>? estudio,
  ) {
    final estado = reserva['estado']?.toString();
    if (!AppConstants.estadosLiquidables.contains(estado)) return 0;

    final creditos = (reserva['creditos_usados'] as num?)?.toInt() ?? 0;
    if (creditos <= 0) return 0;

    final valor = ValorCredito.deEstudio(estudio);
    final pct = comision(estudio, esWorkshop: _esWorkshop(reserva));
    final bruto = creditos * valor;
    return (bruto * ((100 - pct) / 100)).round();
  }

  /// Suma del neto de una lista de reservas.
  static int netoTotal(
    Iterable<Map<String, dynamic>> reservas,
    Map<String, dynamic>? estudio,
  ) =>
      reservas.fold<int>(0, (acc, r) => acc + netoReserva(r, estudio));

  // ── Workshops: precio en pesos que el estudio quiere RECIBIR ─────────────
  //
  // El estudio ingresa cuánta plata quiere recibir. El precio al usuario es
  //   precio_pesos = monto / (1 - comision_workshop)
  // así el estudio recibe exactamente su monto y Aura cobra su comisión real.
  // NO es monto * 1.15: eso dejaba al estudio recibiendo ~2,25% menos.

  /// Créditos que paga el usuario por un workshop de `montoEstudio` pesos.
  static int creditosDeWorkshop(int montoEstudio, Map<String, dynamic>? estudio) {
    if (montoEstudio <= 0) return 0;
    final valor = ValorCredito.deEstudio(estudio);
    if (valor <= 0) return 0;
    final pct = comision(estudio, esWorkshop: true);
    final factor = (100 - pct) / 100; // 0.85 con comisión 15
    if (factor <= 0) return 0;
    return (montoEstudio / factor / valor).round();
  }

  /// Inverso: cuánta plata recibe el estudio dados N créditos de workshop.
  /// Es la fórmula de liquidación real (créditos × valor × (1 − comisión)),
  /// así que coincide con lo que efectivamente cobra.
  static int montoEstudioDeWorkshop(int creditos, Map<String, dynamic>? estudio) {
    if (creditos <= 0) return 0;
    final valor = ValorCredito.deEstudio(estudio);
    final pct = comision(estudio, esWorkshop: true);
    return (creditos * valor * ((100 - pct) / 100)).round();
  }
}
