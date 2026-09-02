import 'package:supabase_flutter/supabase_flutter.dart';

class ReviewsService {
  final _supabase = Supabase.instance.client;

  String get _userId => _supabase.auth.currentUser?.id ?? '';

  Future<List<Map<String, dynamic>>> getReviewsForStudy(int estudioId) async {
    final rows = await _supabase
        .from('study_reviews')
        .select('id, estudio_id, usuario_id, clase_id, experiencia_label, rating, comentario, created_at, usuarios(nombre, email)')
        .eq('estudio_id', estudioId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Página de reseñas de un estudio, más nuevas primero.
  ///
  /// La usan las DOS puntas: la alumna que toca el promedio y el estudio que
  /// entra desde su Dashboard. Es la misma lista — la policy
  /// `study_reviews_select_all` es pública porque las reseñas se muestran en
  /// el perfil, así que no hay nada que separar por rol.
  ///
  /// [rating] filtra por estrellas (null = todas). [offset]/[limit] paginan:
  /// con 100+ reseñas traerlas todas de una sería lento y no aporta.
  Future<List<Map<String, dynamic>>> getReviewsPage(
    int estudioId, {
    int? rating,
    int offset = 0,
    int limit = 20,
  }) async {
    var query = _supabase
        .from('study_reviews')
        .select('id, estudio_id, usuario_id, clase_id, experiencia_label, '
            'rating, comentario, created_at, updated_at, '
            'usuarios(nombre), clases(nombre, fecha)')
        .eq('estudio_id', estudioId);
    if (rating != null) query = query.eq('rating', rating);
    final rows = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Cuántas reseñas hay por cada puntaje: alimenta el desglose de barras y
  /// el promedio, sin traer las reseñas enteras.
  Future<Map<int, int>> getRatingBreakdown(int estudioId) async {
    final rows = await _supabase
        .from('study_reviews')
        .select('rating')
        .eq('estudio_id', estudioId);
    final out = {for (var i = 1; i <= 5; i++) i: 0};
    for (final r in (rows as List)) {
      final v = (r['rating'] as num?)?.toInt();
      if (v != null && v >= 1 && v <= 5) out[v] = out[v]! + 1;
    }
    return out;
  }

  Future<Map<String, dynamic>?> getMyReviewForStudy(int estudioId) async {
    if (_userId.isEmpty) return null;
    final row = await _supabase
        .from('study_reviews')
        .select('id, estudio_id, usuario_id, clase_id, experiencia_label, rating, comentario, created_at')
        .eq('estudio_id', estudioId)
        .eq('usuario_id', _userId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<bool> canReviewStudy({
    required int estudioId,
    int? claseId,
  }) async {
    if (_userId.isEmpty) return false;

    final reservas = await _supabase
        .from('reservas')
        .select('id, estado, clase_id, created_at')
        .eq('usuario_id', _userId)
        .neq('estado', 'cancelada');

    final reservaList = List<Map<String, dynamic>>.from(reservas as List);
    if (reservaList.isEmpty) return false;

    final classIds = reservaList
        .map((row) => (row['clase_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .toList();
    if (classIds.isEmpty) return false;

    var clasesQuery = _supabase
        .from('clases')
        .select('id, estudio_id, fecha')
        .inFilter('id', classIds)
        .eq('estudio_id', estudioId);

    if (claseId != null) {
      clasesQuery = clasesQuery.eq('id', claseId) as dynamic;
    }

    final clases = await clasesQuery;
    final now = DateTime.now();
    for (final row in (clases as List)) {
      final fecha = DateTime.tryParse(row['fecha']?.toString() ?? '');
      if (fecha != null && fecha.isBefore(now)) {
        return true;
      }
    }
    return false;
  }

  Future<void> upsertStudyReview({
    required int estudioId,
    int? claseId,
    String? experienciaLabel,
    required int rating,
    required String comentario,
  }) async {
    if (_userId.isEmpty) throw Exception('Necesitás iniciar sesión.');

    await _supabase.from('study_reviews').upsert({
      'estudio_id': estudioId,
      'usuario_id': _userId,
      'clase_id': claseId,
      'experiencia_label': experienciaLabel,
      'rating': rating,
      'comentario': comentario.trim(),
    }, onConflict: 'estudio_id,usuario_id');

    // Recalcular rating promedio del estudio
    try {
      final ratings = await _supabase
          .from('study_reviews')
          .select('rating')
          .eq('estudio_id', estudioId);
      final list = (ratings as List);
      if (list.isNotEmpty) {
        final avg = list
                .map((r) => (r['rating'] as num).toDouble())
                .reduce((a, b) => a + b) /
            list.length;
        await _supabase
            .from('estudios')
            .update({'rating': avg}).eq('id', estudioId);
      }
    } catch (_) {}
  }
}
