import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_constants.dart';

class NotificacionesEstudioService {
  static final NotificacionesEstudioService instance =
      NotificacionesEstudioService._();
  NotificacionesEstudioService._();

  final _supabase = Supabase.instance.client;

  /// Inserts a "nueva_reserva" notification for a studio.
  /// Fully non-blocking — silently swallows errors so it never breaks reservations.
  Future<void> insertarNuevaReserva({
    required int estudioId,
    required String claseNombre,
    required String usuarioNombre,
    required int claseId,
  }) async {
    try {
      await _supabase.from(AppConstants.tableNotificacionesEstudio).insert({
        'estudio_id': estudioId,
        'tipo': 'nueva_reserva',
        'mensaje': '$usuarioNombre reservó "$claseNombre"',
        'metadata': {'clase_id': claseId, 'usuario_nombre': usuarioNombre},
        'leida': false,
      });
    } catch (_) {
      // Non-critical.
    }
  }

  Future<List<Map<String, dynamic>>> getNotificaciones(
    int estudioId, {
    int limit = 30,
  }) async {
    final rows = await _supabase
        .from(AppConstants.tableNotificacionesEstudio)
        .select()
        .eq('estudio_id', estudioId)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<int> getUnreadCount(int estudioId) async {
    final rows = await _supabase
        .from(AppConstants.tableNotificacionesEstudio)
        .select('id')
        .eq('estudio_id', estudioId)
        .eq('leida', false);
    return (rows as List).length;
  }

  Future<void> marcarTodasLeidas(int estudioId) async {
    await _supabase
        .from(AppConstants.tableNotificacionesEstudio)
        .update({'leida': true})
        .eq('estudio_id', estudioId)
        .eq('leida', false);
  }
}
