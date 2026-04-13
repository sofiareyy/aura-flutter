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

  String _btnLabel() {
    if (_isPackTab) {
      if (_selectedPack == null) return 'Seleccioná un pack';
      final precio = (_packs[_selectedPack!]['precio'] as num).toInt();
      return 'Pagar \$${_fmt(precio)}';
    } else {
      if (_selectedPlan == null) return 'Seleccioná un plan';
      final precio = (_planes[_selectedPlan!]['precio'] as num).toInt();
      return 'Suscribirme por \$${_fmt(precio)}/mes';
    }
  }

  String _fmt(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      );

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
              12,
              20,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            color: AppColors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_isPackTab && selected != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Renovación automática · Cancelá cuando quieras',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (loading || selected == null) ? null : _continuar,
                    child: Text(_btnLabel()),
                  ),
                ),
              ],
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

  String? _badge(String nombre) {
    final n = nombre.toLowerCase();
    if (n.contains('explorer')) return 'MÁS POPULAR';
    if (n.contains('unlimited')) return 'MEJOR VALOR';
    return null;
  }

  String? _subtitulo(String nombre) {
    final n = nombre.toLowerCase();
    if (n.contains('starter')) return '~2 clases de pilates + 1 yoga';
    if (n.contains('explorer')) return '~5 clases de pilates o 1 cerámica + yoga';
    if (n.contains('unlimited')) return '~10 clases o combinación libre';
    return null;
  }

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
          final nombre = plan['nombre']?.toString() ?? '';
          final badge = _badge(nombre);
          final subtitulo = _subtitulo(nombre);
          return GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFFDF0E8) : AppColors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? AppColors.primary : const Color(0xFFE8E5E0),
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
                          nombre,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.black,
                          ),
                        ),
                      ),
                      if (badge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    plan['descripcion']?.toString() ?? '',
                    style: const TextStyle(color: AppColors.grey, fontSize: 13),
                  ),
                  if (subtitulo != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitulo,
                      style: const TextStyle(color: AppColors.grey, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${plan['creditos']}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: AppColors.black,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6, left: 4),
                        child: Text(
                          'cr/mes',
                          style: TextStyle(color: AppColors.grey, fontSize: 14),
                        ),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\$${_fmt((plan['precio'] as num).toInt())}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.black,
                            ),
                          ),
                          const Text(
                            'por mes',
                            style: TextStyle(fontSize: 12, color: AppColors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected ? AppColors.primary : AppColors.lightGrey,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Renovación automática mensual',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.grey,
                        ),
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
