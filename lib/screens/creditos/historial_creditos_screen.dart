import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_provider.dart';

class HistorialCreditosScreen extends StatefulWidget {
  const HistorialCreditosScreen({super.key});

  @override
  State<HistorialCreditosScreen> createState() => _HistorialCreditosScreenState();
}

class _HistorialCreditosScreenState extends State<HistorialCreditosScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<_Movimiento> _movimientos = [];
  int _saldoActual = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final userId = context.read<AppProvider>().userId;
      if (userId.isEmpty) throw Exception('Sin sesión activa.');

      final results = await Future.wait([
        _supabase
            .from('pagos')
            .select('id, type, status, amount, creditos, pack_nombre, plan_nombre, created_at')
            .eq('user_id', userId)
            .eq('status', 'approved')
            .order('created_at', ascending: false),
        _supabase
            .from('reservas')
            .select('id, creditos_usados, codigo_qr, created_at, clase_id')
            .eq('usuario_id', userId)
            .neq('estado', 'cancelada')
            .gt('creditos_usados', 0)
            .order('created_at', ascending: false),
      ]);

      final pagos = (results[0] as List).cast<Map<String, dynamic>>();
      final reservas = (results[1] as List).cast<Map<String, dynamic>>();

      // Enriquecer reservas con nombre de clase
      final clasesIds = reservas.map((r) => r['clase_id']).whereType<int>().toSet().toList();
      final Map<int, String> claseNombres = {};
      if (clasesIds.isNotEmpty) {
        final clasesRows = await _supabase
            .from('clases')
            .select('id, nombre')
            .inFilter('id', clasesIds);
        for (final c in (clasesRows as List).cast<Map<String, dynamic>>()) {
          final id = (c['id'] as num?)?.toInt();
          if (id != null) claseNombres[id] = c['nombre']?.toString() ?? 'Clase';
        }
      }

      final movs = <_Movimiento>[];

      for (final p in pagos) {
        final fecha = DateTime.tryParse(p['created_at']?.toString() ?? '');
        if (fecha == null) continue;
        final creditos = (p['creditos'] as num?)?.toInt() ?? 0;
        final tipo = p['type']?.toString() ?? 'pack';
        final nombre = (tipo == 'plan'
                ? p['plan_nombre']?.toString()
                : p['pack_nombre']?.toString()) ??
            (tipo == 'plan' ? 'Plan mensual' : 'Pack de créditos');
        movs.add(_Movimiento(
          fecha: fecha,
          tipo: _TipoMovimiento.ingreso,
          descripcion: nombre,
          creditos: creditos,
        ));
      }

      for (final r in reservas) {
        final fecha = DateTime.tryParse(r['created_at']?.toString() ?? '');
        if (fecha == null) continue;
        final creditos = (r['creditos_usados'] as num?)?.toInt() ?? 0;
        final claseId = (r['clase_id'] as num?)?.toInt();
        final nombreClase = (claseId != null ? claseNombres[claseId] : null) ?? 'Clase reservada';
        movs.add(_Movimiento(
          fecha: fecha,
          tipo: _TipoMovimiento.egreso,
          descripcion: nombreClase,
          creditos: creditos,
        ));
      }

      movs.sort((a, b) => b.fecha.compareTo(a.fecha));

      if (!mounted) return;
      setState(() {
        _movimientos = movs;
        _saldoActual = context.read<AppProvider>().usuario?.creditos ?? 0;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Historial de créditos'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _SaldoHeader(saldo: _saldoActual),
                  const SizedBox(height: 20),
                  if (_error != null)
                    Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.grey),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else if (_movimientos.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Column(
                        children: [
                          const Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            'Todavía no hay movimientos',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Comprá un pack o plan para sumar créditos.',
                            style: TextStyle(color: AppColors.grey, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: () => context.push('/comprar-creditos'),
                            child: const Text('Comprar créditos'),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final mov in _movimientos)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _MovimientoRow(movimiento: mov),
                      ),
                ],
              ),
            ),
    );
  }
}

enum _TipoMovimiento { ingreso, egreso }

class _Movimiento {
  final DateTime fecha;
  final _TipoMovimiento tipo;
  final String descripcion;
  final int creditos;

  const _Movimiento({
    required this.fecha,
    required this.tipo,
    required this.descripcion,
    required this.creditos,
  });
}

class _SaldoHeader extends StatelessWidget {
  final int saldo;

  const _SaldoHeader({required this.saldo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.toll_rounded, color: AppColors.primary, size: 28),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Saldo actual',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                '$saldo créditos',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MovimientoRow extends StatelessWidget {
  final _Movimiento movimiento;

  const _MovimientoRow({required this.movimiento});

  @override
  Widget build(BuildContext context) {
    final esIngreso = movimiento.tipo == _TipoMovimiento.ingreso;
    final color = esIngreso ? const Color(0xFF2E7D32) : const Color(0xFFE65100);
    final bgColor = esIngreso ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0);
    final signo = esIngreso ? '+' : '−';
    final fecha = DateFormat('d MMM yyyy · HH:mm', 'es').format(movimiento.fecha.toLocal());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: Icon(
              esIngreso ? Icons.add_rounded : Icons.remove_rounded,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movimiento.descripcion,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  fecha,
                  style: const TextStyle(color: AppColors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$signo${movimiento.creditos}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
