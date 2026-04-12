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
  }
}
