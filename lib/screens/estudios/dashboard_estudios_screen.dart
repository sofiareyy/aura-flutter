import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../services/estudio_admin_service.dart';
import '../../services/notificaciones_estudio_service.dart';
import '../../widgets/notificaciones_estudio_sheet.dart';

class DashboardEstudiosScreen extends StatefulWidget {
  const DashboardEstudiosScreen({super.key});

  @override
  State<DashboardEstudiosScreen> createState() => _DashboardEstudiosScreenState();
}

class _DashboardEstudiosScreenState extends State<DashboardEstudiosScreen> {
  final _service = EstudioAdminService();

  Map<String, dynamic>? _estudio;
  List<Map<String, dynamic>> _clases = [];
  List<Map<String, dynamic>> _reservas = [];
  List<Map<String, dynamic>> _actividad = [];
  bool _loading = true;
  String? _error;
  int _unreadNotifs = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final estudio = await _service.getCurrentStudio();
      final clases = await _service.getClasesDeEstudio(
        from: DateTime.now().subtract(const Duration(days: 30)),
      );
      final reservas = await _service.getReservasDeEstudio(limit: 120);

      int unread = 0;
      if (estudio != null) {
        final estudioId = (estudio['id'] as num?)?.toInt();
        if (estudioId != null) {
          try {
            unread = await NotificacionesEstudioService.instance
                .getUnreadCount(estudioId);
          } catch (_) {}
        }
      }

