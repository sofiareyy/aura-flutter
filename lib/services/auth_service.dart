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
          : LaunchMode.externalApplication,
    );
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
