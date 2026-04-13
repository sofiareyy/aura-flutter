import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';
import 'admin_export_helper.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _service = AdminService();

  late DateTime _from;
  late DateTime _to;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _metrics;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 0);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.getDashboardMetrics(from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _metrics = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked == null) return;
    setState(() {
      _from = picked.start;
      _to = picked.end;
    });
    await _load();
  }

  Future<void> _setCurrentMonth() async {
    final now = DateTime.now();
    setState(() {
      _from = DateTime(now.year, now.month, 1);
      _to = DateTime(now.year, now.month + 1, 0);
    });
    await _load();
  }

  Future<void> _exportarResumen() async {
    final m = _metrics;
    if (m == null) return;
    final text = '''
Admin Aura
Período: ${_date(_from)} al ${_date(_to)}
Usuarios: ${m['usuarios_total'] ?? 0}
Usuarios activos: ${m['usuarios_activos'] ?? 0}
Estudios: ${m['estudios_total'] ?? 0}
Estudios activos: ${m['estudios_activos'] ?? 0}
Reservas hoy: ${m['reservas_hoy'] ?? 0}
Reservas del período: ${m['reservas_mes'] ?? 0}
Créditos consumidos: ${m['creditos_consumidos'] ?? 0}
Ingresos estimados: ${_money(m['ingresos_estimados'] ?? 0)}
Ocupación promedio: ${m['ocupacion_promedio'] ?? 0}%
Top estudio: ${m['top_estudio'] ?? 'Sin datos'}
Top clase: ${m['top_clase'] ?? 'Sin datos'}
Top categoría: ${m['top_categoria'] ?? 'Sin datos'}
''';
    final downloaded = await downloadAdminReport(
      filename: 'aura-admin-resumen.txt',
      content: text,
    );
    if (!downloaded) {
      await Clipboard.setData(ClipboardData(text: text));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          downloaded || kIsWeb
              ? 'Resumen descargado.'
              : 'Resumen copiado para compartir.',
        ),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = _metrics;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Admin Aura',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Resumen del negocio con foco operativo.',
                              style: TextStyle(color: AppColors.grey),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _pickRange,
                                  icon: const Icon(Icons.date_range_rounded),
                                  label:
                                      Text('${_date(_from)} - ${_date(_to)}'),
                                ),
                                TextButton(
                                  onPressed: _setCurrentMonth,
                                  child: const Text('Mes actual'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: m == null ? null : _exportarResumen,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Exportar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    _InfoCard(
                      title: 'No se pudo cargar el dashboard',
                      body: _error!,
                    )
                  else ...[
                    _HeroPanel(
                      reservasHoy: '${m?['reservas_hoy'] ?? 0}',
                      ingresos: _money(m?['ingresos_estimados'] ?? 0),
                      ocupacion: '${m?['ocupacion_promedio'] ?? 0}%',
                    ),
                    const SizedBox(height: 16),
                    const _SectionLabel('Base del producto'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _CompactCard(
                            title: 'Usuarios',
                            value: '${m?['usuarios_total'] ?? 0}',
                            subtitle: '${m?['usuarios_activos'] ?? 0} activos',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CompactCard(
                            title: 'Estudios',
                            value: '${m?['estudios_total'] ?? 0}',
                            subtitle: '${m?['estudios_activos'] ?? 0} activos',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _CompactCard(
                            title: 'Reservas totales',
                            value: '${m?['reservas_total'] ?? 0}',
                            subtitle: '${m?['reservas_mes'] ?? 0} en el período',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CompactCard(
                            title: 'Créditos usados',
                            value: '${m?['creditos_consumidos'] ?? 0}',
                            subtitle: 'Consumo del período',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _CompactCard(
                            title: 'Créditos en circulación',
                            value: '${m?['creditos_circulacion'] ?? 0}',
                            subtitle: 'Total en cuentas activas',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CompactCard(
                            title: 'Tasa de conversión',
                            value: '${m?['tasa_conversion'] ?? 0}%',
                            subtitle: 'Usuarios que reservaron',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const _SectionLabel('Qué está funcionando mejor'),
                    const SizedBox(height: 10),
                    _InfoCard(
                      title: 'Top del negocio',
                      body:
                          'Estudio con más reservas: ${m?['top_estudio'] ?? 'Sin datos'}\n'
                          'Clase más reservada: ${m?['top_clase'] ?? 'Sin datos'}\n'
                          'Categoría más activa: ${m?['top_categoria'] ?? 'Sin datos'}\n'
                          'Instructor más activo: ${m?['top_instructor'] ?? 'Sin datos'}\n'
                          'Hora pico de reservas: ${m?['hora_pico'] ?? 'Sin datos'}',
                    ),
                    const SizedBox(height: 12),
                    _InfoCard(
                      title: 'Actividad reciente',
                      body: (m?['actividad_reciente'] as String?) ??
                          'Todavía no hay suficiente actividad reciente para mostrar.',
                    ),
                    if ((m?['alertas'] as List?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 18),
                      const _SectionLabel('Alertas'),
                      const SizedBox(height: 10),
                      for (final alerta in (m!['alertas'] as List).cast<String>())
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _AlertCard(text: alerta),
                        ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

  String _money(dynamic value) {
    final amount = (value as num?)?.toInt() ?? 0;
    return '\$${NumberFormat('#,###', 'es_AR').format(amount).replaceAll(',', '.')}';
  }

  String _date(DateTime value) => DateFormat('dd/MM').format(value);
}

class _HeroPanel extends StatelessWidget {
  final String reservasHoy;
  final String ingresos;
  final String ocupacion;

  const _HeroPanel({
    required this.reservasHoy,
    required this.ingresos,
    required this.ocupacion,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hoy en Aura',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _HeroStat(label: 'Reservas', value: reservasHoy)),
              Expanded(child: _HeroStat(label: 'Ingresos', value: ingresos)),
              Expanded(child: _HeroStat(label: 'Ocupación', value: ocupacion)),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;

  const _HeroStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
            fontSize: 24,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}

class _CompactCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;

  const _CompactCard({
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.grey)),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String body;

  const _InfoCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: AppColors.grey, height: 1.5)),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final String text;

  const _AlertCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFCC02), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFE6A817)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF7A5800),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
