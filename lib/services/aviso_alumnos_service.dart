import 'package:supabase_flutter/supabase_flutter.dart';

/// Resultado de intentar enviar un aviso.
class ResultadoAviso {
  final bool ok;

  /// True cuando el estudio agotó su cupo mensual de avisos generales.
  final bool limiteMensual;

  final int destinatarios;
  final int emailsEnviados;
  final String? error;

  /// Cupo mensual tras el envío: `{max, usados, restantes, reinicia}`.
  final Map<String, dynamic>? cupo;

  const ResultadoAviso({
    required this.ok,
    this.limiteMensual = false,
    this.destinatarios = 0,
    this.emailsEnviados = 0,
    this.error,
    this.cupo,
  });
}

class AvisoAlumnosService {
  final _client = Supabase.instance.client;

  /// Tope de clases por envío. Espejado en `enviar_aviso_estudio`.
  static const int maxClasesPorEnvio = 10;

  /// Cuenta alumnas con reserva CONFIRMADA. Es el universo real de
  /// destinatarios: quien canceló o ya asistió no recibe el aviso.
  Future<int> contarAlumnosReservados(int claseId) =>
      contarAlumnosDeClases([claseId]);

  /// Igual que [contarAlumnosReservados] pero para varias clases, sin contar
  /// dos veces a quien está anotada en más de una.
  Future<int> contarAlumnosDeClases(List<int> claseIds) async {
    if (claseIds.isEmpty) return 0;
    try {
      final res = await _client
          .from('reservas')
          .select('usuario_id')
          .inFilter('clase_id', claseIds)
          .eq('estado', 'confirmada');
      return (res as List)
          .map((r) => r['usuario_id']?.toString())
          .whereType<String>()
          .toSet()
          .length;
    } catch (_) {
      return 0;
    }
  }

  /// Cupo mensual de avisos generales del estudio.
  /// Devuelve `{max, usados, restantes, reinicia}`.
  Future<Map<String, dynamic>?> cupoMensual(int estudioId) async {
    try {
      final res = await _client.rpc(
        'avisos_generales_restantes',
        params: {'p_estudio_id': estudioId},
      );
      return res is Map ? Map<String, dynamic>.from(res) : null;
    } catch (_) {
      return null;
    }
  }

  /// Envía un aviso a las alumnas confirmadas de una o varias clases.
  ///
  /// Toda la lógica vive en el RPC `enviar_aviso_estudio`: valida permisos,
  /// aplica el tope mensual, deduplica destinatarios y decide a quién le
  /// corresponde canal externo según el tope diario por usuario. Se hace
  /// server-side a propósito — desde el cliente los topes serían salteables.
  Future<ResultadoAviso> enviarAviso({
    required List<int> claseIds,
    required String mensaje,
    required String tipo,
  }) async {
    if (claseIds.isEmpty) {
      return const ResultadoAviso(ok: false, error: 'Elegí al menos una clase');
    }
    if (claseIds.length > maxClasesPorEnvio) {
      return const ResultadoAviso(
        ok: false,
        error: 'Máximo $maxClasesPorEnvio clases por envío',
      );
    }

    try {
      final res = await _client.rpc(
        'enviar_aviso_estudio',
        params: {
          'p_clase_ids': claseIds,
          'p_mensaje': mensaje.trim(),
          'p_tipo': tipo,
        },
      );
      final map = res is Map ? Map<String, dynamic>.from(res) : {};

      if (map['ok'] != true) {
        final err = map['error']?.toString();
        return ResultadoAviso(
          ok: false,
          limiteMensual: err == 'limite_mensual',
          error: err,
          cupo: map['cupo'] is Map
              ? Map<String, dynamic>.from(map['cupo'] as Map)
              : null,
        );
      }

      final avisoId = (map['aviso_id'] as num?)?.toInt();
      final destinatarios = (map['destinatarios'] as num?)?.toInt() ?? 0;

      // El email solo sale para urgentes. No bloquea ni revierte: el aviso
      // in-app ya quedó guardado aunque Resend falle.
      var emails = 0;
      if (tipo == 'urgente' && avisoId != null && destinatarios > 0) {
        emails = await _enviarEmailRespaldo(avisoId);
      }

      return ResultadoAviso(
        ok: true,
        destinatarios: destinatarios,
        emailsEnviados: emails,
        cupo: map['cupo'] is Map
            ? Map<String, dynamic>.from(map['cupo'] as Map)
            : null,
      );
    } catch (e) {
      return ResultadoAviso(
        ok: false,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<int> _enviarEmailRespaldo(int avisoId) async {
    try {
      final jwt = _client.auth.currentSession?.accessToken ?? '';
      if (jwt.isEmpty) return 0;

      final res = await _client.functions.invoke(
        'aviso-alumnos-email',
        headers: {'x-aura-auth': jwt},
        body: {'aviso_id': avisoId},
      );
      if (res.status != 200) return 0;
      final data = res.data;
      return data is Map ? ((data['enviados'] as num?)?.toInt() ?? 0) : 0;
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
