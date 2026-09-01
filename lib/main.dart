import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/auth_flow_state.dart';
import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/app_provider.dart';
import 'services/auth_service.dart';
import 'utils/destino_post_login.dart';
import 'services/notificaciones_service.dart';
import 'services/valor_credito.dart';
import 'services/version_gate.dart';
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

  // Push (FCM): SOLO mobile. En el proyecto de Firebase estan registradas las
  // apps de Android e iOS, no una app Web, asi que inicializar Firebase en web
  // reventaria en runtime. Y push web necesitaria service worker + claves VAPID
  // aparte. Con este guard, somosaurapass.com queda intacto.
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
      await NotificacionesService.instance.initFirebaseMessaging();
    } catch (e) {
      // Si Firebase no esta configurado en esta maquina (falta
      // google-services.json / GoogleService-Info.plist, que NO van al repo
      // porque es publico), la app tiene que arrancar igual: sin push.
      debugPrint('[push] Firebase no disponible: $e');
    }
  }

  // Valor del crédito en ARS: se cachea al arranque para que las
  // pantallas de dinero lo lean sincrónicamente sin hardcodear nada.
  // No bloqueamos el arranque si falla: queda el default.
  unawaited(ValorCredito.cargar());

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

class _AuraAppState extends State<AuraApp> with WidgetsBindingObserver {
  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<AuthState>? _authSub;
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAuthListener();
    if (!kIsWeb) {
      _initDeepLinks();
      _initNotificationHandlers();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver la app al foreground, releemos el valor del crédito por si el
    // admin lo cambió desde el backoffice mientras la sesión estaba abierta.
    // `forzar: false` respeta el throttle de 5 min de ValorCredito, así que si
    // el usuario entra y sale seguido no se repite la query. Es una sola fila,
    // async y no bloquea la UI.
    if (state == AppLifecycleState.resumed) {
      ValorCredito.cargar(forzar: false).ignore();

      // Re-chequeo del force-update al volver del background: si mientras la
      // app estaba abierta se subió la versión mínima, o si alguien intentó
      // saltear la pantalla con un deep link, acá queda atrapado. Fail-open
      // (VersionGate nunca bloquea ante error), y no aplica en web.
      if (!kIsWeb) {
        VersionGate.hayQueActualizar().then((hay) {
          if (hay) appRouter.go('/actualizar');
        }).ignore();
      }
    }
    super.didChangeAppLifecycleState(state);
  }

  /// Garantiza que la fila en `usuarios` exista después de CUALQUIER inicio
  /// de sesión (Google, Apple o email). Es la red de seguridad central: aun
  /// si el flujo específico no la creó, este listener lo hace. Es idempotente
  /// (ensureUsuarioCreado relee si ya existe y maneja la carrera).
  void _initAuthListener() {
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) async {
        final event = data.event;
        // Recuperación de contraseña: el SDK ya estableció la sesión temporal
        // al procesar el deep link aura://reset-password. Llevamos a la pantalla
        // para elegir la clave nueva.
        if (event == AuthChangeEvent.passwordRecovery) {
          // Marca el flag para que el splash (en cold start) no pise esta
          // navegación con su redirect normal a /home. En warm start el splash
          // no corre y basta con el go() de acá.
          AuthFlowState.pendingPasswordRecovery = true;
          Future.delayed(const Duration(milliseconds: 200), () {
            try {
              appRouter.go('/reset-password');
            } catch (_) {}
          });
          return;
        }
        if (event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.userUpdated ||
            event == AuthChangeEvent.initialSession) {
          try {
            await _authService.ensureUsuarioCreado();
          } catch (e) {
            debugPrint('[authListener] ensureUsuarioCreado falló: $e');
          }
          // Los créditos de bienvenida se DESCARTARON (decisión del 29/8:
          // no se regalan créditos a cuentas nuevas). La RPC
          // acreditar_bienvenida nunca existió en la base y esta llamada
          // fallaba en silencio EN CADA LOGIN: una ida y vuelta regalada.
          // Cargar el usuario en el provider para que esProfe / rol activo
          // (roles múltiples) estén disponibles apenas se entra a un panel.
          if (mounted) {
            try {
              await context.read<AppProvider>().cargarUsuario();
            } catch (_) {}
          }
          // PUSH: el permiso se pide ACA, después del login, no en main().
          // Antes salía el diálogo de iOS al abrir la app por primera vez,
          // en frío y antes de saber qué es Aura — quemando el único intento
          // que da iOS. Y recién ahora hay usuario contra quien registrar el
          // token del dispositivo.
          try {
            await NotificacionesService.instance.pedirPermisos();
            await NotificacionesService.instance.registrarDispositivo();
          } catch (_) {}
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
      } else if (tipo == 'pre_confirmada') {
        // Push de "se liberó un lugar" (promoción de lista de espera). El
        // codigo_qr lo manda la edge push-enviar en el `data`. Tiene 30 min
        // para confirmar, así que el tap lo deja directo en la pantalla.
        final codigoQr = data['codigo_qr']?.toString() ?? '';
        Future.delayed(const Duration(milliseconds: 200), () {
          try {
            if (codigoQr.isNotEmpty) {
              appRouter.go('/reserva-confirmada/$codigoQr?from_notif=true');
            } else {
              appRouter.go('/mis-reservas');
            }
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
    //   https://somosaurapass.com/payment-result?... (App Links)
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

    // Recuperación de contraseña: el SDK procesa el token de este mismo deep
    // link y dispara passwordRecovery, que es quien navega a /reset-password
    // (recién cuando la sesión temporal ya está lista). No navegamos acá para
    // no llegar a la pantalla antes de tener sesión.
    if (path == '/reset-password') {
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
      // Vuelta de OAuth: la pantalla de login ya no existe, así que el destino
      // que dejó guardado se consume acá. `tomar()` borra siempre (es de un
      // solo uso) y `resolver` sólo lo aplica si el rol daba el /home
      // genérico: un estudio o una profe van igual a su panel.
      final volver = await DestinoPostLogin.tomar();
      final destinoFinal = DestinoPostLogin.resolver(destino, volver);
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        appRouter.go(destinoFinal);
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
    WidgetsBinding.instance.removeObserver(this);
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
