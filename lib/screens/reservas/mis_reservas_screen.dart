import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../services/reservas_service.dart';

class MisReservasScreen extends StatefulWidget {
  const MisReservasScreen({super.key});

  @override
  State<MisReservasScreen> createState() => _MisReservasScreenState();
}

class _MisReservasScreenState extends State<MisReservasScreen>
    with SingleTickerProviderStateMixin {
  final _reservasService = ReservasService();
  late TabController _tabCtrl;
  List<Map<String, dynamic>> _proximas = [];
  List<Map<String, dynamic>> _historial = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMoreHistorial = true;
  int _historialOffset = 0;
  static const _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _cargar();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final authUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (authUserId.isEmpty) {
      if (mounted) setState(() { _proximas = []; _historial = []; _loading = false; });
      return;
    }
    setState(() { _loading = true; _historialOffset = 0; _hasMoreHistorial = true; });
    await context.read<AppProvider>().refrescarUsuario();

    final results = await Future.wait([
      _reservasService.getReservasUsuario(authUserId),
      _reservasService.getHistorialReservas(authUserId, limit: _pageSize, offset: 0),
    ]);

    if (!mounted) return;
    final historial = results[1];
    setState(() {
      _proximas = results[0];
      _historial = historial;
      _historialOffset = historial.length;
      _hasMoreHistorial = historial.length == _pageSize;
      _loading = false;
    });
  }

  Future<void> _cargarMasHistorial() async {
    if (_loadingMore || !_hasMoreHistorial) return;
    final authUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (authUserId.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final mas = await _reservasService.getHistorialReservas(
        authUserId,
        limit: _pageSize,
        offset: _historialOffset,
      );
      if (!mounted) return;
      setState(() {
        _historial = [..._historial, ...mas];
        _historialOffset += mas.length;
        _hasMoreHistorial = mas.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  bool _puedeCancelar(Map<String, dynamic> reserva) {
    final clase = reserva['clases'] as Map<String, dynamic>?;
    final fecha = clase?['fecha'] != null
        ? DateTime.tryParse(clase!['fecha'].toString())
        : null;
    if (fecha == null) return false;
    return DateTime.now().isBefore(fecha.subtract(const Duration(hours: 12)));
  }

  Future<void> _cancelar(Map<String, dynamic> reserva) async {
    if (!_puedeCancelar(reserva)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solo podés cancelar hasta 12 horas antes del inicio.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar reserva'),
        content: const Text('¿Querés cancelar esta reserva?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, cancelar',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _reservasService.cancelarReserva(
        reserva['codigo_qr']?.toString() ?? '',
      );
      await _cargar();
    }
  }

  void _verQr(Map<String, dynamic> reserva) {
    final codigoQr = reserva['codigo_qr']?.toString() ?? '';
    if (codigoQr.isNotEmpty) {
      context.push('/reserva-confirmada/${Uri.encodeComponent(codigoQr)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            titleSpacing: 20,
            title: const Text(
              'Mis reservas',
              style: TextStyle(
                color: AppColors.black,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                color: AppColors.background,
                child: TabBar(
                  controller: _tabCtrl,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.grey,
                  indicatorColor: AppColors.primary,
                  indicatorWeight: 2,
                  labelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: const [
                    Tab(text: 'Próximas'),
                    Tab(text: 'Historial'),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: _loading
            ? _buildShimmer()
            : TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildProximas(),
                  _buildHistorial(),
                ],
              ),
      ),
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFECE9E4),
      highlightColor: AppColors.background,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        itemCount: 3,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 14),
          height: 160,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  Widget _buildProximas() {
    if (_proximas.isEmpty) {
      return _EmptyState(
        title: 'Nada por aquí todavía',
        subtitle: 'Reservá tu primera clase y aparecerá acá.',
        onExplorar: () => context.go('/explorar'),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        itemCount: _proximas.length,
        itemBuilder: (context, i) => _ProximaCard(
          reserva: _proximas[i],
          canCancel: _puedeCancelar(_proximas[i]),
          onVerTicket: () => _verQr(_proximas[i]),
          onCancelar: () => _cancelar(_proximas[i]),
        ),
      ),
    );
  }

  Widget _buildHistorial() {
    if (_historial.isEmpty) {
      return _EmptyState(
        title: 'Tu historial está vacío',
        subtitle: 'Tus clases completadas o canceladas aparecerán acá.',
        onExplorar: () => context.go('/explorar'),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        itemCount: _historial.length + (_hasMoreHistorial || _loadingMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _historial.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: _loadingMore
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : TextButton.icon(
                        onPressed: _cargarMasHistorial,
                        icon: const Icon(Icons.expand_more_rounded, size: 18),
                        label: const Text('Cargar más'),
                      ),
              ),
            );
          }
          return _HistorialCard(reserva: _historial[i]);
        },
      ),
    );
  }
}

// ─── Próxima Card ────────────────────────────────────────────────────────────

class _ProximaCard extends StatelessWidget {
  final Map<String, dynamic> reserva;
  final bool canCancel;
  final VoidCallback onVerTicket;
  final VoidCallback onCancelar;

  const _ProximaCard({
    required this.reserva,
    required this.canCancel,
    required this.onVerTicket,
    required this.onCancelar,
  });

  @override
  Widget build(BuildContext context) {
    final clase = reserva['clases'] as Map<String, dynamic>?;
    final estudio = clase?['estudios'] as Map<String, dynamic>?;
    final fecha = clase?['fecha'] != null
        ? DateTime.tryParse(clase!['fecha'].toString())
        : null;
    final creditos = (reserva['creditos_usados'] as num?)?.toInt() ?? 0;
    final esGratis = creditos == 0;
    final fotoUrl = (clase?['imagen_url'] ?? estudio?['foto_url'])?.toString();
    final categoria =
        (estudio?['categoria']?.toString() ?? 'CLASE').toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Foto 80×80
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: fotoUrl != null && fotoUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: fotoUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _photoPlaceholder(),
                          )
                        : _photoPlaceholder(),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          categoria,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        clase?['nombre']?.toString() ?? 'Clase',
                        style: const TextStyle(
                          color: AppColors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        estudio?['nombre']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (fecha != null) ...[
                  const Icon(Icons.calendar_today_outlined,
                      size: 13, color: AppColors.grey),
                  const SizedBox(width: 5),
                  Text(
                    DateFormat('EEE d MMM · HH:mm', 'es').format(fecha),
                    style:
                        const TextStyle(color: AppColors.grey, fontSize: 13),
                  ),
                  const Spacer(),
                ],
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: esGratis
                        ? const Color(0xFFE8F5E9)
                        : AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    esGratis
                        ? 'Gratis'
                        : '$creditos crédito${creditos != 1 ? 's' : ''}',
                    style: TextStyle(
                      color: esGratis
                          ? const Color(0xFF2E7D32)
                          : AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton(
                      onPressed: onVerTicket,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Ver ticket',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton(
                      onPressed: onCancelar,
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            canCancel ? AppColors.error : AppColors.grey,
                        side: BorderSide(
                          color: canCancel
                              ? AppColors.error.withOpacity(0.4)
                              : AppColors.lightGrey,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoPlaceholder() {
    return Container(
      color: const Color(0xFFECE9E4),
      child: const Center(
        child: Icon(Icons.self_improvement_rounded,
            size: 32, color: AppColors.grey),
      ),
    );
  }
}

// ─── Historial Card ───────────────────────────────────────────────────────────

class _HistorialCard extends StatelessWidget {
  final Map<String, dynamic> reserva;

  const _HistorialCard({required this.reserva});

  @override
  Widget build(BuildContext context) {
    final clase = reserva['clases'] as Map<String, dynamic>?;
    final estudio = clase?['estudios'] as Map<String, dynamic>?;
    final fecha = clase?['fecha'] != null
        ? DateTime.tryParse(clase!['fecha'].toString())
        : null;
    final estado = reserva['estado'] as String? ?? '';
    final fotoUrl = (clase?['imagen_url'] ?? estudio?['foto_url'])?.toString();

    Color estadoColor;
    String estadoLabel;
    Color estadoBg;
    switch (estado) {
      case 'completada':
        estadoColor = const Color(0xFF2E7D32);
        estadoBg = const Color(0xFFE8F5E9);
        estadoLabel = 'Completada';
        break;
      case 'cancelada':
        estadoColor = AppColors.error;
        estadoBg = const Color(0xFFFFEBEE);
        estadoLabel = 'Cancelada';
        break;
      case 'cancelada_por_estudio':
        estadoColor = const Color(0xFFE65100);
        estadoBg = const Color(0xFFFFF3E0);
        estadoLabel = 'Cancelada por el estudio';
        break;
      default:
        estadoColor = AppColors.grey;
        estadoBg = AppColors.lightGrey;
        estadoLabel = estado.isNotEmpty
            ? '${estado[0].toUpperCase()}${estado.substring(1)}'
            : 'Desconocido';
    }
    final creditos = (reserva['creditos_usados'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 56,
              height: 56,
              child: fotoUrl != null && fotoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: fotoUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clase?['nombre']?.toString() ?? 'Clase',
                  style: const TextStyle(
                    color: AppColors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  estudio?['nombre']?.toString() ?? '',
                  style:
                      const TextStyle(color: AppColors.grey, fontSize: 12),
                ),
                if (fecha != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    DateFormat('d MMM yyyy · HH:mm', 'es').format(fecha),
                    style: const TextStyle(
                        color: AppColors.mutedText, fontSize: 11),
                  ),
                ],
                if (estado == 'cancelada_por_estudio' && creditos > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Se te devolvieron $creditos crédito${creditos != 1 ? 's' : ''}',
                    style: const TextStyle(
                      color: Color(0xFF2E7D32),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: estadoBg,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              estadoLabel,
              style: TextStyle(
                color: estadoColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFECE9E4),
      child: const Center(
        child: Icon(Icons.self_improvement_rounded,
            size: 24, color: AppColors.grey),
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onExplorar;

  const _EmptyState({
    required this.title,
    required this.subtitle,
    required this.onExplorar,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.calendar_today_outlined,
                color: AppColors.primary,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.black,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.grey,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onExplorar,
                child: const Text('Explorar ahora'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
