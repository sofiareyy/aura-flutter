import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';

class AdminLiquidacionesScreen extends StatefulWidget {
  const AdminLiquidacionesScreen({super.key});

  @override
  State<AdminLiquidacionesScreen> createState() =>
      _AdminLiquidacionesScreenState();
}

class _AdminLiquidacionesScreenState extends State<AdminLiquidacionesScreen> {
  final _client = Supabase.instance.client;

  // Últimos 6 meses (más reciente primero)
  late List<String> _meses;
  late String _mesSeleccionado;

  bool _loading = true;
  String? _error;

  // Por estudio: { estudio_id, nombre, cantidad_reservas, monto_total, monto_pagar, estado, fecha_pago, comprobante_nota }
  List<Map<String, dynamic>> _estudios = [];

  // Historial expandido
  bool _historialExpanded = false;
  bool _loadingHistorial = false;
  List<Map<String, dynamic>> _historial = [];

  @override
  void initState() {
    super.initState();
    _meses = _ultimos6Meses();
    _mesSeleccionado = _meses.first;
    _cargar();
  }

  // ── Helpers de fecha ─────────────────────────────────────────────────────

  List<String> _ultimos6Meses() {
    final now = DateTime.now();
    return List.generate(6, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    });
  }

  DateTime _inicioMes(String mes) {
    final parts = mes.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
  }

  DateTime _finMes(String mes) {
    final inicio = _inicioMes(mes);
    return DateTime(inicio.year, inicio.month + 1, 1)
        .subtract(const Duration(seconds: 1));
  }

  String _labelMes(String mes) {
    final d = _inicioMes(mes);
    return DateFormat("MMMM yyyy", 'es').format(d);
  }

  // ── Data loading ─────────────────────────────────────────────────────────

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final inicio = _inicioMes(_mesSeleccionado).toIso8601String();
      final fin = _finMes(_mesSeleccionado).toIso8601String();

      // 1. Traer reservas del mes con estudio info
      final reservas = await _client
          .from('reservas')
          .select('estudio_id, creditos_usados, clases(estudio_id)')
          .inFilter('estado', ['confirmada', 'presente'])
          .gte('created_at', inicio)
          .lte('created_at', fin);

      // 2. Traer todos los estudios activos
      final estudiosData = await _client
          .from('estudios')
          .select('id, nombre')
          .eq('activo', true)
          .order('nombre');

      // 3. Traer liquidaciones ya registradas para este mes
      final liquidaciones = await _client
          .from('liquidaciones')
          .select()
          .eq('mes', _mesSeleccionado);

      // 4. Agrupar reservas por estudio
      final Map<int, int> creditosPorEstudio = {};
      final Map<int, int> reservasPorEstudio = {};

      for (final r in (reservas as List)) {
        final esId = (r['estudio_id'] as num?)?.toInt();
        if (esId == null) continue;
        final cred = (r['creditos_usados'] as num?)?.toInt() ?? 0;
        creditosPorEstudio[esId] = (creditosPorEstudio[esId] ?? 0) + cred;
        reservasPorEstudio[esId] = (reservasPorEstudio[esId] ?? 0) + 1;
      }

      // Mapa de liquidaciones registradas
      final Map<int, Map<String, dynamic>> liqMap = {};
      for (final l in (liquidaciones as List)) {
        final esId = (l['estudio_id'] as num?)?.toInt();
        if (esId != null) liqMap[esId] = Map<String, dynamic>.from(l);
      }

      // 5. Construir lista solo de estudios con reservas
      final List<Map<String, dynamic>> resultado = [];
      for (final e in (estudiosData as List)) {
        final esId = (e['id'] as num).toInt();
        final cantReservas = reservasPorEstudio[esId] ?? 0;
        if (cantReservas == 0) continue;

        final creditos = creditosPorEstudio[esId] ?? 0;
        final montoTotal = creditos * 1000;
        final montoPagar = (montoTotal * 0.70).round();

        final liq = liqMap[esId];
        resultado.add({
          'estudio_id': esId,
          'nombre': e['nombre']?.toString() ?? 'Estudio',
          'cantidad_reservas': cantReservas,
          'monto_total': montoTotal,
          'monto_pagar': montoPagar,
          'estado': liq?['estado'] ?? 'pendiente',
          'fecha_pago': liq?['fecha_pago'],
          'comprobante_nota': liq?['comprobante_nota'],
          'liquidacion_id': liq?['id'],
        });
      }

      // Ordenar: pendientes primero, luego por monto desc
      resultado.sort((a, b) {
        final aPend = a['estado'] == 'pendiente' ? 0 : 1;
        final bPend = b['estado'] == 'pendiente' ? 0 : 1;
        if (aPend != bPend) return aPend - bPend;
        return (b['monto_pagar'] as int).compareTo(a['monto_pagar'] as int);
      });

      if (!mounted) return;
      setState(() {
        _estudios = resultado;
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

  Future<void> _cargarHistorial() async {
    setState(() => _loadingHistorial = true);
    try {
      // Todos los meses anteriores al seleccionado
      final mesesAnteriores = _meses.skip(1).toList();
      if (mesesAnteriores.isEmpty) {
        if (mounted) setState(() => _loadingHistorial = false);
        return;
      }

      final List<Map<String, dynamic>> resumen = [];
      for (final mes in mesesAnteriores) {
        final liqMes = await _client
            .from('liquidaciones')
            .select('estado, monto_a_pagar')
            .eq('mes', mes);

        final lista = liqMes as List;
        if (lista.isEmpty) continue;
        final totalPagado = lista.fold<int>(
          0,
          (acc, l) => acc + ((l['monto_a_pagar'] as num?)?.toInt() ?? 0),
        );
        final cantEstudios = lista.length;
        final completado =
            lista.every((l) => l['estado']?.toString() == 'pagado');
        resumen.add({
          'mes': mes,
          'total_pagado': totalPagado,
          'cantidad_estudios': cantEstudios,
          'completado': completado,
        });
      }

      if (!mounted) return;
      setState(() {
        _historial = resumen;
        _loadingHistorial = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingHistorial = false);
    }
  }

  // ── Registrar pago ───────────────────────────────────────────────────────

  Future<void> _registrarPago(Map<String, dynamic> estudio, String nota) async {
    final esId = estudio['estudio_id'] as int;
    final montoPagar = estudio['monto_pagar'] as int;
    final montoTotal = estudio['monto_total'] as int;
    final cantReservas = estudio['cantidad_reservas'] as int;
    final liqId = estudio['liquidacion_id'] as String?;

    try {
      if (liqId != null) {
        await _client.from('liquidaciones').update({
          'estado': 'pagado',
          'fecha_pago': DateTime.now().toIso8601String(),
          'comprobante_nota': nota.trim().isEmpty ? null : nota.trim(),
        }).eq('id', liqId);
      } else {
        await _client.from('liquidaciones').insert({
          'estudio_id': esId,
          'mes': _mesSeleccionado,
          'monto_total_reservas': montoTotal,
          'monto_a_pagar': montoPagar,
          'cantidad_reservas': cantReservas,
          'estado': 'pagado',
          'fecha_pago': DateTime.now().toIso8601String(),
          'comprobante_nota': nota.trim().isEmpty ? null : nota.trim(),
        });
      }

      if (!mounted) return;
      setState(() {
        final idx = _estudios.indexWhere((e) => e['estudio_id'] == esId);
        if (idx >= 0) {
          _estudios[idx] = {
            ..._estudios[idx],
            'estado': 'pagado',
            'fecha_pago': DateTime.now().toIso8601String(),
            'comprobante_nota': nota.trim().isEmpty ? null : nota.trim(),
          };
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Pago registrado correctamente'),
          backgroundColor: const Color(0xFF1A1A1A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _abrirBottomSheet(Map<String, dynamic> estudio) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PagoSheet(
        estudio: estudio,
        onConfirmar: (nota) async {
          Navigator.pop(ctx);
          await _registrarPago(estudio, nota);
        },
      ),
    );
  }

  // ── Formateo ─────────────────────────────────────────────────────────────

  static String _fmt(int amount) {
    final s = amount.toString();
    final buf = StringBuffer('\$');
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F5F2),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Liquidaciones',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A1A),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _mesSeleccionado,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                items: _meses.map((mes) {
                  return DropdownMenuItem(
                    value: mes,
                    child: Text(_labelMes(mes)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val == null || val == _mesSeleccionado) return;
                  setState(() => _mesSeleccionado = val);
                  _cargar();
                },
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    children: [
                      const SizedBox(height: 16),
                      _buildResumenCard(),
                      const SizedBox(height: 20),
                      ..._estudios.map(_buildEstudioCard),
                      const SizedBox(height: 24),
                      _buildHistorialSection(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AppColors.grey),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }

  Widget _buildResumenCard() {
    final pendientes =
        _estudios.where((e) => e['estado'] == 'pendiente').toList();
    final totalPendiente = pendientes.fold<int>(
      0,
      (acc, e) => acc + (e['monto_pagar'] as int),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total a pagar este mes',
                  style: TextStyle(color: Color(0xFFF5F0EB), fontSize: 14),
                ),
              ),
              Text(
                _fmt(totalPendiente),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${pendientes.length} estudio${pendientes.length != 1 ? 's' : ''} pendiente${pendientes.length != 1 ? 's' : ''}',
            style: const TextStyle(color: Color(0xFF8F877F), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildEstudioCard(Map<String, dynamic> estudio) {
    final nombre = estudio['nombre'] as String;
    final cantReservas = estudio['cantidad_reservas'] as int;
    final montoPagar = estudio['monto_pagar'] as int;
    final estado = estudio['estado'] as String;
    final pagado = estado == 'pagado';

    final inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Row superior
          Row(
            children: [
              // Avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    inicial,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$cantReservas reserva${cantReservas != 1 ? 's' : ''} este mes',
                      style: const TextStyle(
                        color: Color(0xFF8F877F),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Badge estado
              _EstadoBadge(pagado: pagado),
            ],
          ),

          // Row inferior (solo si pendiente)
          if (!pagado) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF0EDE8)),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  _fmt(montoPagar),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _abrirBottomSheet(estudio),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Registrar pago',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
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

  Widget _buildHistorialSection() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GestureDetector(
            onTap: () {
              if (!_historialExpanded) {
                _cargarHistorial();
              }
              setState(() => _historialExpanded = !_historialExpanded);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.history_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _historialExpanded
                        ? 'Ocultar historial'
                        : 'Ver historial',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _historialExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_historialExpanded) ...[
          const SizedBox(height: 12),
          if (_loadingHistorial)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            )
          else if (_historial.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Text(
                'No hay meses anteriores registrados.',
                style: TextStyle(color: AppColors.grey),
                textAlign: TextAlign.center,
              ),
            )
          else
            ..._historial.map(_buildHistorialCard),
        ],
      ],
    );
  }

  Widget _buildHistorialCard(Map<String, dynamic> item) {
    final mes = item['mes'] as String;
    final totalPagado = item['total_pagado'] as int;
    final cantEstudios = item['cantidad_estudios'] as int;
    final completado = item['completado'] as bool;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _labelMes(mes),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$cantEstudios estudio${cantEstudios != 1 ? 's' : ''} · ${_fmt(totalPagado)} pagado${completado ? '' : ' (parcial)'}',
                  style: const TextStyle(
                    color: Color(0xFF8F877F),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (completado)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Completado',
                style: TextStyle(
                  color: Color(0xFF2E7D32),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Parcial',
                style: TextStyle(
                  color: Color(0xFFE65100),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Supporting widgets ─────────────────────────────────────────────────────────

class _EstadoBadge extends StatelessWidget {
  final bool pagado;

  const _EstadoBadge({required this.pagado});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: pagado ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        pagado ? 'PAGADO' : 'PENDIENTE',
        style: TextStyle(
          color: pagado ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _PagoSheet extends StatefulWidget {
  final Map<String, dynamic> estudio;
  final Future<void> Function(String nota) onConfirmar;

  const _PagoSheet({required this.estudio, required this.onConfirmar});

  @override
  State<_PagoSheet> createState() => _PagoSheetState();
}

class _PagoSheetState extends State<_PagoSheet> {
  final _notaCtrl = TextEditingController();
  bool _confirmando = false;

  static String _fmt(int amount) {
    final s = amount.toString();
    final buf = StringBuffer('\$');
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  void dispose() {
    _notaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nombre = widget.estudio['nombre'] as String;
    final montoPagar = widget.estudio['monto_pagar'] as int;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDD8D2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Registrar pago a $nombre',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 16),
            // Monto grande
            Center(
              child: Text(
                _fmt(montoPagar),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Campo nota
            const Text(
              'Nota o comprobante',
              style: TextStyle(
                color: Color(0xFF5F5953),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notaCtrl,
              maxLines: 3,
              style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
              decoration: InputDecoration(
                hintText:
                    'Ej: Transferencia CBU 1234, comprobante MP #XXXXX',
                hintStyle: const TextStyle(
                  color: Color(0xFF9A928B),
                  fontSize: 14,
                ),
                filled: true,
                fillColor: const Color(0xFFF7F5F2),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Botón confirmar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _confirmando
                    ? null
                    : () async {
                        setState(() => _confirmando = true);
                        await widget.onConfirmar(_notaCtrl.text);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _confirmando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Confirmar pago',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            // Botón cancelar
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  foregroundColor: const Color(0xFF8F877F),
                ),
                child: const Text('Cancelar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
