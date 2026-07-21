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

  /// Envía un aviso del estudio a las alumnas con reserva activa.
  ///
  /// La notificación in-app se inserta para todas: es pasiva, vive dentro de
  /// la app que ya usan, y silenciarla podría ocultarles que su clase se
  /// canceló. El email de respaldo (FIX 7) solo sale para `tipo == 'urgente'`
  /// y solo a quienes tienen `notifs_reservas = true` — ese filtro lo aplica
  /// la Edge Function, que es la única que puede leer los emails.
  ///
  /// Devuelve la cantidad de emails enviados (0 si no era urgente o si el
  /// envío falló; el aviso in-app se guarda igual).
  Future<int> enviarAviso({
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

    // 4. Email de respaldo (solo urgentes). No bloquea ni revierte el aviso
    // in-app: si Resend falla, el aviso ya quedó guardado igual.
    if (tipo == 'urgente' && inserts.isNotEmpty) {
      return _enviarEmailRespaldo(claseId: claseId, mensaje: mensaje);
    }
    return 0;
  }

  Future<int> _enviarEmailRespaldo({
    required int claseId,
    required String mensaje,
  }) async {
    try {
      final jwt = _client.auth.currentSession?.accessToken ?? '';
      if (jwt.isEmpty) return 0;

      final res = await _client.functions.invoke(
        'aviso-alumnos-email',
        headers: {'x-aura-auth': jwt},
        body: {
          'clase_id': claseId,
          'mensaje': mensaje,
          'tipo': 'urgente',
        },
      );
      if (res.status != 200) return 0;
      final data = res.data;
      if (data is Map) {
        return (data['enviados'] as num?)?.toInt() ?? 0;
      }
      return 0;
    } catch (_) {
      return 0;
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
