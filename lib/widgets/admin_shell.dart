import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../screens/admin/admin_gate.dart';

class AdminShell extends StatelessWidget {
  final Widget child;
  final String location;

  const AdminShell({
    super.key,
    required this.child,
    required this.location,
  });

  @override
  Widget build(BuildContext context) {
    int currentIndex = 0;
    if (location.startsWith('/admin/estudios')) currentIndex = 1;
    if (location.startsWith('/admin/usuarios')) currentIndex = 2;
    if (location.startsWith('/admin/reservas')) currentIndex = 3;
    if (location.startsWith('/admin/historial')) currentIndex = 4;
    if (location.startsWith('/admin/liquidaciones')) currentIndex = 5;
    if (location.startsWith('/admin/config')) currentIndex = 6;

    return AdminGate(
      child: Scaffold(
        body: child,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: currentIndex,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.grey,
          type: BottomNavigationBarType.fixed,
          onTap: (index) {
            const paths = [
              '/admin/dashboard',
              '/admin/estudios',
              '/admin/usuarios',
              '/admin/reservas',
              '/admin/historial',
              '/admin/liquidaciones',
              '/admin/config',
            ];
            context.go(paths[index]);
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.space_dashboard_outlined),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.store_outlined),
              label: 'Estudios',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline_rounded),
              label: 'Usuarios',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              label: 'Reservas',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_rounded),
              label: 'Historial',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined),
              label: 'Pagos',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.tune_rounded),
              label: 'Config',
            ),
          ],
        ),
      ),
    );
  }
}
