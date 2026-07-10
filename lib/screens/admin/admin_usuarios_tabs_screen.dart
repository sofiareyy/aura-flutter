import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'admin_usuarios_screen.dart';
import 'admin_reservas_screen.dart';
import 'admin_historial_screen.dart';

/// Agrupa Usuarios + Reservas + Historial bajo una sola pestaña del backoffice
/// ("Usuarios") con sub-tabs internas, para bajar el bottom nav a 5 tabs.
class AdminUsuariosTabsScreen extends StatelessWidget {
  const AdminUsuariosTabsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          toolbarHeight: 0,
          backgroundColor: AppColors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          bottom: const TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.grey,
            indicatorColor: AppColors.primary,
            labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: [
              Tab(text: 'Usuarios'),
              Tab(text: 'Reservas'),
              Tab(text: 'Historial'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AdminUsuariosScreen(),
            AdminReservasScreen(),
            AdminHistorialScreen(),
          ],
        ),
      ),
    );
  }
}
