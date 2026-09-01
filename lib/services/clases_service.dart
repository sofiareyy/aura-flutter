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

class ClasesService {
  final _supabase = Supabase.instance.client;

  /// [incluirExperiencias]: Explorar (E2, 1/9/2026) mezcla los workshops en
  /// el feed cronológico. El default en `false` es para Home, que tiene su
  /// sección de Experiencias aparte y las duplicaría.
  /// [diasVentana]: Explorar mira 60 días (una experiencia se anuncia con más
  /// anticipación que una clase); Home conserva sus 30.
  Future<List<Map<String, dynamic>>> getProximasClases({
    int limit = 20,
    int offset = 0,
    bool incluirExperiencias = false,
    int diasVentana = 30,
  }) async {
    final ahora = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    final semanasAdelante = ahora.add(Duration(days: diasVentana));
    var query = _supabase
        .from(AppConstants.tableClases)
        .select()
        // 2026-08-25: una clase cancelada por el estudio no se ofrece.
        .eq('cancelada', false);
    if (!incluirExperiencias) {
      // Los workshops van en su propia sección "Experiencias" (Home).
      query = query.neq('tipo', 'workshop');
    }
    final clases = await query
        .gte('fecha', _toSupaDate(ahora))
        .lte('fecha', _toSupaDate(semanasAdelante))
        .order('fecha', ascending: true)
        .range(offset, offset + limit - 1);
    final withEstudios =
        await _attachEstudios(List<Map<String, dynamic>>.from(clases as List));
    return _attachOcupacion(withEstudios);
  }

  /// Próximos workshops / eventos (tipo = 'workshop'), ordenados por fecha
  /// ascendente. Ventana más amplia porque los eventos suelen ser más lejanos.
  Future<List<Map<String, dynamic>>> getProximasExperiencias(
      {int limit = 20, int offset = 0}) async {
    final ahora = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    final hasta = ahora.add(const Duration(days: 90));
    final clases = await _supabase
        .from(AppConstants.tableClases)
        .select()
        .eq('tipo', 'workshop')
        .eq('cancelada', false)
        .gte('fecha', _toSupaDate(ahora))
        .lte('fecha', _toSupaDate(hasta))
        .order('fecha', ascending: true)
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

  Future<List<Map<String, dynamic>>> getClasesSugeridas({
    required String userId,
    int limit = 3,
  }) async {
    if (userId.isEmpty) return [];
    try {
      // Get user's last 5 reservations
      final reservas = await _supabase
          .from('reservas')
          .select('clase_id')
          .eq('usuario_id', userId)
          .neq('estado', 'cancelada')
          .order('created_at', ascending: false)
          .limit(5);
      final reservaList = List<Map<String, dynamic>>.from(reservas as List);
      if (reservaList.length < 2) return [];

      final claseIds = reservaList
          .map((r) => (r['clase_id'] as num?)?.toInt())
          .whereType<int>()
          .toList();

      // Get categories and studio IDs from those classes
      final clases = await _supabase
          .from('clases')
          .select('estudio_id, estudios(categoria, categorias)')
          .inFilter('id', claseIds);
      final clasesList = List<Map<String, dynamic>>.from(clases as List);

      final visitedEstudios = clasesList
          .map((c) => (c['estudio_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet()
          .toList();
      // Un estudio puede tener varias categorias: juntamos todas las de los
      // estudios visitados para recomendar sobre el set completo.
      final categorias = clasesList
          .expand((c) {
            final estudio = c['estudios'] as Map?;
            if (estudio == null) return const <String>[];
            return Estudio.parseCategorias(
                Map<String, dynamic>.from(estudio));
          })
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList();
      if (categorias.isEmpty) return [];

      // Query upcoming classes from those categories, excluding visited studios
      final ahora =
          DateTime.now().toUtc().subtract(const Duration(hours: 3));
      final hasta = ahora.add(const Duration(days: 30));
      final resultado = await _supabase
          .from('clases')
          .select(
              '*, estudios!inner(id, nombre, categoria, categorias, barrio, foto_url)')
          .eq('cancelada', false)
          .gte('fecha', _toSupaDate(ahora))
          .lte('fecha', _toSupaDate(hasta))
          // `overlaps` = el estudio comparte AL MENOS una categoria con las
          // que el usuario ya visitó.
          .overlaps('estudios.categorias', categorias)
          .order('fecha', ascending: true)
          .limit(limit * 3);
      final all = List<Map<String, dynamic>>.from(resultado as List);
      final filtered = all
          .where((c) {
            final esId = (c['estudio_id'] as num?)?.toInt();
            return esId != null && !visitedEstudios.contains(esId);
          })
          .take(limit)
          .toList();
      return _attachOcupacion(
          filtered.map((c) => {...c, 'estudios': c['estudios']}).toList());
    } catch (_) {
      return [];
    }
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
      final storedDisp = (c['lugares_disponibles'] as num?)?.toInt() ?? total;
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
