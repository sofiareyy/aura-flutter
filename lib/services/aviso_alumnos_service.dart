import 'package:supabase_flutter/supabase_flutter.dart';

class AvisoAlumnosService {
  final _client = Supabase.instance.client;

  Future<int> contarAlumnosReservados(int claseId) async {
    try {
      final res = await _client
          .from('reservas')
          .select('id')
          .eq('clase_id', claseId)
          .inFilter('estado', ['confirmada', 'presente']);
      return (res as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> enviarAviso({
    required int claseId,
    required String mensaje,
    required String tipo,
    required String tituloEstudio,
  }) async {
    // 1. Log en notificaciones_estudio_alumnos
    await _client.from('notificaciones_estudio_alumnos').insert({
      'clase_id': claseId,
      'mensaje': mensaje,
      'tipo': tipo,
    });

    // 2. Obtener alumnos con reservas activas
    final reservas = await _client
        .from('reservas')
        .select('usuario_id')
        .eq('clase_id', claseId)
        .inFilter('estado', ['confirmada', 'presente']);

    final titulo = tipo == 'urgente'
        ? '🚨 $tituloEstudio — Aviso urgente'
        : '📢 $tituloEstudio';

    // 3. Insertar notificación por usuario (bulk)
    final inserts = (reservas as List)
        .map((r) => {
              'usuario_id': r['usuario_id'],
              'titulo': titulo,
              'mensaje': mensaje,
              'tipo': 'aviso_estudio',
              'leida': false,
            })
        .toList();

    if (inserts.isNotEmpty) {
      await _client.from('notificaciones_usuario').insert(inserts);
    }
  }

  Future<int> getUnreadCount() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return 0;
    try {
      final res = await _client
          .from('notificaciones_usuario')
          .select('id')
          .eq('usuario_id', uid)
          .eq('leida', false);
      return (res as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> getNotificaciones() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    final res = await _client
        .from('notificaciones_usuario')
        .select()
        .eq('usuario_id', uid)
        .order('created_at', ascending: false)
        .limit(30);
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<void> marcarTodasLeidas() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    await _client
        .from('notificaciones_usuario')
        .update({'leida': true})
        .eq('usuario_id', uid)
        .eq('leida', false);
  }
}
