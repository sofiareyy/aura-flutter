import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/notificaciones_estudio_service.dart';

Future<void> showNotificacionesEstudioSheet(
  BuildContext context, {
  required int estudioId,
  VoidCallback? onRead,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _NotificacionesSheet(estudioId: estudioId, onRead: onRead),
  );
}

class _NotificacionesSheet extends StatefulWidget {
  final int estudioId;
  final VoidCallback? onRead;

  const _NotificacionesSheet({required this.estudioId, this.onRead});

  @override
  State<_NotificacionesSheet> createState() => _NotificacionesSheetState();
}

class _NotificacionesSheetState extends State<_NotificacionesSheet> {
  final _service = NotificacionesEstudioService.instance;
  List<Map<String, dynamic>> _notifs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _service.getNotificaciones(widget.estudioId);
    if (!mounted) return;
    setState(() {
      _notifs = data;
      _loading = false;
    });
  }

  Future<void> _marcarLeidas() async {
    await _service.marcarTodasLeidas(widget.estudioId);
    if (!mounted) return;
    setState(() {
      _notifs = _notifs.map((n) => {...n, 'leida': true}).toList();
    });
    widget.onRead?.call();
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifs.where((n) => n['leida'] == false).length;
    final maxH = MediaQuery.of(context).size.height * 0.72;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0DDD9),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text(
                      'Notificaciones',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    if (unread > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8763A),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$unread',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (unread > 0)
                      TextButton(
                        onPressed: _marcarLeidas,
                        child: const Text(
                          'Marcar leídas',
                          style: TextStyle(
                            color: Color(0xFF8F877F),
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: _loading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(
                        color: Color(0xFFE8763A),
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : _notifs.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Text(
                            'No hay notificaciones todavía.',
                            style: TextStyle(
                              color: Color(0xFF8F877F),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: _notifs.length,
                        separatorBuilder: (context, index) => const Divider(
                            height: 1, indent: 20, endIndent: 20),
                        itemBuilder: (ctx, i) {
                          final n = _notifs[i];
                          final leida = n['leida'] == true;
                          final dt = DateTime.tryParse(
                              n['created_at']?.toString() ?? '');
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 4),
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: leida
                                    ? const Color(0xFFF5F3F1)
                                    : const Color(0xFFFEEFE6),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.notifications_outlined,
                                size: 18,
                                color: leida
                                    ? const Color(0xFF9A928B)
                                    : const Color(0xFFE8763A),
                              ),
                            ),
                            title: Text(
                              n['mensaje']?.toString() ?? '',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: leida
                                    ? FontWeight.w400
                                    : FontWeight.w600,
                                color: const Color(0xFF1A1A1A),
                              ),
                            ),
                            trailing: Text(
                              dt != null ? _relative(dt) : '',
                              style: const TextStyle(
                                color: Color(0xFFB0A8A0),
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  String _relative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'hace ${diff.inHours}h';
    if (diff.inDays < 7) return 'hace ${diff.inDays}d';
    return DateFormat('d MMM', 'es').format(dt);
  }
}
