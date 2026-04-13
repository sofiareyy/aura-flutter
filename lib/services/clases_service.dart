import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/app_constants.dart';

String _toSupaDate(DateTime dt) {
  return '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:00';
}

class ClasesService {
  final _supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getProximasClases({int limit = 20, int offset = 0}) async {
    final ahora = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    final semanasAdelante = ahora.add(const Duration(days: 21));
    final clases = await _supabase
        .from(AppConstants.tableClases)
        .select()
        .gte('fecha', _toSupaDate(ahora))
        .lte('fecha', _toSupaDate(semanasAdelante))
        .order('fecha')
        .range(offset, offset + limit - 1);
    final withEstudios =
        await _attachEstudios(List<Map<String, dynamic>>.from(clases as List));
    return _attachOcupacion(withEstudios);
  }

  Future<Map<String, dynamic>?> getClase(int id) async {
    final data = await _supabase
        .from(AppConstants.tableClases)
        .select()
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;

    final estudio = await _supabase
        .from(AppConstants.tableEstudios)
        .select()
        .eq('id', data['estudio_id'])
        .maybeSingle();

    // Recalcular ocupación real desde reservas activas
    final withOcupacion = await _attachOcupacion([Map<String, dynamic>.from(data)]);
    return {...withOcupacion.first, 'estudios': estudio};
  }

  Future<List<Map<String, dynamic>>> getClasesUsuario(String userId) async {
    final reservas = await _supabase
        .from(AppConstants.tableReservas)
        .select()
        .eq('usuario_id', userId)
        .neq('estado', 'cancelada')
        .order('created_at', ascending: false);

    final result = <Map<String, dynamic>>[];
    for (final r in (reservas as List)) {
      final clase = await _supabase
          .from(AppConstants.tableClases)
          .select()
          .eq('id', r['clase_id'])
          .maybeSingle();
      if (clase != null) {
        final estudio = await _supabase
            .from(AppConstants.tableEstudios)
            .select()
            .eq('id', clase['estudio_id'])
            .maybeSingle();
        result.add({...r, 'clases': {...clase, 'estudios': estudio}});
      }
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> _attachEstudios(
      List<Map<String, dynamic>> clases) async {
    if (clases.isEmpty) return clases;

    final estudioIds = clases
        .map((c) => c['estudio_id'])
        .whereType<int>()
        .toSet()
        .toList();

    if (estudioIds.isEmpty) return clases;

    final estudios = await _supabase
        .from(AppConstants.tableEstudios)
        .select()
        .inFilter('id', estudioIds);

    final estudiosMap = {
      for (final e in (estudios as List)) e['id']: e,
    };

    return clases.map((c) {
      return {...c, 'estudios': estudiosMap[c['estudio_id']]};
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _attachOcupacion(
    List<Map<String, dynamic>> clases,
  ) async {
    if (clases.isEmpty) return clases;

    final classIds = clases
        .map((c) => (c['id'] as num?)?.toInt())
        .whereType<int>()
        .toList();
    if (classIds.isEmpty) return clases;

    final reservas = await _supabase
        .from(AppConstants.tableReservas)
        .select('clase_id')
        .inFilter('clase_id', classIds)
        .neq('estado', 'cancelada');

    final countByClass = <int, int>{};
    for (final row in (reservas as List)) {
      final classId = (row['clase_id'] as num?)?.toInt();
      if (classId == null) continue;
      countByClass[classId] = (countByClass[classId] ?? 0) + 1;
    }

    return clases.map((c) {
      final classId = (c['id'] as num?)?.toInt();
      final total = (c['lugares_total'] as num?)?.toInt() ?? 0;
      final storedDisp =
          (c['lugares_disponibles'] as num?)?.toInt() ??
          (c['lugares_ disponibles'] as num?)?.toInt() ??
          total;
      final storedOcupados = total > 0 ? (total - storedDisp) : 0;
      final reserved = classId != null ? (countByClass[classId] ?? 0) : 0;
      final ocupados = reserved > storedOcupados ? reserved : storedOcupados;
      final disponibles = total > 0 ? (total - ocupados).clamp(0, total) : storedDisp;

      return {
        ...c,
        'lugares_disponibles': disponibles,
        '_ocupados_real': ocupados,
      };
    }).toList();
  }
}
