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
import 'services/notificaciones_service.dart';
import 'widgets/connectivity_banner.dart';

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

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _initDeepLinks();
      _initNotificationHandlers();
    }
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
    //   https://somosauraar.netlify.app/payment-result?... (App Links)
    final String path;
    if (uri.scheme == 'aura') {
      // aura://payment-result → host="payment-result", path=""
      path = uri.host.isNotEmpty ? '/${uri.host}' : uri.path;
    } else {
      path = uri.path.isEmpty ? '/' : uri.path;
    }

    final query = uri.query.isNotEmpty ? '?${uri.query}' : '';
    final fullPath = '$path$query';

    // Pequeño delay para que el router esté listo si la app acaba de lanzar
    Future.delayed(const Duration(milliseconds: 200), () {
      try {
        appRouter.go(fullPath);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConnectivityBanner(
      child: MaterialApp.router(
        title: 'Aura',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: appRouter,
      ),
    );
  }
}
