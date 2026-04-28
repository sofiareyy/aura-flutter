import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_constants.dart';

/// Pricing dinamico de Aura.
/// La unica variable que cambia con la inflacion es `valor_credito_ars`
/// en `configuracion_global`. Todos los packs se calculan automaticamente:
///
///   Pack Prueba    : 20 cr  x valor x 1.00
///   Pack Esencial  : 50 cr  x valor x 0.95
///   Pack Popular   : 100 cr x valor x 0.90
///   Pack Full      : 200 cr x valor x 0.85
class PricingService {
  final _client = Supabase.instance.client;

  static const int _valorCreditoFallback = 1000;
  static const double _comisionEstudio = 0.70;

  static const List<_PackBase> _packsBase = [
    _PackBase(
      nombre: 'Pack Prueba',
      creditos: 20,
      multiplicador: 1.00,
      vigenciaDias: 30,
      popular: false,
      descripcion: 'Ideal para probar Aura',
      equivalencia: '= 1 pilates + 1 yoga',
    ),
    _PackBase(
      nombre: 'Pack Esencial',
      creditos: 50,
      multiplicador: 0.95,
      vigenciaDias: 60,
      popular: false,
      descripcion: 'El pack base para usar durante el bimestre',
      equivalencia: '= 3 pilates + 1 yoga',
    ),
    _PackBase(
      nombre: 'Pack Popular',
      creditos: 100,
      multiplicador: 0.90,
      vigenciaDias: 60,
      popular: true,
      descripcion: 'El mas elegido para entrenar con frecuencia',
      equivalencia: '= 7 pilates + 1 ceramica',
    ),
    _PackBase(
      nombre: 'Pack Full',
      creditos: 200,
      multiplicador: 0.85,
      vigenciaDias: 60,
      popular: false,
      descripcion: 'La opcion mas conveniente para cargar saldo',
      equivalencia: '= todo lo anterior x2',
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

  /// Lee los creditos por categoria desde configuracion_global (JSON).
  Future<Map<String, int>> getCreditosPorCategoria() async {
    try {
      final res = await _client
          .from('configuracion_global')
          .select('valor')
          .eq('clave', 'creditos_por_categoria')
          .maybeSingle();
      final raw = res?['valor']?.toString();
      if (raw == null || raw.isEmpty) return _defaultCreditosPorCategoria();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _defaultCreditosPorCategoria();
      return decoded.map(
        (k, v) => MapEntry(k.toString(), (v is num) ? v.toInt() : 0),
      );
    } catch (_) {
      return _defaultCreditosPorCategoria();
    }
  }

  Map<String, int> _defaultCreditosPorCategoria() => {
        'Gym/Funcional': 10,
        'Pilates': 14,
        'Yoga': 18,
        'Ceramica + vino': 50,
      };

  /// Calcula el monto que recibe el estudio por una clase de N creditos.
  int montoEstudioPorClase(int valorCredito, int creditos) =>
      (valorCredito * creditos * _comisionEstudio).round();

  /// Devuelve los 4 packs canonicos con precio calculado.
  Future<List<Map<String, dynamic>>> getPacks() async {
    final valor = await getValorCreditoArs();
    return _packsBase.map((p) => p.toMap(valor)).toList();
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
  final bool popular;
  final String descripcion;
  final String equivalencia;

  const _PackBase({
    required this.nombre,
    required this.creditos,
    required this.multiplicador,
    required this.vigenciaDias,
    required this.popular,
    required this.descripcion,
    required this.equivalencia,
  });

  Map<String, dynamic> toMap(int valorCredito) => {
        'nombre': nombre,
        'creditos': creditos,
        'precio': (creditos * valorCredito * multiplicador).round(),
        'vigencia_dias': vigenciaDias,
        'popular': popular,
        'descripcion': descripcion,
        'equivalencia': equivalencia,
        'multiplicador': multiplicador,
      };
}
