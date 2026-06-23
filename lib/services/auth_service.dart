import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
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

  /// Login NATIVO con Apple (iOS). Usa la hoja nativa de Sign in with Apple y
  /// canjea el id_token directamente con Supabase (signInWithIdToken), sin
  /// navegador ni redirect. Evita el problema del flujo OAuth web por
  /// SFSafariViewController (que no podía volver a la app por aura://) y no
  /// depende del client secret web de Apple.
  ///
  /// Requisito en Supabase: el proveedor Apple debe tener el bundle id
  /// `app.somosaura.aura` en los Client IDs autorizados.
  Future<AuthResponse> signInWithAppleNative() async {
    // Nonce: el crudo se manda a Supabase; el hasheado (sha256) a Apple.
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw const AuthException('No se recibió el token de identidad de Apple.');
    }

    final response = await _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );

    // El nombre solo lo manda Apple la PRIMERA vez que el usuario autoriza.
    // Lo guardamos en la metadata para que ensureUsuarioCreado lo use.
    final fullName = [credential.givenName, credential.familyName]
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .join(' ');
    if (fullName.isNotEmpty) {
      try {
        await _supabase.auth.updateUser(
          UserAttributes(data: {'full_name': fullName}),
        );
      } catch (_) {
        // No crítico: si falla, ensureUsuarioCreado cae al fallback de nombre.
      }
    }

    return response;
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
        length, (_) => charset[random.nextInt(charset.length)]).join();
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
  /// Si no existe (OAuth por primera vez con Google o Apple), lo crea con
  /// los datos disponibles del perfil. Devuelve el rol del usuario.
  ///
  /// Importante (Apple): Apple solo devuelve el email la PRIMERA vez que el
  /// usuario autoriza la app. En reintentos / re-autorizaciones `user.email`
  /// puede venir null, lo que antes hacía fallar el insert (columna email
  /// NOT NULL) y dejaba el registro a medias. Por eso resolvemos el email
  /// con varios fallbacks antes de insertar.
  Future<String> ensureUsuarioCreado() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Sin sesión activa');

    // --- Logs de diagnóstico OAuth (Apple/Google) ---
    // Apple solo devuelve el email la PRIMERA vez que el usuario autoriza la
    // app; en reintentos user.email viene null. Estos logs permiten ver en
    // consola (flutter logs / Xcode) qué llega exactamente.
    debugPrint('[ensureUsuarioCreado] provider: '
        '${user.appMetadata['provider'] ?? user.appMetadata['providers']}');
    debugPrint('[ensureUsuarioCreado] user id: ${user.id}');
    debugPrint('[ensureUsuarioCreado] user email: ${user.email}');
    debugPrint('[ensureUsuarioCreado] user metadata: ${user.userMetadata}');

    final existing = await _supabase
        .from('usuarios')
        .select('rol')
        .eq('id', user.id)
        .maybeSingle();

    if (existing != null) {
      debugPrint('[ensureUsuarioCreado] fila ya existe, rol=${existing['rol']}');
      return existing['rol']?.toString() ?? 'usuario';
    }

    // Primera vez con OAuth: crear fila en usuarios.
    final meta = user.userMetadata ?? {};

    // Email con fallbacks: sesión -> metadata -> relay privado de Apple.
    final email = (user.email ??
            meta['email']?.toString() ??
            '${user.id}@privaterelay.appleid.com')
        .trim();

    // Nombre con fallbacks (Apple a veces solo manda full_name la 1ra vez).
    var nombre = (meta['full_name'] ??
            meta['name'] ??
            meta['nombre'] ??
            email.split('@').first)
        .toString()
        .trim();
    if (nombre.isEmpty) nombre = 'Usuario';

    debugPrint('[ensureUsuarioCreado] insertando usuario: '
        'id=${user.id} email=$email nombre=$nombre');

    try {
      await _supabase.from('usuarios').insert({
        'id': user.id,
        'email': email,
        'nombre': nombre,
        'rol': 'usuario',
        'creditos': 0,
      });
      debugPrint('[ensureUsuarioCreado] insert OK');
    } on PostgrestException catch (e) {
      // Log COMPLETO del error real de Postgres para diagnosticar
      // (RLS, NOT NULL, FK, etc.). Sin esto el error queda oculto.
      debugPrint('[ensureUsuarioCreado] PostgrestException '
          'code=${e.code} message=${e.message} '
          'details=${e.details} hint=${e.hint}');

      // 23505 = unique_violation: la fila ya fue creada por otra ruta
      // (carrera entre el splash y el deep link de OAuth). No es un error
      // real: releemos el rol y seguimos.
      if (e.code == '23505') {
        final row = await _supabase
            .from('usuarios')
            .select('rol')
            .eq('id', user.id)
            .maybeSingle();
        return row?['rol']?.toString() ?? 'usuario';
      }
      throw Exception(
          'No pudimos completar tu registro. Intentá de nuevo o usá otro método de inicio de sesión.');
    } catch (e, st) {
      debugPrint('[ensureUsuarioCreado] error inesperado: $e\n$st');
      throw Exception(
          'No pudimos completar tu registro. Intentá de nuevo o usá otro método de inicio de sesión.');
    }

    return 'usuario';
  }
}
