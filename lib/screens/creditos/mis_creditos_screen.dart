import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../services/reservas_service.dart';

class MisCreditosScreen extends StatefulWidget {
  const MisCreditosScreen({super.key});

  @override
  State<MisCreditosScreen> createState() => _MisCreditosScreenState();
}

class _MisCreditosScreenState extends State<MisCreditosScreen> {
  final _reservasService = ReservasService();
  List<Map<String, dynamic>> _reservasMes = [];
  bool _loadingReservas = true;
  String? _loadedUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = context.read<AppProvider>().usuario?.id;
    if (userId != null && userId != _loadedUserId) {
      _loadedUserId = userId;
      _loadReservas(userId);
    }
  }

  Future<void> _loadReservas(String userId) async {
    try {
      final data = await _reservasService.getReservasMes(userId);
      if (!mounted) return;
      setState(() {
        _reservasMes = data;
        _loadingReservas = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingReservas = false);
    }
  }

  // ── Savings logic ─────────────────────────────────────────────────────────

  static const Map<String, int> _preciosMercado = {
    'gym': 12000,
    'fitness': 12000,
    'pilates': 20000,
    'yoga': 30000,
    'arte': 75000,
    'ceramica': 75000,
  };

  int _precioMercadoPara(Map<String, dynamic> reserva) {
    final clase = reserva['clases'] as Map<String, dynamic>?;
    final cat = clase?['categoria']?.toString().toLowerCase().trim() ?? '';
    for (final entry in _preciosMercado.entries) {
      if (cat.contains(entry.key)) return entry.value;
    }
    return 12000;
  }

  int _ahorroPor(Map<String, dynamic> reserva) {
    final creditos = (reserva['creditos_usados'] as num?)?.toInt() ?? 0;
    final diff = _precioMercadoPara(reserva) - creditos * 1000;
    return diff > 0 ? diff : 0;
  }

  int get _totalAhorro =>
      _reservasMes.fold(0, (acc, r) => acc + _ahorroPor(r));

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
        title: const Text('Mis créditos'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          final usuario = provider.usuario;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // ── Credits card ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, Color(0xFFD4612A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Créditos disponibles',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${usuario?.creditos ?? 0}',
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 56,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8, left: 6),
                          child: Text(
                            'créditos',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (usuario?.creditosVencimiento != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time_rounded,
                            color: Colors.white54,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Próximo vencimiento: ${DateFormat("d 'de' MMMM", 'es').format(usuario!.creditosVencimiento!)}',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Tus packs vencen según su vigencia. El Pack Prueba dura 60 días. Los packs Esencial, Popular y Full duran 90 días. Siempre se descuentan primero los créditos que vencen antes.',
                  style: TextStyle(
                    color: AppColors.grey,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.add_circle_outline_rounded,
                      label: 'Comprar\ncréditos',
                      onTap: () => context.push('/comprar-creditos'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.people_outline_rounded,
                      label: 'Ganar\ncon referidos',
                      onTap: () => context.push('/referidos'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                '¿Cómo usar los créditos?',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Column(
                  children: [
                    _HowItem(
                      step: '1',
                      text: 'Explorá los estudios y clases disponibles',
                    ),
                    Divider(height: 20),
                    _HowItem(
                      step: '2',
                      text: 'Elegí una clase y reservá tu lugar',
                    ),
                    Divider(height: 20),
                    _HowItem(
                      step: '3',
                      text: 'Presentá tu QR en el estudio y listo',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: () => context.push('/historial-creditos'),
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: const Text('Ver historial de movimientos'),
                ),
              ),

              // ── Savings section ───────────────────────────────────────────
              const SizedBox(height: 24),
              const _SectionLabel('TU AHORRO CON AURA'),
              const SizedBox(height: 12),
              _buildAhorroSection(),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAhorroSection() {
    if (_loadingReservas) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_reservasMes.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          children: [
            Icon(Icons.savings_rounded, color: AppColors.primary, size: 48),
            SizedBox(height: 12),
            Text(
              'Reservá tu primera clase',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'y empezá a ahorrar con Aura',
              style: TextStyle(color: Color(0xFF8F877F), fontSize: 14),
            ),
          ],
        ),
      );
    }

    final total = _totalAhorro;
    final ultimasReservas = _reservasMes.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dark savings card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.savings_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Este mes ahorraste',
                    style: TextStyle(
                      color: Color(0xFFF5F0EB),
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _fmt(total),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: Color(0xFF333333), height: 1),
              ),
              const Text(
                'vs pagar precio de mercado en Pilar',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8F877F), fontSize: 12),
              ),
            ],
          ),
        ),

        // Per-reservation breakdown (only when total saving > 0)
        if (total > 0) ...[
          const SizedBox(height: 20),
          const _SectionLabel('CÓMO AHORRASTE'),
          const SizedBox(height: 12),
          ...ultimasReservas.map(_buildReservaCard),
        ],
      ],
    );
  }

  Widget _buildReservaCard(Map<String, dynamic> reserva) {
    final clase = reserva['clases'] as Map<String, dynamic>?;
    final nombre = clase?['nombre']?.toString() ?? 'Clase';
    final creditos = (reserva['creditos_usados'] as num?)?.toInt() ?? 0;
    final precioAura = creditos * 1000;
    final precioMercado = _precioMercadoPara(reserva);
    final ahorro = _ahorroPor(reserva);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  nombre,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fmt(precioMercado),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9A928B),
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  Text(
                    _fmt(precioAura),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (ahorro > 0) ...[
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '+${_fmt(ahorro)} ahorrado',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2E7D32),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF8F877F),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HowItem extends StatelessWidget {
  final String step;
  final String text;

  const _HowItem({
    required this.step,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              step,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.black,
            ),
          ),
        ),
      ],
    );
  }
}