      if (!mounted) return;
      setState(() {
        _estudio = estudio;
        _clases = clases;
        _reservas = reservas;
        _actividad = _buildActividad(reservas, clases);
        _loading = false;
        _error = estudio == null ? 'No encontramos un estudio asociado.' : null;
        _unreadNotifs = unread;
      });
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
                label: 'Ingresos mes',
                accent: AppColors.white,
                change: _formatChange(_ingresosMes, _ingresosMesAnterior),
                changeColor: _colorForDelta(_ingresosMes - _ingresosMesAnterior),
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
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF7F5F2),
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                ),
                                child: const Row(
                                  children: [
                                    SizedBox(width: 56, child: Text('Hora', style: _kTableHeader)),
                                    SizedBox(width: 16),
                                    Expanded(child: Text('Clase', style: _kTableHeader)),
                                    SizedBox(width: 140, child: Text('Instructor', style: _kTableHeader)),
                                    SizedBox(width: 120, child: Text('Ocupación', style: _kTableHeader)),
                                    SizedBox(width: 90, child: Text('Estado', style: _kTableHeader, textAlign: TextAlign.center)),
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
                                      top: BorderSide(color: Colors.grey.shade100),
                                    ),
                                    borderRadius: i == clasesHoy.length - 1
                                        ? const BorderRadius.vertical(bottom: Radius.circular(16))
                                        : null,
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                                          clase['nombre']?.toString() ?? 'Clase',
                                          style: const TextStyle(fontSize: 14, color: AppColors.black, fontWeight: FontWeight.w600),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 140,
                                        child: Text(
                                          clase['instructor']?.toString() ?? '—',
                                          style: const TextStyle(fontSize: 13, color: Color(0xFF8F877F)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 120,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: progress,
                                                backgroundColor: const Color(0xFFF0EDE9),
                                                color: AppColors.primary,
                                                minHeight: 6,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _spotsLabel(clase),
                                              style: const TextStyle(fontSize: 11, color: Color(0xFF8F877F)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width: 90,
                                        child: Center(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: _colorForStatus(status),
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              status,
                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.black),
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
                                        style: const TextStyle(color: Color(0xFF625C57), fontSize: 13),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      item['time'] as String,
                                      style: const TextStyle(color: Color(0xFFB0A8A0), fontSize: 11),
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
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _estudio?['nombre']?.toString() ?? 'Estudio',
                                style: const TextStyle(
                                  color: AppColors.black,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Panel de socio Aura',
                                style: TextStyle(
                                  color: Color(0xFF9A928B),
                                  fontSize: 13,
                                ),
                              ),
                            ],
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
                                final estudioId =
                                    (_estudio?['id'] as num?)?.toInt();
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
                          _StatBox(
                            value: _reservasHoy.toString(),
                            label: 'Reservas hoy',
                            accent: const Color(0xFFDBF3E0),
                            change: _formatChange(_reservasHoy, _reservasAyer),
                            changeColor: _colorForDelta(_reservasHoy - _reservasAyer),
                          ),
                          const SizedBox(width: 8),
                          _StatBox(
                            value: _moneyCompact(_ingresosMes),
                            label: 'Ingresos mes',
                            accent: AppColors.white,
                            change: _formatChange(_ingresosMes, _ingresosMesAnterior),
                            changeColor: _colorForDelta(_ingresosMes - _ingresosMesAnterior),
                          ),
                          const SizedBox(width: 8),
                          _StatBox(
                            value: '${_ocupacionHoy}%',
                            label: 'Ocupación hoy',
                            accent: AppColors.white,
                            footer: '${clasesHoy.length} clases',
                            footerColor: AppColors.primary,
                          ),
                        ],
                      ),
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
                                  style: TextStyle(
                                    color: Color(0xFF8F877F),
                                  ),
                                ),
                              )
                            : Column(
                                children: clasesHoy.take(3).map((clase) {
                                  final status = _statusForClass(clase);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _TodayClassRow(
                                      hora: _timeForClass(clase),
                                      nombre: clase['nombre']?.toString() ?? 'Clase',
                                      instructor: clase['instructor']?.toString() ?? 'Sin instructor',
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
    }).toList()
      ..sort((a, b) => (a['fecha']?.toString() ?? '').compareTo(b['fecha']?.toString() ?? ''));
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
    final classIds = _clasesDelDia(day)
        .map((c) => (c['id'] as num?)?.toInt())
        .whereType<int>()
        .toSet();
    return _reservas.where((reserva) {
      final claseId = (reserva['clase_id'] as num?)?.toInt();
      final estado = reserva['estado']?.toString();
      return claseId != null &&
          classIds.contains(claseId) &&
          estado != 'cancelada';
    }).toList();
  }

  int _ingresosDelMes(DateTime date) {
    return _reservas.where((reserva) {
      final created = DateTime.tryParse(reserva['created_at']?.toString() ?? '');
      final estado = reserva['estado']?.toString();
      return created != null &&
          created.year == date.year &&
          created.month == date.month &&
          estado != 'cancelada';
    }).fold<int>(0, (acc, reserva) => acc + _montoReserva(reserva));
  }

  int _montoReserva(Map<String, dynamic> reserva) {
    final creditos = (reserva['creditos_usados'] as num?)?.toInt() ?? 0;
    final precioCredito = (_estudio?['valor_credito'] as num?)?.toInt() ?? 6000;
    final comision = (_estudio?['comision_aura'] as num?)?.toDouble() ?? 30;
    final bruto = creditos * precioCredito;
    return (bruto * ((100 - comision) / 100)).round();
  }

  List<Map<String, dynamic>> _buildActividad(
    List<Map<String, dynamic>> reservas,
    List<Map<String, dynamic>> clases,
  ) {
    final classMap = {
      for (final clase in clases)
        ((clase['id'] as num?)?.toInt()): clase['nombre']?.toString() ?? 'Clase'
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
    final end = dt.add(Duration(minutes: (clase['duracion_min'] as num?)?.toInt() ?? 60));
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
                  style: TextStyle(
                    color: Color(0xFFA7A09A),
                    fontSize: 16,
                  ),
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
    return Expanded(
      child: Container(
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
              style: const TextStyle(
                color: Color(0xFF8F877F),
                fontSize: 12,
              ),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                style: const TextStyle(
                  color: Color(0xFF6A635D),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
        style: const TextStyle(
          color: AppColors.black,
          fontSize: 14,
        ),
      ),
    );
  }
}
