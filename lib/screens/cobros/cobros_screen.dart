import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../services/estudio_admin_service.dart';

class CobrosScreen extends StatefulWidget {
  const CobrosScreen({super.key});

  @override
  State<CobrosScreen> createState() => _CobrosScreenState();
}

class _CobrosScreenState extends State<CobrosScreen> {
  final _service = EstudioAdminService();

  Map<String, dynamic>? _estudio;
  List<Map<String, dynamic>> _reservas = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final estudio = await _service.getCurrentStudio();
      final reservas = await _service.getReservasDeEstudio(limit: 200);

      if (!mounted) return;
      setState(() {
        _estudio = estudio;
        _reservas = reservas;
        _loading = false;
        _error = estudio == null ? 'No encontramos un estudio asociado.' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar los cobros del estudio.';
      });
    }
  }

  Widget _buildDesktopContent() {
    if (_error != null) return _InfoCard(message: _error!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 3 metric tiles
        Row(
          children: [
            _MetricTile(
              value: _moneyCompact(_montoCobrado),
              label: 'cobrado',
              color: const Color(0xFFE3F3E5),
              valueColor: const Color(0xFF2FAD5B),
            ),
            const SizedBox(width: 12),
            _MetricTile(
              value: '${_reservasNoCanceladas.length}',
              label: 'Reservas',
              color: const Color(0xFFFFF3DE),
              valueColor: AppColors.primary,
            ),
            const SizedBox(width: 12),
            _MetricTile(
              value: _moneyCompact(_ticketPromedio),
              label: 'por reserva',
              color: const Color(0xFFF1F1F1),
              valueColor: AppColors.black,
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Chart + próximo cobro
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ingresos mensuales',
                      style: TextStyle(color: Color(0xFF9A928B), fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 120,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: _buildMonthlyBars(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.blackSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Próximo cobro', style: TextStyle(color: Color(0xFFA39B94), fontSize: 13)),
                    const SizedBox(height: 10),
                    Text(_money(_montoPendiente), style: const TextStyle(color: AppColors.primary, fontSize: 28, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text('${_reservasMesActual.length} reservas · $_mesActualCapitalizado', style: const TextStyle(color: Color(0xFFA39B94), fontSize: 13)),
                    const SizedBox(height: 16),
                    Text('Pago el $_diaPago', style: const TextStyle(color: Color(0xFFA39B94), fontSize: 13)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 40,
                      child: ElevatedButton(
                        onPressed: () => _verDetalle(context),
                        child: const Text('Ver detalle'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Historial tabla
        const Text(
          'HISTORIAL',
          style: TextStyle(color: Color(0xFF8F877F), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16)),
          child: _historial.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Todavía no hay historial de cobros.', style: TextStyle(color: Color(0xFF8F877F))),
                )
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF7F5F2),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: const Row(
                        children: [
                          Expanded(child: Text('Mes', style: TextStyle(color: Color(0xFF888888), fontSize: 11, fontWeight: FontWeight.w700))),
                          SizedBox(width: 80, child: Text('Reservas', style: TextStyle(color: Color(0xFF888888), fontSize: 11, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
                          SizedBox(width: 120, child: Text('Monto neto', style: TextStyle(color: Color(0xFF888888), fontSize: 11, fontWeight: FontWeight.w700), textAlign: TextAlign.right)),
                          SizedBox(width: 90, child: Text('Estado', style: TextStyle(color: Color(0xFF888888), fontSize: 11, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
                        ],
                      ),
                    ),
                    ..._historial.asMap().entries.map((e) {
                      final item = e.value;
                      final isPending = item['estado'] == 'Pendiente';
                      final statusColor = isPending ? AppColors.primary : const Color(0xFF43A047);
                      final statusBg = isPending ? const Color(0xFFFFF3DE) : const Color(0xFFE3F3E5);
                      return Container(
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: Colors.grey.shade100)),
                          borderRadius: e.key == _historial.length - 1
                              ? const BorderRadius.vertical(bottom: Radius.circular(16))
                              : null,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        child: Row(
                          children: [
                            Expanded(child: Text(item['mes'] as String, style: const TextStyle(color: AppColors.black, fontSize: 14, fontWeight: FontWeight.w600))),
                            SizedBox(width: 80, child: Text('${item['reservas']}', style: const TextStyle(color: Color(0xFF8F877F), fontSize: 14), textAlign: TextAlign.center)),
                            SizedBox(width: 120, child: Text(_money(item['monto'] as int), style: TextStyle(color: statusColor, fontSize: 14, fontWeight: FontWeight.w700), textAlign: TextAlign.right)),
                            SizedBox(
                              width: 90,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(999)),
                                  child: Text(item['estado'] as String, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600)),
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
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  child: _buildDesktopContent(),
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
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => context.go('/estudio/dashboard'),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const Spacer(),
                        const Icon(Icons.notifications_none_rounded),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'Cobros',
                        style: TextStyle(
                          color: AppColors.black,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (_error != null) _InfoCard(message: _error!),
                    if (_error == null) ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.blackSoft,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Próximo cobro',
                              style: TextStyle(
                                color: Color(0xFFA39B94),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _money(_montoPendiente),
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${_reservasMesActual.length} reservas · ${_mesActualCapitalizado}',
                              style: const TextStyle(
                                color: Color(0xFFA39B94),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                SizedBox(
                                  height: 42,
                                  child: ElevatedButton(
                                    onPressed: () => _verDetalle(context),
                                    child: const Text('Ver detalle'),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'Pago el ${_diaPago}',
                                  style: const TextStyle(
                                    color: Color(0xFFA39B94),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _MetricTile(
                            value: _moneyCompact(_montoCobrado),
                            label: 'cobrado',
                            color: const Color(0xFFE3F3E5),
                            valueColor: const Color(0xFF2FAD5B),
                          ),
                          const SizedBox(width: 8),
                          _MetricTile(
                            value: '${_reservasNoCanceladas.length}',
                            label: 'Reservas',
                            color: const Color(0xFFFFF3DE),
                            valueColor: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          _MetricTile(
                            value: _moneyCompact(_ticketPromedio),
                            label: 'por reserva',
                            color: const Color(0xFFF1F1F1),
                            valueColor: AppColors.black,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
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
                              'Ingresos mensuales',
                              style: TextStyle(
                                color: Color(0xFF9A928B),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: _buildMonthlyBars(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'HISTORIAL',
                        style: TextStyle(
                          color: Color(0xFF8F877F),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: _historial.isEmpty
                            ? const Text(
                                'Todavía no hay historial de cobros.',
                                style: TextStyle(color: Color(0xFF8F877F)),
                              )
                            : Column(
                                children: _historial.map((item) {
                                  final isPending = item['estado'] == 'Pendiente';
                                  final statusColor = isPending
                                      ? AppColors.primary
                                      : const Color(0xFF43A047);
                                  final statusBg = isPending
                                      ? const Color(0xFFFFF3DE)
                                      : const Color(0xFFE3F3E5);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item['mes'] as String,
                                                style: const TextStyle(
                                                  color: AppColors.black,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                '${item['reservas']} reservas',
                                                style: const TextStyle(
                                                  color: Color(0xFF8F877F),
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          _money(item['monto'] as int),
                                          style: TextStyle(
                                            color: statusColor,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: statusBg,
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            item['estado'] as String,
                                            style: TextStyle(
                                              color: statusColor,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                      const SizedBox(height: 16),
                      _hasBankData
                          ? Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Transferencia bancaria',
                                          style: TextStyle(
                                            color: AppColors.black,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            context.go('/estudio/perfil'),
                                        child: const Text(
                                          'Editar',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 16),
                                  if ((_estudio?['cbu']?.toString() ?? '').isNotEmpty)
                                    _BankRow(
                                      icon: Icons.account_balance_outlined,
                                      label: 'CBU',
                                      value: _estudio!['cbu'].toString(),
                                    ),
                                  if ((_estudio?['alias']?.toString() ?? '').isNotEmpty)
                                    _BankRow(
                                      icon: Icons.alternate_email_rounded,
                                      label: 'Alias',
                                      value: _estudio!['alias'].toString(),
                                    ),
                                  if ((_estudio?['banco']?.toString() ?? '').isNotEmpty)
                                    _BankRow(
                                      icon: Icons.business_outlined,
                                      label: 'Banco',
                                      value: _estudio!['banco'].toString(),
                                    ),
                                  if ((_estudio?['titular']?.toString() ?? '').isNotEmpty)
                                    _BankRow(
                                      icon: Icons.person_outline_rounded,
                                      label: 'Titular',
                                      value: _estudio!['titular'].toString(),
                                    ),
                                  _BankRow(
                                    icon: Icons.percent_rounded,
                                    label: 'Comisión Aura',
                                    value:
                                        '${_comisionAura.toStringAsFixed(_comisionAura.truncateToDouble() == _comisionAura ? 0 : 1)}%',
                                  ),
                                ],
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppColors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFEDE7E1),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.account_balance_outlined,
                                        color: AppColors.primary,
                                        size: 22,
                                      ),
                                      SizedBox(width: 10),
                                      Text(
                                        'Datos bancarios incompletos',
                                        style: TextStyle(
                                          color: AppColors.black,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Completá tus datos bancarios para que Aura pueda liquidarte los pagos correctamente.',
                                    style: TextStyle(
                                      color: Color(0xFF8F877F),
                                      fontSize: 13,
                                      height: 1.45,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: () =>
                                          context.go('/estudio/perfil'),
                                      child:
                                          const Text('Completar datos bancarios'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Future<(Map<int, String>, Map<String, String>)> _loadDetalleData() async {
    final reservas = _reservasMesActual;

    final claseIds = reservas
        .map((r) => (r['clase_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .toList();
    final userIds = reservas
        .map((r) => r['usuario_id']?.toString())
        .whereType<String>()
        .toSet()
        .toList();

    final client = Supabase.instance.client;

    final Map<int, String> claseNames = {};
    if (claseIds.isNotEmpty) {
      final data = await client
          .from('clases')
          .select('id, nombre')
          .inFilter('id', claseIds);
      for (final row in (data as List)) {
        final id = (row['id'] as num?)?.toInt();
        if (id != null) claseNames[id] = row['nombre']?.toString() ?? '—';
      }
    }

    final Map<String, String> userNames = {};
    if (userIds.isNotEmpty) {
      final data = await client
          .from('usuarios')
          .select('id, nombre')
          .inFilter('id', userIds);
      for (final row in (data as List)) {
        final id = row['id']?.toString();
        if (id != null) userNames[id] = row['nombre']?.toString() ?? '—';
      }
    }

    return (claseNames, userNames);
  }

  void _verDetalle(BuildContext context) {
    final reservas = _reservasMesActual;
    final moneyFmt = NumberFormat.currency(
      locale: 'es_AR',
      symbol: '\$',
      decimalDigits: 0,
    );
    final comision = _comisionAura;
    final totalBruto = reservas.fold<int>(0, (acc, r) {
      final creditos = (r['creditos_usados'] as num?)?.toInt() ?? 0;
      final valorCredito =
          (_estudio?['valor_credito'] as num?)?.toInt() ?? 6000;
      return acc + creditos * valorCredito;
    });
    final comisionMonto = (totalBruto * comision / 100).round();
    final aTransferir = _montoPendiente;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.94,
        expand: false,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4CEC9),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Row(
                  children: [
                    const Text(
                      'Detalle del mes',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.black,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${reservas.length} reservas',
                      style: const TextStyle(
                        color: Color(0xFF8F877F),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: reservas.isEmpty
                    ? const Center(
                        child: Text(
                          'Sin reservas este mes.',
                          style: TextStyle(color: Color(0xFF8F877F)),
                        ),
                      )
                    : FutureBuilder<(Map<int, String>, Map<String, String>)>(
                        future: _loadDetalleData(),
                        builder: (context, snap) {
                          final claseNames =
                              snap.data?.$1 ?? <int, String>{};
                          final userNames =
                              snap.data?.$2 ?? <String, String>{};
                          final isLoading = !snap.hasData;

                          return ListView.separated(
                            controller: controller,
                            padding:
                                const EdgeInsets.fromLTRB(20, 10, 20, 16),
                            itemCount: reservas.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final r = reservas[i];
                              final dt = DateTime.tryParse(
                                  r['created_at']?.toString() ?? '');
                              final claseId =
                                  (r['clase_id'] as num?)?.toInt();
                              final userId =
                                  r['usuario_id']?.toString() ?? '';
                              final creditos =
                                  (r['creditos_usados'] as num?)
                                      ?.toInt() ??
                                  0;
                              final monto = _montoReserva(r);
                              final estado =
                                  r['estado']?.toString() ?? '';
                              final isPresentado = estado == 'presente';
                              final claseNombre = isLoading
                                  ? '…'
                                  : (claseNames[claseId] ?? '—');
                              final userNombre = isLoading
                                  ? '…'
                                  : (userNames[userId] ?? '—');

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF3DE),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        dt != null
                                            ? DateFormat('d', 'es')
                                                .format(dt)
                                            : '—',
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            claseNombre,
                                            style: const TextStyle(
                                              color: AppColors.black,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            userNombre,
                                            style: const TextStyle(
                                              color: Color(0xFF8F877F),
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              Text(
                                                '$creditos crédito${creditos == 1 ? '' : 's'}',
                                                style: const TextStyle(
                                                  color: Color(0xFFB0A8A0),
                                                  fontSize: 11,
                                                ),
                                              ),
                                              if (dt != null) ...[
                                                const Text(
                                                  ' · ',
                                                  style: TextStyle(
                                                      color: Color(
                                                          0xFFB0A8A0),
                                                      fontSize: 11),
                                                ),
                                                Text(
                                                  DateFormat('d MMM', 'es')
                                                      .format(dt),
                                                  style: const TextStyle(
                                                    color:
                                                        Color(0xFFB0A8A0),
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          moneyFmt.format(monto),
                                          style: const TextStyle(
                                            color: AppColors.black,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isPresentado
                                                ? const Color(0xFFE3F3E5)
                                                : const Color(0xFFFFF3DE),
                                            borderRadius:
                                                BorderRadius.circular(99),
                                          ),
                                          child: Text(
                                            isPresentado
                                                ? 'Presente'
                                                : 'Confirmada',
                                            style: TextStyle(
                                              color: isPresentado
                                                  ? const Color(0xFF2FAD5B)
                                                  : AppColors.primary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
              // Desglose financiero
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  border:
                      Border(top: BorderSide(color: Color(0xFFEDE7E1))),
                ),
                child: Column(
                  children: [
                    _DetalleRow(
                      label: 'Total bruto',
                      value: moneyFmt.format(totalBruto),
                    ),
                    const SizedBox(height: 6),
                    _DetalleRow(
                      label:
                          'Comisión Aura (${comision.toStringAsFixed(comision.truncateToDouble() == comision ? 0 : 1)}%)',
                      value: '- ${moneyFmt.format(comisionMonto)}',
                      valueColor: AppColors.error,
                    ),
                    const Divider(height: 16),
                    _DetalleRow(
                      label: 'A transferir',
                      value: moneyFmt.format(aTransferir),
                      bold: true,
                      valueColor: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasBankData =>
      (_estudio?['cbu']?.toString() ?? '').isNotEmpty ||
      (_estudio?['alias']?.toString() ?? '').isNotEmpty;

  List<Map<String, dynamic>> get _reservasNoCanceladas =>
      _reservas.where((r) => r['estado']?.toString() != 'cancelada').toList();

  List<Map<String, dynamic>> get _reservasMesActual {
    final now = DateTime.now();
    return _reservasNoCanceladas.where((r) {
      final dt = DateTime.tryParse(r['created_at']?.toString() ?? '');
      return dt != null && dt.year == now.year && dt.month == now.month;
    }).toList();
  }

  double get _comisionAura => (_estudio?['comision_aura'] as num?)?.toDouble() ?? 30;

  int get _montoPendiente => _reservasMesActual.fold<int>(0, (acc, r) {
        final estado = r['estado']?.toString();
        return acc + (estado == 'cancelada' ? 0 : _montoReserva(r));
      });

  int get _montoCobrado => _reservas.where((r) {
        final estado = r['estado']?.toString();
        return estado == 'confirmada' || estado == 'presente';
      }).fold<int>(0, (acc, r) => acc + _montoReserva(r));

  int get _ticketPromedio {
    if (_reservasNoCanceladas.isEmpty) return 0;
    final total = _reservasNoCanceladas.fold<int>(0, (acc, r) => acc + _montoReserva(r));
    return total ~/ _reservasNoCanceladas.length;
  }

  int _montoReserva(Map<String, dynamic> reserva) {
    final creditos = (reserva['creditos_usados'] as num?)?.toInt() ?? 0;
    final valorCredito = (_estudio?['valor_credito'] as num?)?.toInt() ?? 6000;
    final bruto = creditos * valorCredito;
    return (bruto * ((100 - _comisionAura) / 100)).round();
  }

  String _money(int value) =>
      NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 0)
          .format(value);

  String _moneyCompact(int value) {
    if (value >= 1000000) return '\$${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '\$${(value / 1000).round()}k';
    return '\$$value';
  }

  List<Widget> _buildMonthlyBars() {
    final months = List.generate(6, (index) {
      final date = DateTime(DateTime.now().year, DateTime.now().month - 5 + index, 1);
      final total = _reservasNoCanceladas.where((reserva) {
        final created = DateTime.tryParse(reserva['created_at']?.toString() ?? '');
        return created != null &&
            created.year == date.year &&
            created.month == date.month;
      }).fold<int>(0, (acc, reserva) => acc + _montoReserva(reserva));
      return {'date': date, 'total': total};
    });

    final max = months.fold<int>(1, (acc, item) => (item['total'] as int) > acc ? item['total'] as int : acc);
    return months.asMap().entries.map((entry) {
      final total = entry.value['total'] as int;
      final active = entry.key == months.length - 1;
      final height = 24 + ((total / max) * 48);
      return Expanded(
        child: Container(
          margin: EdgeInsets.only(right: entry.key == months.length - 1 ? 0 : 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                height: height,
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : const Color(0xFFE1E1E1),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                DateFormat('MMM', 'es').format(entry.value['date'] as DateTime),
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF8F877F),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  List<Map<String, dynamic>> get _historial {
    final formatter = DateFormat('MMMM yyyy', 'es');
    final grouped = <String, Map<String, dynamic>>{};

    for (final reserva in _reservasNoCanceladas) {
      final dt = DateTime.tryParse(reserva['created_at']?.toString() ?? '');
      if (dt == null) continue;

      final key = formatter.format(dt);
      grouped.putIfAbsent(
        key,
        () => {
          'mes': toBeginningOfSentenceCase(key) ?? key,
          'reservas': 0,
          'monto': 0,
          '_date': DateTime(dt.year, dt.month, 1),
          'estado': dt.month == DateTime.now().month && dt.year == DateTime.now().year
              ? 'Pendiente'
              : 'Pagado',
        },
      );
      grouped[key]!['reservas'] = (grouped[key]!['reservas'] as int) + 1;
      grouped[key]!['monto'] = (grouped[key]!['monto'] as int) + _montoReserva(reserva);
    }

    final values = grouped.values.toList();
    values.sort((a, b) => (b['_date'] as DateTime).compareTo(a['_date'] as DateTime));
    return values.take(4).toList();
  }

  String get _mesActualCapitalizado {
    final text = DateFormat('MMMM', 'es').format(DateTime.now());
    return toBeginningOfSentenceCase(text) ?? text;
  }

  String get _diaPago {
    final dia = (_estudio?['dia_pago'] as num?)?.toInt() ?? 5;
    return '$dia de cada mes';
  }
}

class _MetricTile extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final Color valueColor;

  const _MetricTile({
    required this.value,
    required this.label,
    required this.color,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF8F877F),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BankRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _BankRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF8F877F)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$label: $value',
              style: const TextStyle(
                color: Color(0xFF625C57),
                fontSize: 14,
              ),
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFFC0B8B0)),
        ],
      ),
    );
  }
}

class _DetalleRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  const _DetalleRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: bold ? AppColors.black : const Color(0xFF8F877F),
            fontSize: bold ? 15 : 13,
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? (bold ? AppColors.black : const Color(0xFF8F877F)),
            fontSize: bold ? 17 : 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String message;

  const _InfoCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
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
