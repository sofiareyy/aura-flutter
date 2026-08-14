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
        // Embed empresas(nombre) para el badge "Beneficio [Empresa]".
        .select('*, empresas(nombre)')
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
      final meta = authUser.userMetadata ?? {};

      // Email con fallbacks: Apple solo devuelve el email la PRIMERA vez que
      // el usuario autoriza la app; en reintentos viene null. Sin fallback el
      // insert quedaba con email '' (o fallaba) y la fila no se creaba.
      final email = (authUser.email ??
              meta['email']?.toString() ??
              '${authUser.id}@privaterelay.appleid.com')
          .trim();

      var nombre = (meta['nombre'] ??
              meta['full_name'] ??
              meta['name'] ??
              email.split('@').first)
          .toString()
          .trim();
      if (nombre.isEmpty) nombre = 'Usuario';

      await _supabase.from(AppConstants.tableUsuarios).upsert(
        {
          'id': uid,
          'nombre': nombre,
          'email': email,
          'rol': 'usuario',
          'creditos': 0,
        },
        onConflict: 'id',
        ignoreDuplicates: true,
      );
    } on PostgrestException catch (e) {
      // Antes se silenciaba todo. Ahora logueamos el error real de Postgres
      // (RLS, NOT NULL, etc.) para poder diagnosticar fallos de alta.
      debugPrint('[crearUsuarioSiNoExiste] PostgrestException '
          'code=${e.code} message=${e.message} '
          'details=${e.details} hint=${e.hint}');
    } catch (e) {
      debugPrint('[crearUsuarioSiNoExiste] error inesperado: $e');
    }
  }

  Future<void> updateUsuario(String id, Map<String, dynamic> updates) async {
    await _supabase
        .from(AppConstants.tableUsuarios)
        .update(updates)
        .eq('id', id);
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
    // Gift card: si vienen, el pago se marca type='gift' y al aprobarse se crea
    // el regalo y se mailea al destinatario en vez de acreditar al comprador.
    String? giftEmail,
    String? giftMensaje,
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
        if (giftEmail != null && giftEmail.trim().isNotEmpty)
          'gift_email': giftEmail.trim(),
        if (giftMensaje != null && giftMensaje.trim().isNotEmpty)
          'gift_mensaje': giftMensaje.trim(),
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
