import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../utils/liquidacion.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../services/estudio_admin_service.dart';
import '../../services/reviews_service.dart';
import '../../utils/resenas.dart';
import '../../services/notificaciones_estudio_service.dart';
import '../../widgets/notificaciones_estudio_sheet.dart';

class DashboardEstudiosScreen extends StatefulWidget {
  const DashboardEstudiosScreen({super.key});

  @override
  State<DashboardEstudiosScreen> createState() =>
      _DashboardEstudiosScreenState();
}

class _DashboardEstudiosScreenState extends State<DashboardEstudiosScreen> {
  final _service = EstudioAdminService();

  Map<String, dynamic>? _estudio;
  Map<int, int> _desgloseResenas = const {};
  List<Map<String, dynamic>> _clases = [];
  List<Map<String, dynamic>> _reservas = [];
  List<Map<String, dynamic>> _actividad = [];
  List<Map<String, dynamic>> _misEstudios = const [];
  bool _loading = true;
  String? _error;
  int _unreadNotifs = 0;
  // FIX 4 — métricas del perfil.
  int _favoritos = 0;
  int _vistasMes = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _abrirSelectorEstudios() async {
    if (_misEstudios.length < 2) return;
    final seleccionado = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4CEC9),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Mis estudios',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ..._misEstudios.map((e) {
                final id = (e['estudio_id'] as num?)?.toInt();
                final nombre = e['nombre']?.toString() ?? 'Sin nombre';
                final isActive = e['is_active'] == true;
                final rol = e['rol']?.toString();
                final rolLabel = rol == 'profe' ? 'Profe' : 'Administrador';
                return ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    nombre,
                    style: TextStyle(
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: AppColors.black,
                    ),
                  ),
                  subtitle: Text(
                    rolLabel,
                    style: const TextStyle(color: AppColors.grey, fontSize: 12),
                  ),
                  trailing: isActive
                      ? const Icon(
                          Icons.check_rounded,
                          color: AppColors.primary,
                        )
                      : null,
                  onTap: () => Navigator.pop(ctx, id),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (seleccionado == null) return;
    final activoActual = (_estudio?['id'] as num?)?.toInt();
    if (seleccionado == activoActual) return;

    setState(() => _loading = true);
    final ok = await _service.setActiveEstudio(seleccionado);
    if (!mounted) return;
    if (!ok) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cambiar de estudio.')),
      );
      return;
    }
    // Refrescar el rol activo (roles múltiples): si el nuevo estudio es de
    // profe, hay que mandarla al panel limitado en vez del dashboard.
    await context.read<AppProvider>().refrescarUsuario();
    if (!mounted) return;
    final sel = _misEstudios.firstWhere(
      (e) => (e['estudio_id'] as num?)?.toInt() == seleccionado,
      orElse: () => const {},
    );
    if (sel['rol']?.toString() == 'profe') {
      context.go('/estudio/clases');
      return;
    }
    await _cargar();
  }

  void _mostrarTutorial() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _TutorialSheet(
        onCompletado: () async {
          await _service.marcarTutorialCompletado();
        },
      ),
    );
  }

  Future<void> _cargar() async {
    try {
      final results = await Future.wait([
        _service.getCurrentStudio(),
        _service.getClasesDeEstudio(
          from: DateTime.now().subtract(const Duration(days: 30)),
        ),
        _service.getReservasDeEstudio(limit: 120),
        _service.getTutorialCompletado(),
        _service.listMyStudios(),
      ]);
      final estudio = results[0] as Map<String, dynamic>?;
      final clases = results[1] as List<Map<String, dynamic>>;
      final reservas = results[2] as List<Map<String, dynamic>>;
      final tutorialOk = results[3] as bool;
      final misEstudios = results[4] as List<Map<String, dynamic>>;

      int unread = 0;
      Map<int, int> desgloseResenas = const {};
      int favoritos = 0;
      int vistasMes = 0;
      if (estudio != null) {
        final estudioId = (estudio['id'] as num?)?.toInt();
        if (estudioId != null) {
          try {
            unread = await NotificacionesEstudioService.instance.getUnreadCount(
              estudioId,
            );
          } catch (_) {}
          final metricas = await _service.getMetricasEstudio(estudioId);
          favoritos = metricas.favoritos;
          vistasMes = metricas.vistasMes;
          // El estudio no veía sus reseñas en ningún lado: le llegaban por
          // campanita y mail y ahí morían.
          try {
            desgloseResenas =
                await ReviewsService().getRatingBreakdown(estudioId);
          } catch (_) {}
        }
      }

      if (!mounted) return;
      setState(() {
        _estudio = estudio;
        _desgloseResenas = desgloseResenas;
        _clases = clases;
        _reservas = reservas;
        _actividad = _buildActividad(reservas, clases);
        _misEstudios = misEstudios;
        _loading = false;
        _error = estudio == null ? 'No encontramos un estudio asociado.' : null;
        _unreadNotifs = unread;
        _favoritos = favoritos;
        _vistasMes = vistasMes;
      });

      if (!tutorialOk) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _mostrarTutorial();
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar el dashboard del estudio.';
      });
    }
  }

  // ── Desktop ────────────────────────────────────────────────────────────────

  Widget _buildDesktopContent(List<Map<String, dynamic>> clasesHoy) {
    if (_error != null) return _DashboardError(message: _error!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 4 stat cards in a row
        Row(
          children: [
            Expanded(
              child: _StatBox(
                value: _reservasHoy.toString(),
                label: 'Reservas hoy',
                accent: const Color(0xFFDBF3E0),
                change: _formatChange(_reservasHoy, _reservasAyer),
                changeColor: _colorForDelta(_reservasHoy - _reservasAyer),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatBox(
                value: _moneyCompact(_ingresosMes),
                label: 'Ingresos mes (total)',
                accent: AppColors.white,
                change: _formatChange(_ingresosMes, _ingresosMesAnterior),
                changeColor: _colorForDelta(
                  _ingresosMes - _ingresosMesAnterior,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatBox(
                value: '${_ocupacionHoy}%',
                label: 'Ocupación hoy',
                accent: AppColors.white,
                footer: '${clasesHoy.length} clases',
                footerColor: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatBox(
                value: _clases.length.toString(),
                label: 'Clases totales',
                accent: AppColors.white,
                footer: 'últimos 30 días',
                footerColor: AppColors.grey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DesgloseMes(
          reservasClases: _reservasMesClases.length,
          ingresosClases: _ingresosMesClases,
          reservasWorkshops: _reservasMesWorkshops.length,
          ingresosWorkshops: _ingresosMesWorkshops,
          mostrarWorkshops: _tieneWorkshops,
          money: _moneyCompact,
        ),
        const SizedBox(height: 16),
        // La tarjeta de reseñas va en LAS DOS vistas. Estuvo sólo en mobile
        // y en una pantalla ancha desaparecía: el estudio no tenía por dónde
        // llegar a sus reseñas. El corte de layout es 768 px.
        _TarjetaResenas(
          desglose: _desgloseResenas,
          onTap: () {
            final id = (_estudio?['id'] as num?)?.toInt();
            if (id == null) return;
            context.push('/estudio/$id/resenas?dueno=1');
          },
        ),
        _misProfesQuickAction(),
        const SizedBox(height: 24),
        // Main content: classes table + activity panel
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel('Clases de hoy'),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(0),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: clasesHoy.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              'No hay clases cargadas para hoy.',
                              style: TextStyle(color: Color(0xFF8F877F)),
                            ),
                          )
                        : Column(
                            children: [
                              // Table header
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF7F5F2),
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(16),
                                  ),
                                ),
                                child: const Row(
                                  children: [
                                    SizedBox(
                                      width: 56,
                                      child: Text('Hora', style: _kTableHeader),
                                    ),
                                    SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        'Clase',
                                        style: _kTableHeader,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 140,
                                      child: Text(
                                        'Instructor',
                                        style: _kTableHeader,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 120,
                                      child: Text(
                                        'Ocupación',
                                        style: _kTableHeader,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 90,
                                      child: Text(
                                        'Estado',
                                        style: _kTableHeader,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ...clasesHoy.asMap().entries.map((entry) {
                                final i = entry.key;
                                final clase = entry.value;
                                final status = _statusForClass(clase);
                                final progress = _progressForClass(clase);
                                return Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      top: BorderSide(
                                        color: Colors.grey.shade100,
                                      ),
                                    ),
                                    borderRadius: i == clasesHoy.length - 1
                                        ? const BorderRadius.vertical(
                                            bottom: Radius.circular(16),
                                          )
                                        : null,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 56,
                                        child: Text(
                                          _timeForClass(clase),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: AppColors.black,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          clase['nombre']?.toString() ??
                                              'Clase',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: AppColors.black,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 140,
                                        child: Text(
                                          clase['instructor']?.toString() ??
                                              '—',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF8F877F),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 120,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: progress,
                                                backgroundColor: const Color(
                                                  0xFFF0EDE9,
                                                ),
                                                color: AppColors.primary,
                                                minHeight: 6,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _spotsLabel(clase),
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF8F877F),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width: 90,
                                        child: Center(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _colorForStatus(status),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              status,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.black,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 280,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel('Actividad reciente'),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: _actividad.isEmpty
                        ? const Text(
                            'Todavía no hay actividad.',
                            style: TextStyle(color: Color(0xFF8F877F)),
                          )
                        : Column(
                            children: _actividad.map((item) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: item['color'] as Color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        item['label'] as String,
                                        style: const TextStyle(
                                          color: Color(0xFF625C57),
                                          fontSize: 13,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      item['time'] as String,
                                      style: const TextStyle(
                                        color: Color(0xFFB0A8A0),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static const _kTableHeader = TextStyle(
    color: Color(0xFF888888),
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final clasesHoy = _clasesDelDia(DateTime.now());
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : RefreshIndicator(
                onRefresh: _cargar,
                color: AppColors.primary,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _buildDesktopContent(clasesHoy),
                ),
              ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SafeArea(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _cargar,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _misEstudios.length >= 2
                                ? _abrirSelectorEstudios
                                : null,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          _estudio?['nombre']?.toString() ??
                                              'Estudio',
                                          style: const TextStyle(
                                            color: AppColors.black,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (_misEstudios.length >= 2) ...[
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.unfold_more_rounded,
                                          size: 18,
                                          color: Color(0xFF8F877F),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _misEstudios.length >= 2
                                        ? 'Tocá para cambiar de estudio'
                                        : 'Panel de socio Aura',
                                    style: const TextStyle(
                                      color: Color(0xFF9A928B),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Stack(
                          alignment: Alignment.topRight,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.notifications_outlined,
                                color: Color(0xFF5F5953),
                              ),
                              onPressed: () {
                                final estudioId = (_estudio?['id'] as num?)
                                    ?.toInt();
                                if (estudioId == null) return;
                                showNotificacionesEstudioSheet(
                                  context,
                                  estudioId: estudioId,
                                  onRead: () =>
                                      setState(() => _unreadNotifs = 0),
                                );
                              },
                            ),
                            if (_unreadNotifs > 0)
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
                        const SizedBox(width: 4),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => context.go('/estudio/perfil'),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                _studioInitials,
                                style: const TextStyle(
                                  color: AppColors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _HeroSummary(clases: clasesHoy),
                    const SizedBox(height: 8),
                    if (_error != null) _DashboardError(message: _error!),
                    if (_error == null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: _StatBox(
                              value: _reservasHoy.toString(),
                              label: 'Reservas hoy',
                              accent: const Color(0xFFDBF3E0),
                              change: _formatChange(
                                _reservasHoy,
                                _reservasAyer,
                              ),
                              changeColor: _colorForDelta(
                                _reservasHoy - _reservasAyer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _StatBox(
                              value: _moneyCompact(_ingresosMes),
                              label: 'Ingresos mes (total)',
                              accent: AppColors.white,
                              change: _formatChange(
                                _ingresosMes,
                                _ingresosMesAnterior,
                              ),
                              changeColor: _colorForDelta(
                                _ingresosMes - _ingresosMesAnterior,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _StatBox(
                              value: '${_ocupacionHoy}%',
                              label: 'Ocupación hoy',
                              accent: AppColors.white,
                              footer: '${clasesHoy.length} clases',
                              footerColor: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _DesgloseMes(
                        reservasClases: _reservasMesClases.length,
                        ingresosClases: _ingresosMesClases,
                        reservasWorkshops: _reservasMesWorkshops.length,
                        ingresosWorkshops: _ingresosMesWorkshops,
                        mostrarWorkshops: _tieneWorkshops,
                        money: _moneyCompact,
                      ),
                      const SizedBox(height: 12),
                      _misProfesQuickAction(),
                      const SizedBox(height: 18),
                      const _SectionLabel('Clases de hoy'),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: clasesHoy.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'No hay clases cargadas para hoy.',
                                  style: TextStyle(color: Color(0xFF8F877F)),
                                ),
                              )
                            : Column(
                                children: clasesHoy.take(3).map((clase) {
                                  final status = _statusForClass(clase);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _TodayClassRow(
                                      hora: _timeForClass(clase),
                                      nombre:
                                          clase['nombre']?.toString() ??
                                          'Clase',
                                      instructor:
                                          clase['instructor']?.toString() ??
                                          'Sin instructor',
                                      progress: _progressForClass(clase),
                                      status: status,
                                      statusColor: _colorForStatus(status),
                                      spots: _spotsLabel(clase),
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                      const SizedBox(height: 18),
                      _buildEstadisticasSection(),
                      const SizedBox(height: 18),
                      const _SectionLabel('Actividad reciente'),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: _actividad.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(8),
                                child: Text(
                                  'Todavía no hay actividad reciente en este estudio.',
                                  style: TextStyle(color: Color(0xFF8F877F)),
                                ),
                              )
                            : Column(
                                children: _actividad.take(4).map((item) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: item['color'] as Color,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            item['label'] as String,
                                            style: const TextStyle(
                                              color: Color(0xFF625C57),
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          item['time'] as String,
                                          style: const TextStyle(
                                            color: Color(0xFFB0A8A0),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Center(
                      child: TextButton.icon(
                        onPressed: _mostrarTutorial,
                        icon: const Icon(
                          Icons.help_outline_rounded,
                          size: 16,
                          color: Color(0xFFB0A8A0),
                        ),
                        label: const Text(
                          'Ver tutorial de nuevo',
                          style: TextStyle(
                            color: Color(0xFFB0A8A0),
                            fontSize: 13,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  List<Map<String, dynamic>> _clasesDelDia(DateTime day) {
    return _clases.where((clase) {
      final dt = DateTime.tryParse(clase['fecha']?.toString() ?? '');
      return dt != null &&
          dt.year == day.year &&
          dt.month == day.month &&
          dt.day == day.day;
    }).toList()..sort(
      (a, b) => (a['fecha']?.toString() ?? '').compareTo(
        b['fecha']?.toString() ?? '',
      ),
    );
  }

  int get _reservasHoy => _reservasDelDia(DateTime.now()).length;

  int get _reservasAyer =>
      _reservasDelDia(DateTime.now().subtract(const Duration(days: 1))).length;

  int get _ingresosMes => _ingresosDelMes(DateTime.now());

  int get _ingresosMesAnterior {
    final now = DateTime.now();
    final previous = DateTime(now.year, now.month - 1, 1);
    return _ingresosDelMes(previous);
  }

  int get _ocupacionHoy {
    final clasesHoy = _clasesDelDia(DateTime.now());
    if (clasesHoy.isEmpty) return 0;

    int totalCupos = 0;
    int ocupados = 0;
    for (final clase in clasesHoy) {
      final total = (clase['lugares_total'] as num?)?.toInt() ?? 0;
      final disponibles = (clase['lugares_disponibles'] as num?)?.toInt() ?? 0;
      totalCupos += total;
      ocupados += (total - disponibles).clamp(0, total);
    }
    if (totalCupos == 0) return 0;
    return ((ocupados / totalCupos) * 100).round();
  }

  List<Map<String, dynamic>> _reservasDelDia(DateTime day) {
    final classIds = _clasesDelDia(
      day,
    ).map((c) => (c['id'] as num?)?.toInt()).whereType<int>().toSet();
    return _reservas.where((reserva) {
      final claseId = (reserva['clase_id'] as num?)?.toInt();
      final estado = reserva['estado']?.toString();
      return claseId != null &&
          classIds.contains(claseId) &&
          estado != 'cancelada';
    }).toList();
  }

  int _ingresosDelMes(DateTime date) =>
      Liquidacion.netoTotal(_reservasDelMes(date), _estudio);

  /// Reservas del mes que el estudio cobra. Antes filtraba solo
  /// `!= 'cancelada'`, así que sumaba `cancelada_por_estudio` (créditos ya
  /// reembolsados) y `pre_confirmada` (todavía sin consumir) como ingreso.
  List<Map<String, dynamic>> _reservasDelMes(DateTime date) {
    return _reservas.where((reserva) {
      final created = DateTime.tryParse(
        reserva['created_at']?.toString() ?? '',
      );
      final estado = reserva['estado']?.toString();
      return created != null &&
          created.year == date.year &&
          created.month == date.month &&
          AppConstants.estadosLiquidables.contains(estado);
    }).toList();
  }

  // ── FIX 5: clases y workshops se miden por separado ──────────────────────
  // Antes el dashboard sumaba todo junto, así que un workshop puntual de
  // monto alto tapaba cómo venían las clases (y al revés). Además liquidan
  // con comisiones distintas: 30% clases, 15% workshops.

  bool _esWorkshop(Map<String, dynamic> r) =>
      r['_clase_tipo']?.toString() == 'workshop';

  List<Map<String, dynamic>> get _reservasMesClases =>
      _reservasDelMes(DateTime.now()).where((r) => !_esWorkshop(r)).toList();

  List<Map<String, dynamic>> get _reservasMesWorkshops =>
      _reservasDelMes(DateTime.now()).where(_esWorkshop).toList();

  int get _ingresosMesClases =>
      Liquidacion.netoTotal(_reservasMesClases, _estudio);

  int get _ingresosMesWorkshops =>
      Liquidacion.netoTotal(_reservasMesWorkshops, _estudio);

  /// True si el estudio tiene algún workshop en el mes. Sin esto le
  /// mostraríamos una sección vacía a los estudios que solo dan clases.
  bool get _tieneWorkshops => _reservasMesWorkshops.isNotEmpty;

  int _montoReserva(Map<String, dynamic> reserva) =>
      Liquidacion.netoReserva(reserva, _estudio);

  List<Map<String, dynamic>> _buildActividad(
    List<Map<String, dynamic>> reservas,
    List<Map<String, dynamic>> clases,
  ) {
    final classMap = {
      for (final clase in clases)
        ((clase['id'] as num?)?.toInt()):
            clase['nombre']?.toString() ?? 'Clase',
    };

    return reservas.take(8).map((reserva) {
      final estado = reserva['estado']?.toString() ?? '';
      final claseId = (reserva['clase_id'] as num?)?.toInt();
      final claseNombre = classMap[claseId] ?? 'Clase';
      late final String label;
      late final Color color;
      if (estado == 'presente') {
        label = 'Asistencia confirmada en $claseNombre';
        color = const Color(0xFF35C759);
      } else if (estado == 'cancelada') {
        label = 'Reserva cancelada en $claseNombre';
        color = const Color(0xFFE53935);
      } else {
        label = 'Nueva reserva en $claseNombre';
        color = AppColors.primary;
      }
      return {
        'label': label,
        'color': color,
        'time': _relative(reserva['created_at']?.toString()),
      };
    }).toList();
  }

  String get _studioInitials {
    final nombre = _estudio?['nombre']?.toString() ?? 'Estudio';
    final parts = nombre.split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return nombre.substring(0, nombre.length >= 2 ? 2 : 1).toUpperCase();
  }

  String _timeForClass(Map<String, dynamic> clase) {
    final dt = DateTime.tryParse(clase['fecha']?.toString() ?? '');
    if (dt == null) return '07:00';
    return DateFormat('HH:mm').format(dt);
  }

  double _progressForClass(Map<String, dynamic> clase) {
    final total = (clase['lugares_total'] as num?)?.toDouble() ?? 0;
    final disponibles = (clase['lugares_disponibles'] as num?)?.toDouble() ?? 0;
    if (total <= 0) return 0.0;
    return ((total - disponibles) / total).clamp(0.0, 1.0);
  }

  String _spotsLabel(Map<String, dynamic> clase) {
    final total = (clase['lugares_total'] as num?)?.toInt() ?? 0;
    final disponibles = (clase['lugares_disponibles'] as num?)?.toInt() ?? 0;
    final ocupados = (total - disponibles).clamp(0, total);
    return '$ocupados/$total lugares';
  }

  String _statusForClass(Map<String, dynamic> clase) {
    final dt = DateTime.tryParse(clase['fecha']?.toString() ?? '');
    if (dt == null) return 'Programada';
    final now = DateTime.now();
    final end = dt.add(
      Duration(minutes: (clase['duracion_min'] as num?)?.toInt() ?? 60),
    );
    if (dt.isBefore(now) && end.isAfter(now)) return 'Activa';
    if (dt.isAfter(now) && dt.difference(now).inHours < 3) return 'Próxima';
    return 'Programada';
  }

  Color _colorForStatus(String status) {
    switch (status) {
      case 'Activa':
        return const Color(0xFFCFF5D7);
      case 'Próxima':
        return const Color(0xFFFFEFAF);
      default:
        return const Color(0xFFE6EBF7);
    }
  }

  String _relative(String? raw) {
    final dt = DateTime.tryParse(raw ?? '');
    if (dt == null) return '1h';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  String _formatChange(int current, int previous) {
    if (current == previous) return '0%';
    if (previous <= 0) return current > 0 ? '+100%' : '0%';
    final delta = ((current - previous) / previous) * 100;
    final rounded = delta.round();
    return rounded > 0 ? '+$rounded%' : '$rounded%';
  }

  Color _colorForDelta(int delta) {
    if (delta > 0) return const Color(0xFF2FAD5B);
    if (delta < 0) return const Color(0xFFE53935);
    return const Color(0xFF8F877F);
  }

  String _moneyCompact(int value) {
    if (value >= 1000000) return '\$${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '\$${(value / 1000).round()}k';
    return '\$$value';
  }

  // ── Estadísticas section ──────────────────────────────────────────────────

  /// Acceso rápido a "Mis Profes" (F2). Lleva al perfil del estudio, donde
  /// está la sección para gestionar profes. No duplica el "cambiar a usuario".
  Widget _misProfesQuickAction() {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => context.go('/estudio/perfil'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.groups_2_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mis Profes',
                      style: TextStyle(
                        color: AppColors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Ver y gestionar las profes del estudio',
                      style: TextStyle(color: AppColors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStatCard(String emoji, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF8F877F), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadisticasSection() {
    final now = DateTime.now();

    // ── Clase más popular ────────────────────────────────────────────────────
    final claseCounts = <int, int>{};
    for (final r in _reservas) {
      final claseId = (r['clase_id'] as num?)?.toInt();
      if (claseId != null)
        claseCounts[claseId] = (claseCounts[claseId] ?? 0) + 1;
    }
    String clasePopular = 'Sin datos';
    if (claseCounts.isNotEmpty) {
      final topId = claseCounts.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
      final topClase = _clases.firstWhere(
        (c) => (c['id'] as num?)?.toInt() == topId,
        orElse: () => {},
      );
      if (topClase.isNotEmpty) {
        clasePopular = topClase['nombre']?.toString() ?? 'Sin datos';
      }
    }

    // ── Top 3 clases por reservas ────────────────────────────────────────────
    final top3 = <({String nombre, int reservas})>[];
    {
      final ordenadas = claseCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in ordenadas.take(3)) {
        final c = _clases.firstWhere(
          (x) => (x['id'] as num?)?.toInt() == e.key,
          orElse: () => <String, dynamic>{},
        );
        final nombre = c.isNotEmpty
            ? (c['nombre']?.toString() ?? 'Clase')
            : 'Clase';
        top3.add((nombre: nombre, reservas: e.value));
      }
    }

    // ── Horario pico ─────────────────────────────────────────────────────────
    final horaCounts = <int, int>{};
    // Build set of clase_ids that have reservas
    final claseIdsConReservas = claseCounts.keys.toSet();
    for (final clase in _clases) {
      final claseId = (clase['id'] as num?)?.toInt();
      if (claseId == null || !claseIdsConReservas.contains(claseId)) continue;
      final dt = DateTime.tryParse(clase['fecha']?.toString() ?? '');
      if (dt == null) continue;
      final hora = dt.hour;
      horaCounts[hora] = (horaCounts[hora] ?? 0) + 1;
    }
    String horarioPico = 'Sin datos';
    if (horaCounts.isNotEmpty) {
      final topHora = horaCounts.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
      horarioPico = '${topHora.toString().padLeft(2, '0')}:00 hs';
    }

    // ── Tasa de ocupación (clases del mes actual) ────────────────────────────
    final clasesDelMes = _clases.where((c) {
      final dt = DateTime.tryParse(c['fecha']?.toString() ?? '');
      return dt != null && dt.year == now.year && dt.month == now.month;
    }).toList();

    // Tasa de ocupación del mes = reservas del mes / cupos totales del mes.
    int cuposMes = 0;
    for (final clase in clasesDelMes) {
      cuposMes += (clase['lugares_total'] as num?)?.toInt() ?? 0;
    }
    final idsMes = clasesDelMes
        .map((c) => (c['id'] as num?)?.toInt())
        .whereType<int>()
        .toSet();
    int reservasMes = 0;
    for (final r in _reservas) {
      final cid = (r['clase_id'] as num?)?.toInt();
      if (cid != null && idsMes.contains(cid)) reservasMes++;
    }
    final tasaOcupacion = cuposMes > 0
        ? (reservasMes / cuposMes * 100).clamp(0, 100)
        : 0.0;

    // ── Reservas por día de semana (mes actual) ──────────────────────────────
    // Build clase fecha map
    final claseFechaMap = <int, DateTime>{};
    for (final clase in _clases) {
      final claseId = (clase['id'] as num?)?.toInt();
      final dt = DateTime.tryParse(clase['fecha']?.toString() ?? '');
      if (claseId != null && dt != null) claseFechaMap[claseId] = dt;
    }

    final diasCount = List<int>.filled(7, 0); // 0=Mon..6=Sun
    for (final r in _reservas) {
      final claseId = (r['clase_id'] as num?)?.toInt();
      if (claseId == null) continue;
      final dt = claseFechaMap[claseId];
      if (dt == null || dt.year != now.year || dt.month != now.month) continue;
      // DateTime.weekday: 1=Mon..7=Sun
      diasCount[dt.weekday - 1]++;
    }

    final maxDia = diasCount.reduce((a, b) => a > b ? a : b);
    final diasLabels = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Estadísticas del mes'),
        const SizedBox(height: 10),
        // Favoritos + vistas del perfil (FIX 4).
        Row(
          children: [
            Expanded(child: _miniStatCard('❤️', '$_favoritos', 'En favoritos')),
            const SizedBox(width: 8),
            Expanded(
              child: _miniStatCard('👁️', '$_vistasMes', 'Vistas del mes'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _TarjetaResenas(
          desglose: _desgloseResenas,
          onTap: () {
            final id = (_estudio?['id'] as num?)?.toInt();
            if (id == null) return;
            context.push('/estudio/$id/resenas?dueno=1');
          },
        ),
        // 3 stat cards
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('⭐', style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 6),
                    Text(
                      clasePopular,
                      style: const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Clase popular',
                      style: TextStyle(color: Color(0xFF8F877F), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🕐', style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 6),
                    Text(
                      horarioPico,
                      style: const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Horario pico',
                      style: TextStyle(color: Color(0xFF8F877F), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('📈', style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 6),
                    Text(
                      '${tasaOcupacion.round()}%',
                      style: const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Ocupación mes',
                      style: TextStyle(color: Color(0xFF8F877F), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Top 3 clases más populares (FIX 4).
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Clases más populares',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              if (top3.isEmpty)
                const Text(
                  'Todavía no hay reservas para rankear.',
                  style: TextStyle(color: Color(0xFF8F877F), fontSize: 12),
                )
              else
                ...top3.asMap().entries.map((entry) {
                  final i = entry.key;
                  final t = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryLight,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            t.nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF1A1A1A),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${t.reservas} reserva${t.reservas == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: Color(0xFF8F877F),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Bar chart by day of week
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Reservas por día',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              maxDia == 0
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Sin datos este mes',
                          style: TextStyle(
                            color: Color(0xFF8F877F),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List.generate(7, (i) {
                        final count = diasCount[i];
                        final barHeight = maxDia > 0
                            ? (count / maxDia) * 60.0
                            : 0.0;
                        final isMax = count == maxDia && maxDia > 0;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (isMax)
                                  Text(
                                    '$count',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                const SizedBox(height: 2),
                                Container(
                                  height: barHeight.clamp(4.0, 60.0),
                                  decoration: BoxDecoration(
                                    color: isMax
                                        ? AppColors.primary.withOpacity(0.9)
                                        : AppColors.primary.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  diasLabels[i],
                                  style: const TextStyle(
                                    color: Color(0xFF8F877F),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroSummary extends StatelessWidget {
  final List<Map<String, dynamic>> clases;

  const _HeroSummary({required this.clases});

  @override
  Widget build(BuildContext context) {
    final today = DateFormat("EEEE d 'de' MMMM", 'es').format(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.blackSoft,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'HOY',
                    style: TextStyle(
                      color: Color(0xFF9A928B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    toBeginningOfSentenceCase(today) ?? today,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go('/estudio/clases'),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFF40261B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.calendar_today_outlined,
                    color: AppColors.primary,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${clases.length}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 58,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(width: 10),
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'clases hoy',
                  style: TextStyle(color: Color(0xFFA7A09A), fontSize: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value;
  final String label;
  final Color accent;
  final String? change;
  final Color? changeColor;
  final String? footer;
  final Color? footerColor;

  const _StatBox({
    required this.value,
    required this.label,
    required this.accent,
    this.change,
    this.changeColor,
    this.footer,
    this.footerColor,
  });

  @override
  Widget build(BuildContext context) {
    // Sin Expanded acá: quien lo pone en un Row decide el flex. Antes lo
    // devolvía envuelto y ADEMÁS los callers lo envolvían -> "Incorrect use
    // of ParentDataWidget" en debug (medido el 25/8 en el build web).
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppColors.black,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF8F877F), fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (change != null)
            Text(
              change!,
              style: TextStyle(
                color: changeColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            )
          else if (footer != null)
            Text(
              footer!,
              style: TextStyle(
                color: footerColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF8F877F),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _TodayClassRow extends StatelessWidget {
  final String hora;
  final String nombre;
  final String instructor;
  final double progress;
  final String status;
  final Color statusColor;
  final String spots;

  const _TodayClassRow({
    required this.hora,
    required this.nombre,
    required this.instructor,
    required this.progress,
    required this.status,
    required this.statusColor,
    required this.spots,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFAF8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.blackSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hora,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: const TextStyle(
                        color: AppColors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      instructor,
                      style: const TextStyle(
                        color: Color(0xFF8F877F),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: const TextStyle(
                    color: Color(0xFF5F5953),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    color: AppColors.primary,
                    backgroundColor: const Color(0xFFEDE7E1),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                spots,
                style: const TextStyle(color: Color(0xFF6A635D), fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Tutorial de bienvenida ───────────────────────────────────────────────────

class _TutorialSheet extends StatefulWidget {
  final Future<void> Function() onCompletado;

  const _TutorialSheet({required this.onCompletado});

  @override
  State<_TutorialSheet> createState() => _TutorialSheetState();
}

class _TutorialSheetState extends State<_TutorialSheet> {
  int _paso = 0;
  bool _guardando = false;

  static const _pasos = [
    _PasoData(
      icono: Icons.check_circle_rounded,
      titulo: '¡Bienvenido a Aura! 🧡',
      cuerpo:
          'En 3 pasos rápidos te mostramos cómo empezar a recibir reservas y cobrar.',
      boton: 'Empezar →',
    ),
    _PasoData(
      icono: Icons.calendar_month_rounded,
      titulo: 'Cargá tu primera clase',
      cuerpo:
          'Tocá el botón "+" y elegí "Nueva clase" (o "Nuevo workshop").\nElegí el horario, los cupos y listo.\nTus clases aparecen para todos los usuarios de Aura en Buenos Aires.',
      boton: 'Entendido →',
    ),
    _PasoData(
      icono: Icons.qr_code_scanner_rounded,
      titulo: 'El día de la clase',
      cuerpo:
          'Abrí Asistencia, escaneá el QR del alumno y confirmá su presencia.\nTambién podés marcar manualmente tocando su nombre en la lista.',
      boton: 'Ir al panel →',
    ),
  ];

  Future<void> _avanzar() async {
    if (_paso < _pasos.length - 1) {
      setState(() => _paso++);
    } else {
      setState(() => _guardando = true);
      await widget.onCompletado();
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final paso = _pasos[_paso];
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle naranja
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFE8763A),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 28),
          // Ícono
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFE8763A),
              shape: BoxShape.circle,
            ),
            child: Icon(paso.icono, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 20),
          // Título
          Text(
            paso.titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          // Cuerpo
          Text(
            paso.cuerpo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF8F877F),
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 28),
          // Dots indicador de progreso
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_pasos.length, (i) {
              final activo = i == _paso;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: activo ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: activo
                      ? const Color(0xFFE8763A)
                      : const Color(0xFF3A3A3A),
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          // Botón
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _guardando ? null : _avanzar,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE8763A),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: _guardando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(paso.boton),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasoData {
  final IconData icono;
  final String titulo;
  final String cuerpo;
  final String boton;

  const _PasoData({
    required this.icono,
    required this.titulo,
    required this.cuerpo,
    required this.boton,
  });
}

class _DashboardError extends StatelessWidget {
  final String message;

  const _DashboardError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.black, fontSize: 14),
      ),
    );
  }
}

/// FIX 5 — Desglose del mes separando clases de workshops.
///
/// Antes el dashboard sumaba todo junto y un workshop puntual de monto alto
/// tapaba cómo venían las clases regulares (o al revés). Además liquidan con
/// comisiones distintas — 30% las clases, 15% los workshops — así que el
/// total mezclado no permitía entender de dónde salió la plata.
class _DesgloseMes extends StatelessWidget {
  final int reservasClases;
  final int ingresosClases;
  final int reservasWorkshops;
  final int ingresosWorkshops;

  /// Los estudios que no hacen workshops no ven una sección vacía.
  final bool mostrarWorkshops;
  final String Function(int) money;

  const _DesgloseMes({
    required this.reservasClases,
    required this.ingresosClases,
    required this.reservasWorkshops,
    required this.ingresosWorkshops,
    required this.mostrarWorkshops,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DESGLOSE DEL MES',
            style: TextStyle(
              color: Color(0xFF8F877F),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          _DesgloseFila(
            icon: Icons.fitness_center_rounded,
            titulo: 'Clases',
            reservas: reservasClases,
            ingresos: money(ingresosClases),
          ),
          if (mostrarWorkshops) ...[
            const Divider(height: 20, color: Color(0xFFEDE7E1)),
            _DesgloseFila(
              icon: Icons.celebration_rounded,
              titulo: 'Workshops y experiencias',
              reservas: reservasWorkshops,
              ingresos: money(ingresosWorkshops),
            ),
          ],
        ],
      ),
    );
  }
}

class _DesgloseFila extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final int reservas;
  final String ingresos;

  const _DesgloseFila({
    required this.icon,
    required this.titulo,
    required this.reservas,
    required this.ingresos,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  color: AppColors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$reservas reserva${reservas == 1 ? '' : 's'}',
                style: const TextStyle(color: Color(0xFF8F877F), fontSize: 12),
              ),
            ],
          ),
        ),
        Text(
          ingresos,
          style: const TextStyle(
            color: AppColors.black,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}


/// Las reseñas del estudio en su Dashboard. Antes le llegaban por campanita y
/// mail y no tenía dónde verlas: para leerlas tenía que entrar como usuaria a
/// su propio perfil público. Abre la pantalla completa (la misma que ve la
/// alumna, con ?dueno=1 para el título).
class _TarjetaResenas extends StatelessWidget {
  final Map<int, int> desglose;
  final VoidCallback onTap;

  const _TarjetaResenas({required this.desglose, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final total = Resenas.totalDe(desglose);
    final promedio = Resenas.promedioDe(desglose);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: total == 0 ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.star_rounded,
                  color: AppColors.warning, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      total == 0
                          ? 'Sin reseñas todavía'
                          : '${Resenas.formatearPromedio(promedio)} · ${Resenas.etiquetaTotal(total)}',
                      style: const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      total == 0
                          ? 'Cuando tus alumnas dejen su opinión, aparece acá'
                          : 'Ver lo que dicen tus alumnas',
                      style: const TextStyle(
                          color: Color(0xFF8F877F), fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (total > 0)
                const Icon(Icons.chevron_right_rounded,
                    color: Color(0xFFC7C0B9)),
            ],
          ),
        ),
      ),
    );
  }
}
