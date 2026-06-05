import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
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

  /// Sign in with Apple.
  /// - iOS: flujo nativo (AuthenticationServices) + signInWithIdToken.
  ///   Devuelve true cuando hay sesión activa.
  /// - Web/Android: OAuth via redirect (mismo callback que Google).
  ///   Devuelve true si se abrió la pantalla externa.
  Future<bool> signInWithApple() async {
    if (!kIsWeb && Platform.isIOS) {
      final rawNonce = _supabase.auth.generateRawNonce();
      final hashedNonce =
          sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const AuthException(
            'No se pudo obtener el ID token de Apple');
      }

      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      // Apple sólo entrega el nombre la primera vez. Si vino, lo guardamos
      // en userMetadata para que ensureUsuarioCreado lo use.
      final fullName = [credential.givenName, credential.familyName]
          .whereType<String>()
          .where((p) => p.trim().isNotEmpty)
          .join(' ')
          .trim();
      if (fullName.isNotEmpty) {
        await _supabase.auth.updateUser(
          UserAttributes(data: {'full_name': fullName}),
        );
      }
      return true;
    }

    return _supabase.auth.signInWithOAuth(
      OAuthProvider.apple,
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
