import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class AuthService {
  final _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  Stream<AuthState> get authStateChanges =>
      _supabase.auth.onAuthStateChange;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String nombre,
  }) async {
    return await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'nombre': nombre,
      },
    );
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  Future<bool> signInWithGoogle() async {
    return _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb
          ? 'https://somosauraar.netlify.app'
          : 'aura://login-callback',
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.inAppWebView,
    );
  }

  Future<bool> signInWithApple() async {
    return _supabase.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: kIsWeb
          ? 'https://somosauraar.netlify.app'
          : 'aura://login-callback',
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.inAppWebView,
    );
  }

  /// Detecta si el usuario logueado es admin de al menos un estudio
  /// (esta presente en estudio_admins). Lo usamos para mostrar la
  /// advertencia extra al eliminar la cuenta.
  Future<bool> esAdminDeEstudio() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    try {
      final rows = await _supabase
          .from('estudio_admins')
          .select('estudio_id')
          .eq('usuario_id', user.id)
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Invoca la Edge Function delete-account, que devuelve creditos,
  /// cancela reservas / clases, borra datos en public.* y elimina el
  /// usuario de auth.users con service role. Si OK, hace signOut.
  Future<void> eliminarCuenta() async {
    final session = _supabase.auth.currentSession;
    final token = session?.accessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Sesión expirada. Volvé a iniciar sesión.');
    }

    final res = await _supabase.functions.invoke(
      'delete-account',
      headers: {'x-aura-auth': token},
    );

    if (res.status != 200) {
      final data = res.data;
      String? msg;
      if (data is Map) {
        msg = data['error']?.toString();
      }
      throw Exception(msg ?? 'No se pudo eliminar la cuenta');
    }

    // Cierre de sesion local. La sesion ya no es valida porque el usuario
    // de auth ya no existe; signOut limpia el storage del cliente.
    await _supabase.auth.signOut();
  }

  /// Verifica si el usuario existe en la tabla `usuarios`.
  /// Si no existe (OAuth por primera vez), lo crea con datos del perfil de Google.
  /// Devuelve el rol del usuario.
  Future<String> ensureUsuarioCreado() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Sin sesión activa');

    final existing = await _supabase
        .from('usuarios')
        .select('rol')
        .eq('id', user.id)
        .maybeSingle();

    if (existing != null) {
      return existing['rol']?.toString() ?? 'usuario';
    }

    // Primera vez con OAuth: crear fila en usuarios
    final meta = user.userMetadata ?? {};
    final nombre = (meta['full_name'] ?? meta['name'] ?? user.email?.split('@').first ?? 'Usuario').toString().trim();

    await _supabase.from('usuarios').insert({
      'id': user.id,
      'email': user.email,
      'nombre': nombre,
      'rol': 'usuario',
      'creditos': 0,
    });

    return 'usuario';
  }
}
