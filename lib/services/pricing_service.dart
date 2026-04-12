import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_constants.dart';

/// Servicio centralizado de pricing de Aura.
/// Lee de Supabase (pricing_credit_packs).
/// Si la tabla no existe o está vacía, usa los valores hardcodeados
/// de AppConstants como fallback.
class PricingService {
  final _client = Supabase.instance.client;

  Map<String, dynamic> _normalizePack(Map<String, dynamic> pack) {
    final creditos = (pack['creditos'] as num?)?.toInt();
    final nombre = switch (creditos) {
      20 => 'Pack Prueba',
      50 => 'Pack Esencial',
      100 => 'Pack Popular',
      200 => 'Pack Full',
      _ => pack['nombre']?.toString() ?? 'Pack',
    };
    return {
      ...pack,
      'nombre': nombre,
    };
  }

  int _packOrder(Map<String, dynamic> pack) {
    final creditos = (pack['creditos'] as num?)?.toInt();
    return switch (creditos) {
      20 => 0,
      50 => 1,
      100 => 2,
      200 => 3,
      _ => 99,
    };
  }

  Future<List<Map<String, dynamic>>> getPacks() async {
    try {
      final data = await _client
          .from('pricing_credit_packs')
          .select()
          .eq('activo', true)
          .order('orden');
      final list = List<Map<String, dynamic>>.from(data as List);
      if (list.isEmpty) return AppConstants.packsCreditos;

      final normalized = list.map(_normalizePack).toList();
      normalized.sort((a, b) => _packOrder(a).compareTo(_packOrder(b)));
      return normalized;
    } catch (_) {
      return AppConstants.packsCreditos;
    }
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


