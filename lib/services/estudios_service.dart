import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/app_constants.dart';
import '../models/estudio.dart';

String _toSupaDate(DateTime dt) {
  return '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:00';
}

class EstudiosService {
  final _supabase = Supabase.instance.client;

  Future<List<String>> getCategorias() async {
    try {
      final rows = await _supabase
          .from('study_categories')
          .select('nombre')
          .order('nombre');
      final categorias = (rows as List)
          .map((row) => (row as Map)['nombre']?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList();
      return ['Todos', ...categorias];
    } catch (_) {
      final rows = await _supabase
          .from(AppConstants.tableEstudios)
          .select('categoria')
          .not('categoria', 'is', null);
      final categorias = (rows as List)
          .map((row) => (row as Map)['categoria']?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      return ['Todos', ...categorias];
    }
  }

  Future<List<Estudio>> getEstudios({String? categoria}) async {
    var query =
        _supabase.from(AppConstants.tableEstudios).select();

    if (categoria != null && categoria != 'Todos') {
      query = query.eq('categoria', categoria) as dynamic;
    }

    final data = await query.order('nombre');
    return (data as List).map((e) => Estudio.fromMap(e)).toList();
  }

  Future<List<Estudio>> buscarEstudios(String query) async {
    final data = await _supabase
        .from(AppConstants.tableEstudios)
        .select()
        .or('nombre.ilike.%$query%,barrio.ilike.%$query%,categoria.ilike.%$query%')
        .order('nombre');
    return (data as List).map((e) => Estudio.fromMap(e)).toList();
  }

  Future<Estudio?> getEstudio(int id) async {
    final data = await _supabase
        .from(AppConstants.tableEstudios)
        .select()
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return Estudio.fromMap(data);
  }

  Future<Estudio?> getEstudioByNombre(String nombre) async {
    final data = await _supabase
        .from(AppConstants.tableEstudios)
        .select()
        .eq('nombre', nombre)
        .maybeSingle();
    if (data == null) return null;
    return Estudio.fromMap(data);
  }

  Future<List<Map<String, dynamic>>> getClasesDeEstudio(int estudioId) async {
    final ahora = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    final semanasAdelante = ahora.add(const Duration(days: 21));
    final data = await _supabase
        .from(AppConstants.tableClases)
        .select()
        .eq('estudio_id', estudioId)
        .gte('fecha', _toSupaDate(ahora))
        .lte('fecha', _toSupaDate(semanasAdelante))
        .order('fecha');

    final clases = List<Map<String, dynamic>>.from(data as List);
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
