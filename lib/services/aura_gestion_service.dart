import 'package:supabase_flutter/supabase_flutter.dart';

class AuraGestionService {
  final _supabase = Supabase.instance.client;

  // ── Alumnos ───────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listarAlumnos(int estudioId) async {
    final rows = await _supabase
        .from('estudio_alumnos')
        .select()
        .eq('estudio_id', estudioId)
        .order('nombre');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<void> agregarAlumno({
    required int estudioId,
    required String email,
    required String nombre,
  }) async {
    final emailLimpio = email.trim().toLowerCase();
    if (emailLimpio.isEmpty) throw Exception('El email no puede estar vacío.');

    await _supabase.from('estudio_alumnos').insert({
      'estudio_id': estudioId,
      'email': emailLimpio,
      'nombre': nombre.trim(),
      'activo': true,
    });
  }

  Future<void> eliminarAlumno({
    required int estudioId,
    required int alumnoId,
  }) async {
    await _supabase
        .from('estudio_alumnos')
        .delete()
        .eq('id', alumnoId)
        .eq('estudio_id', estudioId);
  }

  Future<void> toggleAlumnoActivo({
    required int estudioId,
    required int alumnoId,
    required bool activo,
  }) async {
    await _supabase
        .from('estudio_alumnos')
        .update({'activo': activo})
        .eq('id', alumnoId)
        .eq('estudio_id', estudioId);
  }

  /// Devuelve true si el email del usuario está en la lista de alumnos
  /// activos del estudio al que pertenece la clase.
  Future<bool> esAlumnoDirecto({
    required int estudioId,
    required String userEmail,
  }) async {
    try {
      final row = await _supabase
          .from('estudio_alumnos')
          .select('id')
          .eq('estudio_id', estudioId)
          .eq('email', userEmail.trim().toLowerCase())
          .eq('activo', true)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }

  // ── Modo del estudio ──────────────────────────────────────

  /// Devuelve el modo del estudio: 'marketplace' o 'gestion'.
  /// Si la columna no existe o falla, retorna 'marketplace' como fallback.
  Future<String> getModoEstudio(int estudioId) async {
    try {
      final row = await _supabase
          .from('estudios')
          .select('modo')
          .eq('id', estudioId)
          .maybeSingle();
      return row?['modo']?.toString() ?? 'marketplace';
    } catch (_) {
      return 'marketplace';
    }
  }

  Future<void> cambiarModoEstudio({
    required int estudioId,
    required String modo,
  }) async {
    assert(modo == 'marketplace' || modo == 'gestion',
        'modo debe ser "marketplace" o "gestion"');
    await _supabase
        .from('estudios')
        .update({'modo': modo})
        .eq('id', estudioId);
  }

  /// Dado un clase_id, devuelve el estudio_id de esa clase.
  Future<int?> getEstudioIdDeClase(int claseId) async {
    final row = await _supabase
        .from('clases')
        .select('estudio_id')
        .eq('id', claseId)
        .maybeSingle();
    return (row?['estudio_id'] as num?)?.toInt();
  }

  /// Combina getModoEstudio + esAlumnoDirecto en una sola llamada útil
  /// para decidir si una reserva debe costar créditos o no.
  ///
  /// Retorna true si la reserva debe ser gratuita (estudio en modo gestión
  /// Y el usuario es alumno directo de ese estudio).
  Future<bool> reservaEsGratuita({
    required int claseId,
    required String userEmail,
  }) async {
    try {
      final estudioId = await getEstudioIdDeClase(claseId);
      if (estudioId == null) return false;

      final modo = await getModoEstudio(estudioId);
      if (modo != 'gestion') return false;

      return esAlumnoDirecto(estudioId: estudioId, userEmail: userEmail);
    } catch (_) {
      return false;
    }
  }
}
