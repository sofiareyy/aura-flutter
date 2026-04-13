import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/auth_service.dart';

class EstudioSidebar extends StatelessWidget {
  final String location;

  const EstudioSidebar({super.key, required this.location});

  static const _kBg = Color(0xFF1A1A1A);
  static const _kOrange = Color(0xFFE8763A);
  static const _kGrey = Color(0xFF888888);

  static const _items = [
    _NavItem(Icons.grid_view_rounded, 'Dashboard', '/estudio/dashboard'),
    _NavItem(Icons.calendar_today_rounded, 'Mis Clases', '/estudio/clases'),
    _NavItem(Icons.qr_code_scanner_rounded, 'Asistencia', '/estudio/asistencia'),
    _NavItem(Icons.payments_outlined, 'Cobros', '/estudio/cobros'),
    _NavItem(Icons.group_outlined, 'Mis Alumnos', '/estudio/gestion'),
    _NavItem(Icons.storefront_outlined, 'Perfil del estudio', '/estudio/perfil'),
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final studioName = provider.estudioAsociado?.nombre ?? 'Mi Estudio';
    final initials = _initials(studioName);

    return Container(
      width: 240,
      color: _kBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Logo ──────────────────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Text(
                'AURA.',
                style: const TextStyle(
                  color: _kOrange,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          _Divider(),

          // ── Studio info ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _kOrange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    studioName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          _Divider(),
          const SizedBox(height: 8),

          // ── Navigation items ──────────────────────────────────────────────
          for (final item in _items)
            _SidebarItem(
              item: item,
              isActive: location.startsWith(item.path),
            ),

          const Spacer(),

          // ── Bottom actions ────────────────────────────────────────────────
          _Divider(),
          _BottomAction(
            icon: Icons.swap_horiz_rounded,
            label: 'Cambiar a usuario',
            color: _kGrey,
            onTap: () => context.go('/home'),
          ),
          _BottomAction(
            icon: Icons.logout_rounded,
            label: 'Cerrar sesión',
            color: const Color(0xFFFF4444),
            onTap: () => _cerrarSesion(context, provider),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Future<void> _cerrarSesion(BuildContext context, AppProvider provider) async {
    try {
      await AuthService().signOut();
    } catch (_) {}
    provider.limpiarUsuario();
    if (context.mounted) context.go('/login');
  }

  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) return '?';
    if (words.length == 1) return words[0][0].toUpperCase();
    return (words[0][0] + words[1][0]).toUpperCase();
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final String label;
  final String path;

  const _NavItem(this.icon, this.label, this.path);
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: const Color(0xFF333333));
  }
}

class _SidebarItem extends StatefulWidget {
  final _NavItem item;
  final bool isActive;

  const _SidebarItem({required this.item, required this.isActive});

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;
    final color = active ? const Color(0xFFE8763A) : const Color(0xFF888888);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => context.go(widget.item.path),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: active
                ? const Color(0x1FE8763A)
                : _hovered
                    ? const Color(0x10FFFFFF)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(widget.item.icon, size: 18, color: color),
              const SizedBox(width: 12),
              Text(
                widget.item.label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _BottomAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_BottomAction> createState() => _BottomActionState();
}

class _BottomActionState extends State<_BottomAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0x10FFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: widget.color),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.color,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
