import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../screens/auth/splash_screen.dart';
import '../../screens/auth/onboarding_screen.dart';
import '../../screens/auth/landing_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/auth/register_screen.dart';
import '../../screens/auth/reset_password_screen.dart';
import '../../screens/auth/seleccionar_acceso_screen.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/explorar/explorar_screen.dart';
import '../../screens/estudios/detalle_estudio_screen.dart';
import '../../screens/estudios/dashboard_estudios_screen.dart';
import '../../screens/estudios/perfil_estudio_screen.dart';
import '../../screens/clases/detalle_clase_screen.dart';
import '../../screens/clases/mis_clases_screen.dart';
import '../../screens/reservas/confirmar_reserva_screen.dart';
import '../../screens/reservas/reserva_gestion_screen.dart';
import '../../screens/reservas/reserva_confirmada_screen.dart';
import '../../screens/reservas/mis_reservas_screen.dart';
import '../../screens/estudio/aura_gestion_screen.dart';
import '../../screens/perfil/mi_perfil_screen.dart';
import '../../screens/perfil/configuracion_screen.dart';
import '../../screens/perfil/editar_perfil_screen.dart';
import '../../screens/perfil/cambiar_contrasena_screen.dart';
import '../../screens/perfil/notificaciones_screen.dart';
import '../../screens/perfil/ayuda_screen.dart';
import '../../screens/perfil/terminos_screen.dart';
import '../../screens/perfil/privacidad_screen.dart';
import '../../screens/admin/admin_dashboard_screen.dart';
import '../../screens/admin/admin_estudios_screen.dart';
import '../../screens/admin/admin_usuarios_tabs_screen.dart';
import '../../screens/admin/admin_config_screen.dart';
import '../../screens/admin/admin_empresas_screen.dart';
import '../../screens/admin/admin_liquidaciones_screen.dart';
import '../../screens/creditos/mis_creditos_screen.dart';
import '../../screens/onboarding/creditos_onboarding_screen.dart';
import '../../screens/creditos/comprar_creditos_screen.dart';
import '../../screens/creditos/historial_creditos_screen.dart';
import '../../screens/plan/cambiar_plan_screen.dart';
import '../../screens/plan/checkout_screen.dart';
import '../../screens/plan/payment_result_screen.dart';
import '../../screens/referidos/referidos_screen.dart';
import '../../screens/mapa/mapa_screen.dart';
import '../../screens/asistencia/asistencia_screen.dart';
import '../../screens/cobros/cobros_screen.dart';
import '../../widgets/admin_shell.dart';
import '../../widgets/estudio_sidebar.dart';
import '../../widgets/estudio_top_bar.dart';
import '../../widgets/main_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();
final _estudioNavigatorKey = GlobalKey<NavigatorState>();
final _adminNavigatorKey = GlobalKey<NavigatorState>();

/// Rutas del panel de estudio a las que puede entrar una profe.
const _rutasProfe = ['/estudio/clases', '/estudio/asistencia'];

bool _rutaPermitidaProfe(String loc) =>
    _rutasProfe.any((p) => loc.startsWith(p));

/// Rutas de "browse" que un invitado (sin sesión) puede ver: el marketplace
/// de solo lectura. El resto sigue protegido (perfil, créditos, reservas,
/// checkout, panel de estudio/admin) — sin sesión caen a /login.
bool _esBrowsePublica(String loc) {
  // /home entra: para el invitado muestra el catálogo (clases de la semana,
  // experiencias, estudios cerca) con las cards personales reemplazadas por
  // un CTA de registro. Ver home_screen.
  if (loc == '/home' || loc == '/explorar' || loc == '/mapa') return true;
  if (loc.startsWith('/clase/')) return true;
  return _esEstudioDetalle(loc);
}

