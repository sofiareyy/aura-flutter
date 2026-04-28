import 'package:supabase_flutter/supabase_flutter.dart';

class ReferidosService {
  final _client = Supabase.instance.client;

  Future<String> obtenerOCrearCodigo(String usuarioId) async {
    try {
      final res = await _client.rpc(
        'ensure_referral_code',
        params: {'p_user_id': usuarioId},
      );
      final code = res?.toString().trim() ?? '';
      if (code.isNotEmpty) return code.toUpperCase();
    } catch (_) {
      // fallback abajo
    }
    return usuarioId.replaceAll('-', '').substring(0, 8).toUpperCase();
  }

  Future<void> aplicarCodigo({
    required String usuarioId,
    required String codigo,
  }) async {
    final res = await _client.rpc(
      'apply_referral_code',
      params: {
        'p_user_id': usuarioId,
        'p_code': codigo.trim().toUpperCase(),
      },
    );

    if (res is Map && res['ok'] == true) return;

    if (res is Map && res['error'] != null) {
      throw Exception(res['error'].toString());
    }

    throw Exception('No se pudo aplicar el código de referido.');
  }

  Future<String?> codigoYaUsado(String usuarioId) async {
    try {
      final data = await _client
          .from('usuarios')
          .select('codigo_referido_usado')
          .eq('id', usuarioId)
          .maybeSingle();
      return data?['codigo_referido_usado']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Devuelve cuántas personas se registraron usando el código de este usuario.
  /// Las columnas reales en `referrals` son `referrer_user_id` y `referred_user_id`
  /// (un nombre distinto al de la primera versión). Si la query falla por
  /// cualquier motivo (columna inexistente, RLS, sin referidos), devolvemos 0
  /// en lugar de propagar el error.
  Future<int> contarReferidos(String usuarioId) async {
    try {
      final rows = await _client
          .from('referrals')
          .select('referred_user_id')
          .eq('referrer_user_id', usuarioId);
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  /// Devuelve true si el usuario ya compró al menos un pack de créditos.
  Future<bool> haCompradoPack(String usuarioId) async {
    try {
      final rows = await _client
          .from('creditos_movimientos')
          .select('id')
          .eq('usuario_id', usuarioId)
          .eq('tipo', 'compra')
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
