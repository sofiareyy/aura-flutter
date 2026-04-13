import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../services/pricing_service.dart';

class ComprarCreditosScreen extends StatefulWidget {
  const ComprarCreditosScreen({super.key});

  @override
  State<ComprarCreditosScreen> createState() => _ComprarCreditosScreenState();
}

class _ComprarCreditosScreenState extends State<ComprarCreditosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _pricingService = PricingService();

  int? _selectedPack;
  int? _selectedPlan;
  bool _loadingPacks = true;
  bool _loadingPlanes = true;
  List<Map<String, dynamic>> _packs = [];
  List<Map<String, dynamic>> _planes = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadPacks();
    _loadPlanes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPacks() async {
    final packs = await _pricingService.getPacks();
    if (!mounted) return;
    setState(() {
      _packs = packs;
      _loadingPacks = false;
    });
  }

  Future<void> _loadPlanes() async {
    final planes = await _pricingService.getPlanes();
    planes.sort((a, b) {
      final oa = (a['orden'] as num?)?.toInt() ?? 999;
      final ob = (b['orden'] as num?)?.toInt() ?? 999;
      return oa.compareTo(ob);
    });
    if (!mounted) return;
    setState(() {
      _planes = planes;
      _loadingPlanes = false;
    });
  }

  bool get _isPackTab => _tabController.index == 0;

  void _continuar() {
    if (_isPackTab) {
      if (_selectedPack == null) return;
      final pack = _packs[_selectedPack!];
      context.push('/checkout', extra: {
        'type': 'pack',
        'nombre': pack['nombre'],
        'creditos': (pack['creditos'] as num).toInt(),
        'precio': (pack['precio'] as num).toInt(),
        'vigencia_dias': (pack['vigencia_dias'] as num?)?.toInt() ?? 90,
        'descripcion': pack['descripcion']?.toString() ?? '',
      });
    } else {
      if (_selectedPlan == null) return;
      final plan = _planes[_selectedPlan!];
      context.push('/checkout', extra: {
        'type': 'plan',
        'nombre': plan['nombre'],
        'creditos': (plan['creditos'] as num).toInt(),
        'precio': (plan['precio'] as num).toInt(),
        'descripcion': plan['descripcion']?.toString() ?? '',
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = _isPackTab ? _loadingPacks : _loadingPlanes;
    final selected = _isPackTab ? _selectedPack : _selectedPlan;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Comprar créditos'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.grey,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Packs'),
            Tab(text: 'Suscripciones'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _PacksTab(
                  packs: _packs,
                  loading: _loadingPacks,
                  selectedIndex: _selectedPack,
                  onSelect: (i) => setState(() => _selectedPack = i),
                ),
                _SuscripcionesTab(
                  planes: _planes,
                  loading: _loadingPlanes,
                  selectedIndex: _selectedPlan,
                  onSelect: (i) => setState(() => _selectedPlan = i),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            color: AppColors.white,
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (loading || selected == null) ? null : _continuar,
                child: Text(
                  selected != null
                      ? 'Continuar al checkout'
                      : _isPackTab
                          ? 'Seleccioná un pack'
                          : 'Seleccioná un plan',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Tab: Packs (compra única)
// ─────────────────────────────────────────────────────────────

class _PacksTab extends StatelessWidget {
  final List<Map<String, dynamic>> packs;
  final bool loading;
  final int? selectedIndex;
  final void Function(int) onSelect;

  const _PacksTab({
    required this.packs,
    required this.loading,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Elegí un pack', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          'Compra única, sin renovación automática.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.grey),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            'Pago seguro con Mercado Pago. Vas a completar la compra en el checkout oficial.',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.warmBorder),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vencimiento de los packs',
                style: TextStyle(color: AppColors.black, fontSize: 13, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 6),
              Text(
                'Pack Prueba: vence a los 60 días. Pack Esencial, Popular y Full: vencen a los 90 días.',
                style: TextStyle(color: AppColors.grey, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ...packs.asMap().entries.map((entry) {
          final i = entry.key;
          final pack = entry.value;
          final selected = selectedIndex == i;
          final vigencia = (pack['vigencia_dias'] as num?)?.toInt() ?? 90;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.lightGrey,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${pack['nombre']} · ${pack['creditos']} créditos',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: selected ? AppColors.white : AppColors.black,
                                ),
                              ),
                            ),
                            if (pack['popular'] == true) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: selected ? AppColors.white : AppColors.primary,
                                  borderRadius: BorderRadius.circular(9999),
                                ),
                                child: Text(
                                  'Más elegido',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: selected ? AppColors.primary : AppColors.white,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          pack['descripcion']?.toString() ?? '',
                          style: TextStyle(
                            color: selected ? Colors.white70 : AppColors.grey,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Vigencia: $vigencia días',
                          style: TextStyle(
                            color: selected ? Colors.white70 : AppColors.grey,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '\$${_fmt((pack['precio'] as num).toInt())}',
                          style: TextStyle(
                            color: selected ? AppColors.white : AppColors.black,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: selected ? AppColors.white : AppColors.lightGrey,
                    size: 24,
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  String _fmt(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      );
}

// ─────────────────────────────────────────────────────────────
// Tab: Suscripciones (renovación mensual automática)
// ─────────────────────────────────────────────────────────────

class _SuscripcionesTab extends StatelessWidget {
  final List<Map<String, dynamic>> planes;
  final bool loading;
  final int? selectedIndex;
  final void Function(int) onSelect;

  const _SuscripcionesTab({
    required this.planes,
    required this.loading,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Elegí tu suscripción', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          'Los créditos se renuevan automáticamente cada mes.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.grey),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            'Podés cancelar cuando quieras desde tu perfil.',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 20),
        ...planes.asMap().entries.map((entry) {
          final i = entry.key;
          final plan = entry.value;
          final selected = selectedIndex == i;
          final destacado = plan['destacado'] == true;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.lightGrey,
                  width: 2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          plan['nombre']?.toString() ?? '',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: selected ? AppColors.white : AppColors.black,
                          ),
                        ),
                      ),
                      if (destacado)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.white : AppColors.primary,
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: Text(
                            'Más popular',
                            style: TextStyle(
                              color: selected ? AppColors.primary : AppColors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    plan['descripcion']?.toString() ?? '',
                    style: TextStyle(
                      color: selected ? Colors.white70 : AppColors.grey,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${plan['creditos']}',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: selected ? AppColors.white : AppColors.black,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6, left: 4),
                        child: Text(
                          'cr/mes',
                          style: TextStyle(
                            color: selected ? Colors.white60 : AppColors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\$${_fmt((plan['precio'] as num).toInt())}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: selected ? AppColors.white : AppColors.black,
                            ),
                          ),
                          Text(
                            'por mes',
                            style: TextStyle(
                              fontSize: 12,
                              color: selected ? Colors.white60 : AppColors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.autorenew_rounded,
                        size: 14,
                        color: selected ? Colors.white70 : AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Se renueva automáticamente cada mes',
                          style: TextStyle(
                            fontSize: 12,
                            color: selected ? Colors.white70 : AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected ? AppColors.white : AppColors.lightGrey,
                        size: 24,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  String _fmt(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      );
}
