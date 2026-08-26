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
      // Fallback: derivar las categorias de los propios estudios.
      final rows = await _supabase
          .from(AppConstants.tableEstudios)
          .select('categoria, categorias');
      final categorias = (rows as List)
          .expand((row) =>
              Estudio.parseCategorias(Map<String, dynamic>.from(row as Map)))
          .map((item) => item.trim())
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
      // `contains` sobre text[] = el estudio aparece si CUALQUIERA de sus
      // categorias matchea (antes era `.eq` sobre el escalar).
      query = query.contains('categorias', [categoria]) as dynamic;
    }

    final data = await query.order('nombre');
    return (data as List).map((e) => Estudio.fromMap(e)).toList();
  }

  Future<List<Estudio>> buscarEstudios(String query) async {
    // `ilike` no aplica sobre text[]; se busca por nombre/barrio en el server
    // y se filtra por categoria en memoria (el set de estudios es chico).
    final data = await _supabase
        .from(AppConstants.tableEstudios)
        .select()
        .or('nombre.ilike.%$query%,barrio.ilike.%$query%')
        .order('nombre');
    final porNombre = (data as List).map((e) => Estudio.fromMap(e)).toList();

    final todos = await _supabase
        .from(AppConstants.tableEstudios)
        .select()
        .order('nombre');
    final q = query.trim().toLowerCase();
    final porCategoria = (todos as List)
        .map((e) => Estudio.fromMap(e))
        .where((e) => e.categorias
            .any((c) => c.toLowerCase().contains(q)))
        .toList();

    final vistos = <int?>{};
    return [...porNombre, ...porCategoria]
        .where((e) => vistos.add(e.id))
        .toList();
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

  /// Clases regulares del estudio (sin experiencias) para los próximos 30 días.
  ///
  /// Los workshops quedan afuera a propósito: se listan aparte con
  /// [getExperienciasDeEstudio]. Antes venían mezclados y, como el perfil
  /// muestra solo las primeras clases por fecha, una experiencia con muchas
  /// clases semanales por delante quedaba enterrada e invisible.
  Future<List<Map<String, dynamic>>> getClasesDeEstudio(int estudioId) async {
    final ahora = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    final semanasAdelante = ahora.add(const Duration(days: 30));
    final data = await _supabase
        .from(AppConstants.tableClases)
        .select()
        .eq('estudio_id', estudioId)
        // 2026-08-25: las canceladas no se muestran a la alumna.
        .eq('cancelada', false)
        .neq('tipo', 'workshop')
        .gte('fecha', _toSupaDate(ahora))
        .lte('fecha', _toSupaDate(semanasAdelante))
        .order('fecha', ascending: true);

    return _conOcupacion(List<Map<String, dynamic>>.from(data as List));
  }

  /// Experiencias / workshops del estudio, hasta 90 días adelante.
  ///
  /// La ventana es más amplia que la de las clases porque un evento se publica
  /// con meses de anticipación. Es la misma que usa el home
  /// (`ClasesService.getProximasExperiencias`), así que lo que aparece en el
  /// inicio ahora también aparece en el perfil del estudio.
  Future<List<Map<String, dynamic>>> getExperienciasDeEstudio(
      int estudioId) async {
    final ahora = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    final hasta = ahora.add(const Duration(days: 90));
    final data = await _supabase
        .from(AppConstants.tableClases)
        .select()
        .eq('estudio_id', estudioId)
        .eq('cancelada', false)
        .eq('tipo', 'workshop')
        .gte('fecha', _toSupaDate(ahora))
        .lte('fecha', _toSupaDate(hasta))
        .order('fecha', ascending: true);

    return _conOcupacion(List<Map<String, dynamic>>.from(data as List));
  }

  /// Completa `lugares_disponibles` con las reservas reales. Se comparte entre
  /// clases y experiencias para no duplicar la lógica.
  Future<List<Map<String, dynamic>>> _conOcupacion(
      List<Map<String, dynamic>> clases) async {
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
