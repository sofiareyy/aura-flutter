import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme/app_theme.dart';

class MainShell extends StatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  /// Suma de pre_confirmadas + lista_espera del usuario logueado.
  /// Cuando es > 0 mostramos un badge naranja en la pestaña "Reservas".
  int _reservasBadge = 0;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refrescarBadge();
    // Poll cada 30 seg. Es chiquito y nos protege del caso "promovieron al
    // user mientras tenia la app abierta en otra pestania".
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refrescarBadge(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/explorar')) return 1;
    if (location.startsWith('/mis-clases')) return 2;
    if (location.startsWith('/perfil')) return 3;
    return 0;
  }

  Future<void> _refrescarBadge() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
      if (uid.isEmpty) {
        if (mounted && _reservasBadge != 0) {
          setState(() => _reservasBadge = 0);
        }
        return;
      }
      final results = await Future.wait([
        Supabase.instance.client
            .from('reservas')
            .select('id')
            .eq('usuario_id', uid)
            .eq('estado', 'pre_confirmada')
            .gt('expires_at', DateTime.now().toUtc().toIso8601String()),
        Supabase.instance.client
            .from('lista_espera')
            .select('clase_id')
            .eq('usuario_id', uid),
      ]);
      if (!mounted) return;
      final total = (results[0] as List).length + (results[1] as List).length;
      if (total != _reservasBadge) {
        setState(() => _reservasBadge = total);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex(context);
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(
            top: BorderSide(color: AppColors.warmBorder, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: selectedIndex,
          backgroundColor: AppColors.background,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: const Color(0xFFC8C0B9),
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          onTap: (index) {
            switch (index) {
              case 0:
                context.go('/home');
                break;
              case 1:
                context.go('/explorar');
                break;
              case 2:
                context.go('/mis-clases');
                // Al entrar a la pestania, refrescar inmediatamente.
                _refrescarBadge();
                break;
              case 3:
                context.go('/perfil');
                break;
            }
          },
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_rounded),
              activeIcon: Icon(Icons.grid_view_rounded),
              label: 'Inicio',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.search_outlined),
              activeIcon: Icon(Icons.search_rounded),
              label: 'Explorar',
            ),
            BottomNavigationBarItem(
              icon: _ReservasIcon(
                icon: Icons.work_outline_rounded,
                badgeCount: _reservasBadge,
              ),
              activeIcon: _ReservasIcon(
                icon: Icons.work_rounded,
                badgeCount: _reservasBadge,
              ),
              label: 'Reservas',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}

class _ReservasIcon extends StatelessWidget {
  final IconData icon;
  final int badgeCount;
  const _ReservasIcon({required this.icon, required this.badgeCount});

  @override
  Widget build(BuildContext context) {
    if (badgeCount <= 0) return Icon(icon);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        Positioned(
          right: -8,
          top: -4,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.background, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text(
              badgeCount > 99 ? '99+' : '$badgeCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
