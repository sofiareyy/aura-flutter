import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';
import '../../widgets/ancho_maximo.dart';

class AdminReservasScreen extends StatefulWidget {
  const AdminReservasScreen({super.key});

  @override
  State<AdminReservasScreen> createState() => _AdminReservasScreenState();
}

class _AdminReservasScreenState extends State<AdminReservasScreen> {
  final _service = AdminService();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _reservas = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Se llama también después de guardar (tras un await): si la pantalla ya
    // se cerró, setState explotaría en release. (26/10/2026)
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.listReservas(search: _searchCtrl.text);
      if (!mounted) return;
      setState(() {
        _reservas = rows;
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

  /// Hora argentina "ahora", en el mismo marco naive que `clases.fecha`.
  DateTime get _ahoraAr =>
      DateTime.now().toUtc().subtract(const Duration(hours: 3));

  DateTime? _fechaClase(Map<String, dynamic> r) {
    final raw = r['clase_fecha']?.toString() ?? '';
    if (raw.isEmpty) return null;
    // Naive en hora argentina: se parsea como UTC para comparar en el mismo
    // marco que [_ahoraAr], sin depender de la zona del dispositivo.
    return DateTime.tryParse('${raw.replaceFirst(' ', 'T')}Z');
  }

  /// Sólo una reserva vigente de una clase que todavía no empezó se puede
  /// cancelar (16/11/2026). La base lo vuelve a controlar.
  bool _cancelable(Map<String, dynamic> r) {
    final estado = r['estado']?.toString();
    if (estado != 'confirmada' && estado != 'pre_confirmada') return false;
    final fecha = _fechaClase(r);
    return fecha != null && fecha.isAfter(_ahoraAr);
  }

  String _cuando(Map<String, dynamic> r) {
    final f = _fechaClase(r);
    if (f == null) return 'sin fecha';
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(f.day)}/${dos(f.month)} ${dos(f.hour)}:${dos(f.minute)}';
  }

  Future<void> _cancelar(Map<String, dynamic> r) async {
    final id = (r['id'] as num).toInt();
    final creditos = (r['creditos_usados'] as num?)?.toInt() ?? 0;
    final pagada = r['estado'] == 'confirmada' && creditos > 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar reserva'),
        content: Text(
          '${r['usuario_nombre'] ?? 'La alumna'} · ${r['clase_nombre'] ?? 'Clase'}'
          ' en ${r['estudio_nombre'] ?? 'el estudio'}, ${_cuando(r)}.\n\n'
          '${pagada ? 'Le devolvemos $creditos créditos (vencen en 90 días), ' : ''}'
          'se libera el lugar y le avisamos con una notificación y un mail.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar reserva'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final devueltos = await _service.cancelarReserva(id);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            devueltos > 0
                ? 'Reserva cancelada. Le devolvimos $devueltos créditos.'
                : 'Reserva cancelada.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: AnchoMaximo(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'Reservas',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Buscá y resolvé reservas problemáticas rápido.',
                    style: TextStyle(color: AppColors.grey),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Buscar por usuario, clase o estudio',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _load,
                      ),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    _ErrorCard(message: _error!)
                  else if (_reservas.isEmpty)
                    const _EmptyCard(message: 'No hay reservas para mostrar.')
                  else
                    ..._reservas.map(
                      (reserva) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    reserva['clase_nombre']?.toString() ??
                                        'Clase',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  reserva['estado']?.toString() ?? '',
                                  style: TextStyle(
                                    color: reserva['estado'] == 'cancelada'
                                        ? AppColors.error
                                        : AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${reserva['usuario_nombre'] ?? 'Usuario'} · ${reserva['estudio_nombre'] ?? 'Estudio'}',
                              style: const TextStyle(color: AppColors.grey),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Clase: ${_cuando(reserva)} · Créditos: ${reserva['creditos_usados'] ?? 0}',
                              style: const TextStyle(color: AppColors.grey),
                            ),
                            if (_cancelable(reserva)) ...[
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: () => _cancelar(reserva),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.error,
                                  side: const BorderSide(
                                    color: AppColors.error,
                                  ),
                                ),
                                child: const Text('Cancelar reserva'),
                              ),
                            ],
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

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(message, style: const TextStyle(color: AppColors.error)),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;

  const _EmptyCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(message, style: const TextStyle(color: AppColors.grey)),
    );
  }
}
