import 'package:supabase_flutter/supabase_flutter.dart';

/// Valor de 1 crédito en ARS.
///
/// La fuente de verdad es `configuracion_global.valor_credito_ars`, que el
/// admin cambia con `admin_set_valor_credito_ars` (ese RPC además espeja el
/// número en `estudios.valor_credito` por compatibilidad).
///
/// Existe porque había seis lugares con `?? 6000` hardcodeado como fallback
/// mientras el valor real configurado es 1000: cualquier estudio con
/// `valor_credito` en null mostraba y liquidaba montos 6x más altos.
///
/// El valor se cachea en memoria: se lee al arrancar la app y las pantallas
/// lo consultan de forma síncrona desde sus getters de dinero.
class ValorCredito {
  const ValorCredito._();

  /// Default de `PRICING_SIMPLIFICADO.sql`. Solo aplica si la config todavía
  /// no se leyó (primer frame) o si la query falló.
  static const int fallback = 1000;

  static int _cache = fallback;

  /// Momento de la última lectura exitosa. Sirve para el throttle del refresh
  /// por foreground: no reconsultamos si ya lo hicimos hace poco.
  static DateTime? _ultimaCarga;

  /// Ventana del throttle: si se pide un refresh dentro de este lapso desde la
  /// última carga exitosa, se devuelve el cache sin ir a la base.
  static const Duration _ttl = Duration(minutes: 5);

  /// Último valor conocido. Nunca devuelve null: si no se cargó, `fallback`.
  static int get actual => _cache;

  /// Relee la config y actualiza el cache. Idempotente y barato (una fila).
  ///
  /// Con `forzar: false` respeta el throttle de [_ttl]: si ya se leyó hace
  /// menos de 5 min, no vuelve a consultar (para el refresh por foreground,
  /// que puede dispararse seguido). El arranque de la app usa `forzar: true`.
  static Future<int> cargar({bool forzar = true}) async {
    if (!forzar &&
        _ultimaCarga != null &&
        DateTime.now().difference(_ultimaCarga!) < _ttl) {
      return _cache;
    }
    try {
      final res = await Supabase.instance.client
          .from('configuracion_global')
          .select('valor')
          .eq('clave', 'valor_credito_ars')
          .maybeSingle();
      final parsed = int.tryParse(res?['valor']?.toString().trim() ?? '');
      if (parsed != null && parsed > 0) _cache = parsed;
      // Marca la lectura como exitosa aunque el valor no haya cambiado; si la
      // query falla (catch), no se marca y se reintenta en el próximo foreground.
      _ultimaCarga = DateTime.now();
    } catch (_) {
      // Se mantiene el último valor conocido.
    }
    return _cache;
  }

  /// Valor a usar para un estudio: el suyo si lo tiene, si no el global.
  /// Reemplaza al viejo `(estudio['valor_credito'] as num?)?.toInt() ?? 6000`.
  static int deEstudio(Map<String, dynamic>? estudio) {
    final propio = (estudio?['valor_credito'] as num?)?.toInt();
    if (propio != null && propio > 0) return propio;
    return _cache;
  }
}
