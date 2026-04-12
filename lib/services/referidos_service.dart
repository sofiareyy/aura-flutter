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
  Future<int> contarReferidos(String usuarioId) async {
    try {
      final rows = await _client
          .from('referrals')
          .select('referred_id')
          .eq('referrer_id', usuarioId);
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }
}