/// `/estudio/<id numérico>` = detalle público del estudio (invitado lo ve).
/// `/estudio/dashboard|clases|...` = panel privado → NO es browse, queda protegido.
bool _esEstudioDetalle(String loc) {
  if (!loc.startsWith('/estudio/')) return false;
  final resto = loc.substring('/estudio/'.length);
  return int.tryParse(resto) != null;
}

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/splash',
  redirect: (context, state) {
    final loc = state.matchedLocation;
    final isLoggedIn = Supabase.instance.client.auth.currentUser != null;

    // Rutas que no requieren auth
    final publicRoutes = {
      '/splash',
      '/landing',
      '/login',
      '/register',
      '/reset-password',
      '/onboarding',
      '/creditos-onboarding',
    };
    if (publicRoutes.contains(loc)) return null;

    // Sin sesión: un invitado puede ver el browse (marketplace de solo lectura);
    // cualquier otra ruta (cuenta, checkout, panel) lo manda a login.
    if (!isLoggedIn) {
      return _esBrowsePublica(loc) ? null : '/login';
    }

    // Una profe solo accede a Mis Clases y Asistencia. El gate va acá, en el
    // redirect global, y no en el builder del shell: el builder corre DESPUES
    // de resolver la ruta, así que CobrosScreen alcanzaba a montarse y a
    // disparar su query de reservas antes de que el redirect la sacara.
    if (loc.startsWith('/estudio') && !_rutaPermitidaProfe(loc)) {
      // read, no watch: en redirect no hay que suscribirse.
      final esProfe = context.read<AppProvider>().esProfe;
      if (esProfe) return '/estudio/clases';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const AuthSplashScreen(),
    ),
    GoRoute(
      path: '/landing',
      builder: (context, state) => const LandingScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const AuthOnboardingScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/reset-password',
      builder: (context, state) => const ResetPasswordScreen(),
    ),
    GoRoute(
      path: '/creditos-onboarding',
      builder: (context, state) => const CreditosOnboardingScreen(),
    ),
    GoRoute(
      path: '/seleccionar-acceso',
      builder: (context, state) => const SeleccionarAccesoScreen(),
    ),
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/explorar',
          builder: (context, state) => const ExplorarScreen(),
        ),
        GoRoute(
          path: '/mis-reservas',
          builder: (context, state) => const MisReservasScreen(),
        ),
        GoRoute(
          path: '/mis-clases',
          builder: (context, state) => const MisClasesScreen(),
        ),
        GoRoute(
          path: '/perfil',
          builder: (context, state) => const MiPerfilScreen(),
        ),
      ],
    ),
    ShellRoute(
      navigatorKey: _adminNavigatorKey,
      builder: (context, state, child) => AdminShell(
        location: state.matchedLocation,
        child: child,
      ),
      routes: [
        GoRoute(
          path: '/admin/dashboard',
          builder: (context, state) => const AdminDashboardScreen(),
        ),
        GoRoute(
          path: '/admin/estudios',
          builder: (context, state) => const AdminEstudiosScreen(),
        ),
        GoRoute(
          path: '/admin/usuarios',
          builder: (context, state) => const AdminUsuariosTabsScreen(),
        ),
        GoRoute(
          path: '/admin/config',
          builder: (context, state) => const AdminConfigScreen(),
        ),
        GoRoute(
          path: '/admin/pagos',
          builder: (context, state) => const AdminLiquidacionesScreen(),
        ),
        GoRoute(
          path: '/admin/empresas',
          builder: (context, state) => const AdminEmpresasScreen(),
        ),
      ],
    ),
    ShellRoute(
      navigatorKey: _estudioNavigatorKey,
      builder: (context, state, child) {
        final loc = state.matchedLocation;
        // Red de seguridad para cuando el rol todavía no estaba cargado en el
        // momento del redirect global (login recién hecho, cambio de estudio).
        // Devolvemos un placeholder en vez de `child`: así la pantalla
        // prohibida no llega a montarse ni a ejecutar sus queries.
        final esProfe = context.watch<AppProvider>().esProfe;
        if (esProfe && !_rutaPermitidaProfe(loc)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('/estudio/clases');
          });
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }
        return LayoutBuilder(
          builder: (ctx, constraints) {
            final isDesktop = constraints.maxWidth >= 768;

            if (isDesktop) {
              return Scaffold(
                backgroundColor: AppColors.background,
                body: Row(
                  children: [
                    EstudioSidebar(location: loc),
                    Expanded(
                      child: Column(
                        children: [
                          EstudioTopBar(location: loc),
                          Expanded(child: child),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            // ── Mobile: bottom nav bar ──────────────────────────────────────
            // La profe ve solo Clases + Asistencia; el resto ve el menú completo.
            final navPaths = esProfe
                ? const ['/estudio/clases', '/estudio/asistencia', '/perfil']
                : const [
                    '/estudio/dashboard',
                    '/estudio/clases',
                    '/estudio/asistencia',
                    '/estudio/cobros',
                    '/estudio/perfil',
                  ];
            final navItems = esProfe
                ? const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.calendar_today_rounded),
                      label: 'Clases',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.qr_code_scanner_rounded),
                      label: 'Asistencia',
                    ),
                    // Perfil propio: la profe edita su perfil y vuelve al lado
                    // usuario. Sale del panel (es otra shell), por eso no queda
                    // "activo" dentro del bottom nav del estudio.
                    BottomNavigationBarItem(
                      icon: Icon(Icons.person_outline_rounded),
                      label: 'Perfil',
                    ),
                  ]
                : const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.grid_view_rounded),
                      label: 'Dashboard',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.calendar_today_rounded),
                      label: 'Clases',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.qr_code_scanner_rounded),
                      label: 'Asistencia',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.payments_outlined),
                      label: 'Cobros',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.person_outline_rounded),
                      label: 'Perfil',
                    ),
                  ];
            var idx = navPaths.indexWhere((p) => loc.startsWith(p));
            if (idx < 0) idx = 0;
            return Scaffold(
              body: child,
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: idx,
                selectedItemColor: AppColors.primary,
                unselectedItemColor: AppColors.grey,
                backgroundColor: AppColors.white,
                elevation: 0,
                type: BottomNavigationBarType.fixed,
                onTap: (i) => context.go(navPaths[i]),
                items: navItems,
              ),
            );
          },
        );
      },
      routes: [
        GoRoute(
          path: '/estudio/dashboard',
          builder: (context, state) => const DashboardEstudiosScreen(),
        ),
        GoRoute(
          path: '/estudio/clases',
          builder: (context, state) => const MisClasesScreen(),
        ),
        GoRoute(
          path: '/estudio/asistencia',
          builder: (context, state) => const AsistenciaScreen(),
        ),
        GoRoute(
          path: '/estudio/cobros',
          builder: (context, state) => const CobrosScreen(),
        ),
        GoRoute(
          path: '/estudio/perfil',
          builder: (context, state) => const PerfilEstudioScreen(),
        ),
        GoRoute(
          path: '/estudio/gestion',
          builder: (context, state) => const AuraGestionScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/estudio/:id',
      builder: (context, state) => DetalleEstudioScreen(
        estudioId: int.tryParse(state.pathParameters['id'] ?? '0') ?? 0,
      ),
    ),
    GoRoute(
      path: '/clase/:id',
      builder: (context, state) => DetalleClaseScreen(
        claseId: int.tryParse(state.pathParameters['id'] ?? '0') ?? 0,
      ),
    ),
    GoRoute(
      path: '/confirmar-reserva/:claseId',
      builder: (context, state) => ConfirmarReservaScreen(
        claseId: int.tryParse(state.pathParameters['claseId'] ?? '0') ?? 0,
      ),
    ),
    GoRoute(
      path: '/reserva-confirmada/:codigoQr',
      builder: (context, state) => ReservaConfirmadaScreen(
        codigoQr: state.pathParameters['codigoQr'] ?? '',
        fromNotification: state.uri.queryParameters['from_notif'] == 'true',
      ),
    ),
    GoRoute(
      path: '/reserva-gestion/:claseId',
      builder: (context, state) => ReservaGestionScreen(
        claseId: int.tryParse(state.pathParameters['claseId'] ?? '0') ?? 0,
      ),
    ),
    GoRoute(
      path: '/configuracion',
      builder: (context, state) => const ConfiguracionScreen(),
    ),
    GoRoute(
      path: '/perfil/editar',
      builder: (context, state) => const EditarPerfilScreen(),
    ),
    GoRoute(
      path: '/perfil/cambiar-contrasena',
      builder: (context, state) => const CambiarContrasenaScreen(),
    ),
    GoRoute(
      path: '/perfil/notificaciones',
      builder: (context, state) => const NotificacionesScreen(),
    ),
    GoRoute(
      path: '/perfil/ayuda',
      builder: (context, state) => const AyudaScreen(),
    ),
    GoRoute(
      path: '/perfil/terminos',
      builder: (context, state) => const TerminosScreen(),
    ),
    GoRoute(
      path: '/perfil/privacidad',
      builder: (context, state) => const PrivacidadScreen(),
    ),
    GoRoute(
      path: '/mis-creditos',
      builder: (context, state) => const MisCreditosScreen(),
    ),
    GoRoute(
      path: '/comprar-creditos',
      builder: (context, state) {
        // ?tab=gift abre directo la pestaña Regalar (para el acceso desde el
        // perfil). Sin el query, arranca en Packs como siempre.
        final tab = state.uri.queryParameters['tab'];
        return ComprarCreditosScreen(
          initialTab: tab == 'gift'
              ? 2
              : tab == 'plan'
                  ? 1
                  : 0,
        );
      },
    ),
    GoRoute(
      path: '/historial-creditos',
      builder: (context, state) => const HistorialCreditosScreen(),
    ),
    GoRoute(
      path: '/cambiar-plan',
      builder: (context, state) => const CambiarPlanScreen(),
    ),
    GoRoute(
      path: '/checkout',
      builder: (context, state) => CheckoutScreen(
        purchase: Map<String, dynamic>.from(
          (state.extra as Map?) ?? const <String, dynamic>{},
        ),
      ),
    ),
    GoRoute(
      path: '/payment-result',
      builder: (context, state) => PaymentResultScreen(
        pagoId: state.uri.queryParameters['pago_id'],
        paymentId: state.uri.queryParameters['payment_id'] ??
            state.uri.queryParameters['collection_id'],
        status: state.uri.queryParameters['status'],
      ),
    ),
    GoRoute(
      path: '/referidos',
      builder: (context, state) => const ReferidosScreen(),
    ),
    GoRoute(
      path: '/mapa',
      builder: (context, state) => const MapaScreen(),
    ),
    // D1 — Se eliminan /asistencia, /cobros y /dashboard-estudios.
    // Eran rutas espejo de las del panel (/estudio/*) pero FUERA del shell,
    // así que el gate de rol del redirect —que matchea startsWith('/estudio')—
    // no las alcanzaba: una profe entraba a /cobros y veía la caja completa
    // del estudio. Las versiones válidas viven en /estudio/asistencia,
    // /estudio/cobros y /estudio/dashboard.
  ],
);
