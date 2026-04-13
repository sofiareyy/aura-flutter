import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/app_constants.dart';
import '../models/usuario.dart';

class UsuariosService {
  final _supabase = Supabase.instance.client;

  Future<Usuario?> getUsuario(String id) async {
    try {
      await _supabase.rpc('refresh_user_credit_balance', params: {'p_user_id': id});
    } catch (_) {
      // Compatibilidad temporal: si la RPC todavía no existe, seguimos igual.
    }

    final data = await _supabase
        .from(AppConstants.tableUsuarios)
        .select()
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return Usuario.fromMap({...data, 'id': id});
  }

  /// Crea la fila en `usuarios` si todavía no existe.
  /// El trigger de Supabase debería crearla en auth.users INSERT,
  /// pero este método es la red de seguridad desde Flutter.
  /// Usa upsert con ignoreDuplicates para que sea idempotente.
  Future<void> crearUsuarioSiNoExiste(String uid) async {
    try {
      final authUser = Supabase.instance.client.auth.currentUser;
      if (authUser == null || authUser.id != uid) return;
      final nombre = (authUser.userMetadata?['nombre'] as String?)?.trim() ?? '';
      final email = authUser.email ?? '';
      await _supabase.from(AppConstants.tableUsuarios).upsert(
        {
          'id': uid,
          'nombre': nombre.isNotEmpty ? nombre : email.split('@').first,
          'email': email,
          'creditos': 0,
        },
        onConflict: 'id',
        ignoreDuplicates: true,
      );
    } catch (_) {
      // Silenciar — el trigger de Supabase es la fuente de verdad.
    }
  }

  Future<void> updateUsuario(String id, Map<String, dynamic> updates) async {
    await _supabase
        .from(AppConstants.tableUsuarios)
        .update(updates)
        .eq('id', id);
  }

  Future<bool> descontarCreditos(String userId, int cantidad) async {
    try {
      final res = await _supabase.rpc(
        'consume_user_credits',
        params: {'p_user_id': userId, 'p_amount': cantidad},
      );
      return res == true;
    } catch (_) {
      final usuario = await getUsuario(userId);
      if (usuario == null || usuario.creditos < cantidad) return false;

      await _supabase
          .from(AppConstants.tableUsuarios)
          .update({'creditos': usuario.creditos - cantidad}).eq('id', userId);
      return true;
    }
  }

  Future<void> agregarCreditos(String userId, int cantidad) async {
    try {
      await _supabase.rpc(
        'grant_user_credits',
        params: {
          'p_user_id': userId,
          'p_amount': cantidad,
          'p_source': 'manual',
        },
      );
    } catch (_) {
      final usuario = await getUsuario(userId);
      if (usuario == null) return;

      await _supabase
          .from(AppConstants.tableUsuarios)
          .update({'creditos': usuario.creditos + cantidad}).eq('id', userId);
    }
  }

  Map<String, String> _authHeaders() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) return const {};
    return {'x-aura-auth': token};
  }

  /// Llama a la Edge Function `crear-checkout-pack`.
  /// Devuelve { init_point, preference_id, pago_id } o lanza excepción.
  Future<Map<String, dynamic>> crearCheckoutPack({
    required String packNombre,
    required int creditos,
    required int amount,
    int? vigenciaDias,
  }) async {
    final res = await _supabase.functions.invoke(
      'crear-checkout-pack',
      headers: _authHeaders(),
      body: {
        'pack_nombre': packNombre,
        'creditos': creditos,
        'amount': amount,
        'vigencia_dias': vigenciaDias,
        'platform': kIsWeb ? 'web' : 'mobile',
      },
    );
    if (res.status != 200) {
      final msg = (res.data as Map<String, dynamic>?)?['error']
          ?? 'Error al crear checkout del pack';
      throw Exception(msg);
    }
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> crearCheckoutPlan({
    required String planNombre,
    required int planCreditos,
    required int planPrecio,
  }) async {
    final res = await _supabase.functions.invoke(
      'crear-checkout-plan',
      headers: _authHeaders(),
      body: {
        'plan_nombre': planNombre,
        'plan_creditos': planCreditos,
        'plan_precio': planPrecio,
        'platform': kIsWeb ? 'web' : 'mobile',
      },
    );
    if (res.status != 200) {
      final msg = (res.data as Map<String, dynamic>?)?['error'] ??
          'Error al crear checkout del plan';
      throw Exception(msg);
    }
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Consulta el estado de un pago por su UUID interno.
  /// Devuelve el status: 'pending' | 'approved' | 'rejected' | 'cancelled' | 'in_process'
  Future<String?> getPagoStatus(String pagoId) async {
    final data = await _supabase
        .from('pagos')
        .select('status')
        .eq('id', pagoId)
        .maybeSingle();
    return data?['status'] as String?;
  }

  Future<String?> confirmarPagoManual({
    String? pagoId,
    String? paymentId,
  }) async {
    final res = await _supabase.functions.invoke(
      'confirmar-pago-manual',
      headers: _authHeaders(),
      body: {
        if (pagoId != null && pagoId.isNotEmpty) 'pago_id': pagoId,
        if (paymentId != null && paymentId.isNotEmpty) 'payment_id': paymentId,
      },
    );

    if (res.status != 200) {
      final msg = (res.data as Map<String, dynamic>?)?['error'] ??
          'Error al confirmar el pago';
      throw Exception(msg);
    }

    return (res.data as Map<String, dynamic>?)?['status'] as String?;
  }

  Future<void> cancelarSuscripcion() async {
    final res = await _supabase.functions.invoke(
      'cancelar-suscripcion',
      headers: _authHeaders(),
    );

    if (res.status != 200) {
      final msg = (res.data as Map<String, dynamic>?)?['error'] ??
          'No se pudo cancelar la suscripción';
      throw Exception(msg);
    }
  }
}
