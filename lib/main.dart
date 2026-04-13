import 'dart:async';

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
    }
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
