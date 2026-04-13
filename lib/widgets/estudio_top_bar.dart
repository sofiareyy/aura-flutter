import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/notificaciones_estudio_service.dart';
import 'notificaciones_estudio_sheet.dart';

class EstudioTopBar extends StatefulWidget implements PreferredSizeWidget {
  final String location;

  const EstudioTopBar({super.key, required this.location});

  static const _kHeight = 64.0;

  @override
  Size get preferredSize => const Size.fromHeight(_kHeight);

  @override
  State<EstudioTopBar> createState() => _EstudioTopBarState();
}

class _EstudioTopBarState extends State<EstudioTopBar> {
  int _unread = 0;
  int? _estudioId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<AppProvider>();
    final newId = provider.estudioAsociado?.id;
    if (newId != null && newId != _estudioId) {
      _estudioId = newId;
      _loadUnread(newId);
    }
  }

  Future<void> _loadUnread(int estudioId) async {
    try {
      final count = await NotificacionesEstudioService.instance
          .getUnreadCount(estudioId);
      if (!mounted) return;
      setState(() => _unread = count);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final studioName = provider.estudioAsociado?.nombre ?? 'Mi Estudio';
    final initials = _initials(studioName);
    final title = _titleFor(widget.location);

    return Container(
      height: EstudioTopBar._kHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE8E5E0)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          // Bell with badge
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.notifications_outlined,
                  color: Color(0xFF5F5953),
                  size: 22,
                ),
                onPressed: () {
                  final id = _estudioId;
                  if (id == null) return;
                  showNotificacionesEstudioSheet(
                    context,
                    estudioId: id,
                    onRead: () => setState(() => _unread = 0),
                  );
                },
              ),
              if (_unread > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE8763A),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFE8763A),
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
        ],
      ),
    );
  }

  static String _titleFor(String loc) {
    if (loc.startsWith('/estudio/dashboard')) return 'Dashboard';
    if (loc.startsWith('/estudio/clases')) return 'Mis Clases';
    if (loc.startsWith('/estudio/asistencia')) return 'Asistencia';
    if (loc.startsWith('/estudio/cobros')) return 'Cobros';
    if (loc.startsWith('/estudio/gestion')) return 'Mis Alumnos';
    if (loc.startsWith('/estudio/perfil')) return 'Perfil del estudio';
    return 'Panel Estudio';
  }

  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) return '?';
    if (words.length == 1) return words[0][0].toUpperCase();
    return (words[0][0] + words[1][0]).toUpperCase();
  }
}
