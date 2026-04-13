import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../../screens/auth/splash_screen.dart';
import '../../screens/auth/onboarding_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/auth/register_screen.dart';
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
import '../../screens/admin/admin_usuarios_screen.dart';
import '../../screens/admin/admin_reservas_screen.dart';
import '../../screens/admin/admin_config_screen.dart';
import '../../screens/admin/admin_historial_screen.dart';
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

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/splash',
  redirect: (context, state) {
    final loc = state.matchedLocation;
    final isLoggedIn = Supabase.instance.client.auth.currentUser != null;

    // Rutas que no requieren auth
    final publicRoutes = {
      '/splash',
      '/login',
      '/register',
      '/onboarding',
      '/creditos-onboarding',
    };
    if (publicRoutes.contains(loc)) return null;

    // Si no está logueado, redirigir a login
    if (!isLoggedIn) return '/login';
    return null;
  },
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const AuthSplashScreen(),
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
      path: '/creditos-onboarding',
      builder: (context, state) => const CreditosOnboardingScreen(),
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
          builder: (context, state) => const AdminUsuariosScreen(),
        ),
        GoRoute(
          path: '/admin/reservas',
          builder: (context, state) => const AdminReservasScreen(),
        ),
        GoRoute(
          path: '/admin/historial',
          builder: (context, state) => const AdminHistorialScreen(),
        ),
        GoRoute(
          path: '/admin/config',
          builder: (context, state) => const AdminConfigScreen(),
        ),
        GoRoute(
          path: '/admin/liquidaciones',
          builder: (context, state) => const AdminLiquidacionesScreen(),
        ),
      ],
    ),
    ShellRoute(
      navigatorKey: _estudioNavigatorKey,
      builder: (context, state, child) {
        final loc = state.matchedLocation;
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
            int idx = 0;
            if (loc.startsWith('/estudio/clases')) idx = 1;
            if (loc.startsWith('/estudio/asistencia')) idx = 2;
            if (loc.startsWith('/estudio/cobros')) idx = 3;
            if (loc.startsWith('/estudio/perfil')) idx = 4;
            return Scaffold(
              body: child,
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: idx,
                selectedItemColor: AppColors.primary,
                unselectedItemColor: AppColors.grey,
                backgroundColor: AppColors.white,
                elevation: 0,
                type: BottomNavigationBarType.fixed,
                onTap: (i) {
                  const paths = [
                    '/estudio/dashboard',
                    '/estudio/clases',
                    '/estudio/asistencia',
                    '/estudio/cobros',
                    '/estudio/perfil',
                  ];
                  context.go(paths[i]);
                },
                items: const [
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
                ],
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
      ),
    ),
    GoRoute(
      path: '/reserva-gestion/:claseId',
      builder: (context, state) => ReservaGestionScreen(
        claseId: int.tryParse(state.pathParameters['claseId'] ?? '0') ?? 0,
      ),
    ),
    GoRoute(
      path: '/mis-reservas',
      builder: (context, state) => const MisReservasScreen(),
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
      builder: (context, state) => const ComprarCreditosScreen(),
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
    GoRoute(
      path: '/asistencia',
      builder: (context, state) => const AsistenciaScreen(),
    ),
    GoRoute(
      path: '/cobros',
      builder: (context, state) => const CobrosScreen(),
    ),
    GoRoute(
      path: '/dashboard-estudios',
      builder: (context, state) => const DashboardEstudiosScreen(),
    ),
  ],
);
