import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/app_provider.dart';
import 'services/auth_service.dart';
import 'services/notificaciones_service.dart';
import 'widgets/connectivity_banner.dart';

/// Key global del ScaffoldMessenger para poder mostrar SnackBars desde fuera
/// del árbol de un Scaffold (p. ej. al fallar el alta tras un callback OAuth).
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('es', null);

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  await NotificacionesService.instance.initialize();

  // Sentry: solo activo en producción (DSN vacío = sin reportes en dev/test)
  final sentryDsn = AppConstants.sentryDsn;
  final sentryEnabled = !kDebugMode &&
      sentryDsn.isNotEmpty &&
      !sentryDsn.startsWith('REEMPLAZAR');

  if (sentryEnabled) {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        options.environment = 'production';
        // Captura el 20 % de transacciones para performance monitoring
        options.tracesSampleRate = 0.2;
        // Adjunta el stack trace incluso para errores no-exception
        options.attachStacktrace = true;
      },
      appRunner: () => _runApp(),
    );
  } else {
    _runApp();
  }
}

void _runApp() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppProvider(),
      child: const AuraApp(),
    ),
  );
}

class AuraApp extends StatefulWidget {
  const AuraApp({super.key});

  @override
  State<AuraApp> createState() => _AuraAppState();
}

class _AuraAppState extends State<AuraApp> {
  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<AuthState>? _authSub;
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _initAuthListener();
    if (!kIsWeb) {
      _initDeepLinks();
      _initNotificationHandlers();
    }
  }

  /// Garantiza que la fila en `usuarios` exista después de CUALQUIER inicio
  /// de sesión (Google, Apple o email). Es la red de seguridad central: aun
  /// si el flujo específico no la creó, este listener lo hace. Es idempotente
  /// (ensureUsuarioCreado relee si ya existe y maneja la carrera).
  void _initAuthListener() {
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) async {
        final event = data.event;
        if (event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.userUpdated ||
            event == AuthChangeEvent.initialSession) {
          try {
            await _authService.ensureUsuarioCreado();
          } catch (e) {
            debugPrint('[authListener] ensureUsuarioCreado falló: $e');
          }
          // Cargar el usuario en el provider para que esProfe / rol activo
          // (roles múltiples) estén disponibles apenas se entra a un panel.
          if (mounted) {
            try {
              await context.read<AppProvider>().cargarUsuario();
            } catch (_) {}
          }
        }
      },
      onError: (Object e) => debugPrint('[authListener] error: $e'),
    );
  }

  void _initNotificationHandlers() {
    NotificacionesService.instance.setNotificationTapHandler(
      _handleNotificationPayload,
    );
    // App lanzada desde notificación (estaba completamente cerrada)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final details =
          await NotificacionesService.instance.getLaunchDetails();
      final payload = details?.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        _handleNotificationPayload(payload);
      }
    });
  }

  void _handleNotificationPayload(String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final tipo = data['tipo']?.toString();
      if (tipo == 'recordatorio_clase') {
        final codigoQr = data['codigo_qr']?.toString() ?? '';
        if (codigoQr.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 200), () {
            try {
              appRouter.go('/reserva-confirmada/$codigoQr?from_notif=true');
            } catch (_) {}
          });
        }
      } else if (tipo == 'recordatorio_resena') {
        final estudioId = data['estudio_id'];
        if (estudioId != null) {
          Future.delayed(const Duration(milliseconds: 200), () {
            try {
              appRouter.go('/estudio/$estudioId');
            } catch (_) {}
          });
        }
      } else if (tipo == 'inactividad_creditos') {
        Future.delayed(const Duration(milliseconds: 200), () {
          try {
            appRouter.go('/explorar');
          } catch (_) {}
        });
      }
    } catch (_) {}
  }

  Future<void> _initDeepLinks() async {
    final appLinks = AppLinks();

    // Link inicial (app lanzada desde deep link mientras estaba cerrada)
    try {
      final initialUri = await appLinks.getInitialLink();
      if (initialUri != null) {
        _handleLink(initialUri);
      }
    } catch (_) {}

    // Links mientras la app está en segundo plano o abierta
    _linkSub = appLinks.uriLinkStream.listen(
      _handleLink,
      onError: (_) {},
    );
  }

  void _handleLink(Uri uri) {
    // Soporta:
    //   aura://payment-result?status=success&pago_id=X  (custom scheme)
    //   aura://login-callback  (OAuth Google callback en mobile)
    //   https://somosauraar.netlify.app/payment-result?... (App Links)
    final String path;
    if (uri.scheme == 'aura') {
      path = uri.host.isNotEmpty ? '/${uri.host}' : uri.path;
    } else {
      path = uri.path.isEmpty ? '/' : uri.path;
    }

    // OAuth callback de Google en mobile
    if (path == '/login-callback') {
      _handleOAuthCallback();
      return;
    }

    final query = uri.query.isNotEmpty ? '?${uri.query}' : '';
    final fullPath = '$path$query';

    Future.delayed(const Duration(milliseconds: 200), () {
      try {
        appRouter.go(fullPath);
      } catch (_) {}
    });
  }

  Future<void> _handleOAuthCallback() async {
    // El deep link aura://login-callback puede llegar ANTES de que Supabase
    // termine de canjear el code por la sesión (PKCE es asíncrono). Si leemos
    // currentUser de inmediato puede venir null y quedaríamos trabados en la
    // pantalla de registro sin navegar. Por eso esperamos (poll) hasta ~3s a
    // que la sesión quede establecida.
    User? user = Supabase.instance.client.auth.currentUser;
    for (var i = 0; i < 20 && user == null; i++) {
      await Future.delayed(const Duration(milliseconds: 150));
      user = Supabase.instance.client.auth.currentUser;
    }
    if (user == null) {
      debugPrint('[OAuthCallback] sesión no establecida tras esperar ~3s');
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
              'No pudimos completar el inicio de sesión con Apple. Intentá de nuevo.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    debugPrint('[OAuthCallback] Apple user id: ${user.id}');
    debugPrint('[OAuthCallback] Apple email: ${user.email}');
    debugPrint('[OAuthCallback] Apple metadata: ${user.userMetadata}');
    try {
      // Crear usuario si es primera vez con OAuth (Google o Apple) y resolver
      // el destino según los accesos (usuario / estudio / profe / selector).
      final destino = await _authService.destinoInicial();
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        appRouter.go(destino);
      });
    } catch (e) {
      // No pudimos crear/leer la fila en usuarios: cerramos la sesión a
      // medias y mostramos el error REAL en pantalla (diagnóstico) para
      // poder ver exactamente qué falla sin necesidad de logs por cable.
      debugPrint('[OAuthCallback] fallo al crear usuario: $e');
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        appRouter.go('/login');
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(msg.isNotEmpty
                ? msg
                : 'No pudimos completar tu registro. Intentá de nuevo o usá otro método de inicio de sesión.'),
            backgroundColor: Colors.red,
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConnectivityBanner(
      child: MaterialApp.router(
        title: 'Aura',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: scaffoldMessengerKey,
        theme: AppTheme.lightTheme,
        routerConfig: appRouter,
      ),
    );
  }
}
