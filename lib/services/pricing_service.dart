
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_constants.dart';

/// Pricing dinamico de Aura.
/// La unica variable que cambia con la inflacion es `valor_credito_ars`
/// en `configuracion_global`. Todos los packs se calculan automaticamente:
///
///   Pack Prueba    : 20 cr  x valor x 1.10
///   Pack Esencial  : 50 cr  x valor x 1.05
///   Pack Popular   : 100 cr x valor x 1.00
///   Pack Full      : 200 cr x valor x 0.95
///
/// OJO: `vigenciaDias` de acá es solo para mostrar. El vencimiento real lo
/// decide el servidor en `validityForPack` (mp-webhook y confirmar-pago-manual).
/// Si cambiás uno, cambiá el otro o el texto miente.
class PricingService {
  final _client = Supabase.instance.client;

  static const int _valorCreditoFallback = 1000;
  static const List<_PackBase> _packsBase = [
    _PackBase(
      nombre: 'Pack Prueba',
      creditos: 20,
      multiplicador: 1.10,
      vigenciaDias: 30,
      badge: null,
      descripcion: 'Ideal para conocer Aura · vence en 30 días',
    ),
    _PackBase(
      nombre: 'Pack Esencial',
      creditos: 50,
      multiplicador: 1.05,
      vigenciaDias: 45,
      badge: 'MÁS POPULAR',
      descripcion: 'Para sumar clases al mes · vence en 45 días',
    ),
    _PackBase(
      nombre: 'Pack Popular',
      creditos: 100,
      multiplicador: 1.00,
      vigenciaDias: 45,
      badge: 'MEJOR VALOR',
      descripcion: 'Para entrenar seguido y variar · vence en 45 días',
    ),
    _PackBase(
      nombre: 'Pack Full',
      creditos: 200,
      multiplicador: 0.95,
      vigenciaDias: 60,
      badge: null,
      descripcion: 'Máxima libertad para explorar · vence en 60 días',
    ),
  ];

  /// Lee el valor de 1 credito en ARS desde configuracion_global.
  /// Si no esta seteado o falla, devuelve 1000.
  Future<int> getValorCreditoArs() async {
    try {
      final res = await _client
          .from('configuracion_global')
          .select('valor')
          .eq('clave', 'valor_credito_ars')
          .maybeSingle();
      final raw = res?['valor']?.toString().trim() ?? '';
      final parsed = int.tryParse(raw);
      if (parsed != null && parsed > 0) return parsed;
      return _valorCreditoFallback;
    } catch (_) {
      return _valorCreditoFallback;
    }
  }

  /// Monto que recibe el estudio por una clase de N créditos, dada la
  /// comisión de Aura para ese estudio (variable: puede ser 0, 30 o lo que
  /// se haya negociado). Antes tenía 30% hardcodeado.
  int montoEstudioPorClase(int valorCredito, int creditos, double comisionPct) =>
      (valorCredito * creditos * (100 - comisionPct) / 100).round();

  /// Lee los packs desde `pricing_credit_packs`, la MISMA tabla que usa
  /// `crear-checkout-pack` para cobrar. Así lo que muestra la app y lo que
  /// cobra Mercado Pago salen de la misma fuente: podés subir precios por
  /// inflación editando la tabla, sin recompilar la app ni romper compras.
  ///
  /// Si la tabla no responde o viene vacía, cae a los packs calculados desde
  /// `valor_credito` (igual que getPlanes cae a AppConstants.planes).
  Future<List<Map<String, dynamic>>> getPacks() async {
    try {
      final data = await _client
          .from('pricing_credit_packs')
          .select()
          .eq('activo', true)
          .order('orden');
      final rows = List<Map<String, dynamic>>.from(data as List);
      if (rows.isEmpty) return _packsCalculados();
      return rows.map(_packDesdeFila).toList();
    } catch (_) {
      return _packsCalculados();
    }
  }

  /// Fallback: los 4 packs canónicos calculados desde `valor_credito`.
  Future<List<Map<String, dynamic>>> _packsCalculados() async {
    final valor = await getValorCreditoArs();
    return _packsBase.map((p) => p.toMap(valor)).toList();
  }

  /// Normaliza una fila de `pricing_credit_packs` a la forma que espera la UI.
  /// El vencimiento real es `vencimiento_dias` (el que lee el server); la
  /// columna `vigencia_dias` de la tabla quedó duplicada y no la usa nadie.
  ///
  /// El badge sale de `popular` (bool) -> 'MÁS POPULAR'. El 'MEJOR VALOR' del
  /// Pack Popular se pierde por ahora: la tabla no tiene columna de texto para
  /// el badge. Pendiente: agregar columna `badge` cuando se linkee el CLI.
  Map<String, dynamic> _packDesdeFila(Map<String, dynamic> row) {
    final esPopular = row['popular'] == true;
    return {
      'nombre': row['nombre']?.toString() ?? '',
      'creditos': (row['creditos'] as num?)?.toInt() ?? 0,
      'precio': (row['precio'] as num?)?.toInt() ?? 0,
      'vigencia_dias': (row['vencimiento_dias'] as num?)?.toInt(),
      'descripcion': row['descripcion']?.toString() ?? '',
      'badge': esPopular ? 'MÁS POPULAR' : null,
      // se mantiene por compat con codigo que lo lee
      'popular': esPopular,
      'orden': (row['orden'] as num?)?.toInt() ?? 999,
    };
  }

  /// Calcula los packs sin ir al server (usando el valor pasado).
  /// Util para preview en el backoffice mientras edita.
  List<Map<String, dynamic>> packsConValor(int valorCredito) {
    return _packsBase.map((p) => p.toMap(valorCredito)).toList();
  }

  Future<List<Map<String, dynamic>>> getPlanes() async {
    try {
      final data = await _client
          .from('pricing_planes')
          .select()
          .eq('activo', true)
          .order('orden');
      final list = List<Map<String, dynamic>>.from(data as List);
      if (list.isEmpty) return AppConstants.planes;
      return list;
    } catch (_) {
      return AppConstants.planes;
    }
  }
}

class _PackBase {
  final String nombre;
  final int creditos;
  final double multiplicador;
  final int vigenciaDias;
  final String? badge;
  final String descripcion;

  const _PackBase({
    required this.nombre,
    required this.creditos,
    required this.multiplicador,
    required this.vigenciaDias,
    required this.badge,
    required this.descripcion,
  });

  Map<String, dynamic> toMap(int valorCredito) => {
        'nombre': nombre,
        'creditos': creditos,
        'precio': (creditos * valorCredito * multiplicador).round(),
        'vigencia_dias': vigenciaDias,
        'badge': badge,
        // popular se mantiene por compat con codigo existente que lo lee
        'popular': badge != null,
        'descripcion': descripcion,
        'multiplicador': multiplicador,
      };
}
