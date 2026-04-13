import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../services/reservas_service.dart';

class ReservaConfirmadaScreen extends StatefulWidget {
  final String codigoQr;

  const ReservaConfirmadaScreen({super.key, required this.codigoQr});

  @override
  State<ReservaConfirmadaScreen> createState() => _ReservaConfirmadaScreenState();
}

class _ReservaConfirmadaScreenState extends State<ReservaConfirmadaScreen> {
  final _reservasService = ReservasService();
  Map<String, dynamic>? _reserva;
  bool _loading = true;

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final data = await _reservasService.getReservaPorQr(widget.codigoQr);
      if (!mounted) return;
      setState(() {
        _reserva = data;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _abrirUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    final launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el enlace'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _agregarAlCalendario(
    String className,
    String studioName,
    String location,
    DateTime? fecha,
  ) async {
    final start = fecha ?? DateTime.now().add(const Duration(days: 1));
    final end = start.add(const Duration(minutes: 60));
    final fmt = (DateTime d) =>
        '${d.toUtc().toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';

    final details = Uri.encodeComponent(
      'Reserva Aura\nClase: $className\nEstudio: $studioName',
    );
    final text = Uri.encodeComponent('$className - $studioName');
    final dates = '${fmt(start)}/${fmt(end)}';
    final locationEncoded = Uri.encodeComponent(location);

    await _abrirUrl(
      'https://calendar.google.com/calendar/render?action=TEMPLATE&text=$text&dates=$dates&details=$details&location=$locationEncoded',
    );
  }

Future<void> _abrirShareSheet({
    required String className,
    required String studioName,
    required DateTime? fecha,
    required String? direccion,
  }) async {
    final fechaStr = fecha != null
        ? "${DateFormat("EEEE d 'de' MMMM, HH:mm", 'es').format(fecha)}hs"
        : 'Próximamente';

    final mensaje = '¡Me anoté en $className en $studioName! 🧡\n'
        '📅 $fechaStr\n'
        '📍 ${direccion?.isNotEmpty == true ? direccion : studioName}\n'
        'Reservá en Aura: somosauraar.netlify.app';

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ShareSheet(
        mensaje: mensaje,
        onCopied: () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('¡Copiado al portapapeles! 📋'),
                backgroundColor: Color(0xFF1A1A1A),
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _escribirAlEstudio(Map<String, dynamic>? estudio) async {
    if (estudio == null) return;

    final whatsapp = estudio['whatsapp']?.toString().trim();
    final instagram = estudio['instagram']?.toString().trim();
    final web = estudio['web']?.toString().trim();

    if (whatsapp != null && whatsapp.isNotEmpty) {
      final phone = whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
      await _abrirUrl('https://wa.me/$phone');
      return;
    }

    if (instagram != null && instagram.isNotEmpty) {
      final handle = instagram.startsWith('http')
          ? instagram
          : 'https://instagram.com/${instagram.replaceFirst('@', '')}';
      await _abrirUrl(handle);
      return;
    }

    if (web != null && web.isNotEmpty) {
      await _abrirUrl(web);
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este estudio no tiene un canal de contacto cargado'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final reserva = _reserva;
    final clase = reserva?['clases'] as Map<String, dynamic>?;
    final estudio = clase?['estudios'] as Map<String, dynamic>?;
    final fecha = clase?['fecha'] != null
        ? DateTime.tryParse(clase!['fecha'].toString())
        : null;
    final codigoQr = reserva?['codigo_qr']?.toString();
    final creditosUsadosRaw = _readInt(reserva?['creditos_usados']);
    final creditosClase = _readInt(clase?['creditos']);
    final creditosUsados = creditosUsadosRaw > 0 ? creditosUsadosRaw : creditosClase;
    final className = clase?['nombre']?.toString() ?? 'Clase';
    final studioName = estudio?['nombre']?.toString() ?? 'Estudio';
    final studioArea = estudio?['barrio']?.toString() ?? '';
    final location = estudio?['direccion']?.toString() ?? studioArea;
    final currentCredits = context.watch<AppProvider>().usuario?.creditos;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              color: AppColors.primary,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.go('/home'),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppColors.white,
                  ),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: AppColors.white,
                        size: 42,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '¡Reserva confirmada!',
                      style: TextStyle(
                        color: AppColors.black,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      fecha != null
                          ? '${DateFormat('EEEE, d \'de\' MMMM', 'es').format(fecha)} · $studioName'
                          : studioName,
                      style: const TextStyle(
                        color: Color(0xFF8F877F),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x12000000),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            className,
                            style: const TextStyle(
                              color: AppColors.black,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            studioArea.isEmpty
                                ? studioName
                                : '$studioName · $studioArea',
                            style: const TextStyle(
                              color: Color(0xFF8F877F),
                              fontSize: 14,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Divider(color: AppColors.warmBorder, height: 1),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: codigoQr == null || codigoQr.isEmpty
                                    ? null
                                    : () => showDialog<void>(
                                          context: context,
                                          builder: (ctx) => Dialog(
                                            backgroundColor: Colors.white,
                                            insetPadding: const EdgeInsets.all(24),
                                            child: Padding(
                                              padding: const EdgeInsets.all(20),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Text(
                                                    'QR de asistencia',
                                                    style: TextStyle(
                                                      color: AppColors.black,
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 16),
                                                  SizedBox(
                                                    width: 220,
                                                    height: 220,
                                                    child: QrImageView(
                                                      data: codigoQr,
                                                      version: QrVersions.auto,
                                                      backgroundColor: Colors.white,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F1EF),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: codigoQr == null || codigoQr.isEmpty
                                    ? const Icon(
                                        Icons.qr_code_2_rounded,
                                        color: Color(0xFFC5C0BC),
                                        size: 42,
                                      )
                                    : Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: QrImageView(
                                          data: codigoQr,
                                          version: QrVersions.auto,
                                          backgroundColor: Colors.white,
                                        ),
                                      ),
                              )),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'ID de reserva',
                                      style: TextStyle(
                                        color: Color(0xFF9A928B),
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '#BK-${widget.codigoQr.split('-').last}',
                                      style: const TextStyle(
                                        color: AppColors.black,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Créditos usados',
                                      style: TextStyle(
                                        color: Color(0xFF9A928B),
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$creditosUsados créditos',
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (currentCredits != null)
                                      Text(
                                        'Créditos restantes: $currentCredits',
                                        style: const TextStyle(
                                          color: Color(0xFF6F6862),
                                          fontSize: 13,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    // ── Cómo llegar ──────────────────────────────────────
                    if (estudio != null) ...[
                      _ComoLlegarCard(
                        estudio: estudio,
                        abrirUrl: _abrirUrl,
                      ),
                      const SizedBox(height: 18),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: _MiniAction(
                            icon: Icons.calendar_today_outlined,
                            label: 'Agregar al\ncalendario',
                            onTap: () => _agregarAlCalendario(
                              className,
                              studioName,
                              location,
                              fecha,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniAction(
                            icon: Icons.share_outlined,
                            label: 'Compartir',
                            onTap: () => _abrirShareSheet(
                              className: className,
                              studioName: studioName,
                              fecha: fecha,
                              direccion: estudio?['direccion']?.toString(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniAction(
                            icon: Icons.chat_bubble_outline_rounded,
                            label: 'Escribir al\nestudio',
                            onTap: () => _escribirAlEstudio(estudio),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () => context.go('/mis-reservas'),
                        child: const Text('Ver mis reservas'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton(
                        onPressed: () => context.go('/explorar'),
                        child: const Text(
                          'Seguir explorando',
                          style: TextStyle(color: AppColors.primary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Cómo llegar ─────────────────────────────────────────────────────────────

class _ComoLlegarCard extends StatelessWidget {
  final Map<String, dynamic> estudio;
  final Future<void> Function(String) abrirUrl;

  const _ComoLlegarCard({required this.estudio, required this.abrirUrl});

  @override
  Widget build(BuildContext context) {
    final direccion = estudio['direccion']?.toString() ?? '';
    final nombre = estudio['nombre']?.toString() ?? '';
    final lat = (estudio['lat'] as num?)?.toDouble();
    final lng = (estudio['lng'] as num?)?.toDouble();
    final hasCoords = lat != null && lng != null;
    final hasAddress = direccion.isNotEmpty;

    if (!hasAddress && !hasCoords) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CÓMO LLEGAR',
            style: TextStyle(
              color: Color(0xFF9A928B),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_rounded,
                color: Color(0xFFE8763A),
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasAddress ? direccion : nombre,
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          if (hasCoords) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MapButton(
                    label: 'Google Maps',
                    icon: Icons.map_outlined,
                    onTap: () => abrirUrl(
                      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MapButton(
                    label: 'Waze',
                    icon: Icons.navigation_outlined,
                    onTap: () => abrirUrl(
                      'https://waze.com/ul?ll=$lat,$lng&navigate=yes',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _MapButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF1A1A1A),
        side: const BorderSide(color: Color(0xFFE8E5E0)),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── Share Sheet ─────────────────────────────────────────────────────────────

class _ShareSheet extends StatelessWidget {
  final String mensaje;
  final VoidCallback onCopied;

  const _ShareSheet({required this.mensaje, required this.onCopied});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          const SizedBox(height: 16),
          const Text(
            'Compartir reserva',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 20),

          // WhatsApp
          _ShareOptionRow(
            iconWidget: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFF25D366),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text(
                  'W',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
            label: 'Invitar por WhatsApp',
            onTap: () async {
              final encoded = Uri.encodeComponent(mensaje);
              final uri = Uri.parse('whatsapp://send?text=$encoded');
              bool launched = false;
              try {
                launched = await launchUrl(uri,
                    mode: LaunchMode.externalApplication);
              } catch (_) {}
              if (!launched) {
                await launchUrl(
                  Uri.parse('https://wa.me/?text=$encoded'),
                  mode: LaunchMode.externalApplication,
                );
              }
              if (context.mounted) Navigator.pop(context);
            },
          ),
          const SizedBox(height: 4),

          // Copy
          _ShareOptionRow(
            iconWidget: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFF8F877F),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.copy_rounded, color: Colors.white, size: 20),
              ),
            ),
            label: 'Copiar información',
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: mensaje));
              if (context.mounted) Navigator.pop(context);
              onCopied();
            },
          ),
          const SizedBox(height: 4),

          // Share via other apps
          _ShareOptionRow(
            iconWidget: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFE8763A),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child:
                    Icon(Icons.share_rounded, color: Colors.white, size: 20),
              ),
            ),
            label: 'Otras apps',
            onTap: () {
              Navigator.pop(context);
              Share.share(mensaje);
            },
          ),

          const Divider(height: 24),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Color(0xFF8F877F), fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareOptionRow extends StatelessWidget {
  final Widget iconWidget;
  final String label;
  final VoidCallback onTap;

  const _ShareOptionRow({
    required this.iconWidget,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            iconWidget,
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFB0A8A0),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Mini Action ──────────────────────────────────────────────────────────────

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10000000),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF625C57),
                  fontSize: 13,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
