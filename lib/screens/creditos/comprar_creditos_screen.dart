import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/aura_tokens.dart';
import '../../services/pricing_service.dart';

class ComprarCreditosScreen extends StatefulWidget {
  /// Pestaña inicial: 0 = Packs, 1 = Suscripciones, 2 = Regalar.
  final int initialTab;

  /// A dónde volver después de pagar, si vino de un lugar concreto (hoy: el
  /// paywall de una clase). Viaja en el `extra` del checkout. Null = compra
  /// suelta desde Perfil o Inicio, y ahí el final sigue siendo /home.
  final String? volver;

  const ComprarCreditosScreen({
    super.key,
    this.initialTab = 0,
    this.volver,
  });

  @override
  State<ComprarCreditosScreen> createState() => _ComprarCreditosScreenState();
}

class _ComprarCreditosScreenState extends State<ComprarCreditosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _pricingService = PricingService();

  int? _selectedPack;
  int? _selectedPlan;
  int? _selectedPackGift;
  bool _loadingPacks = true;
  bool _loadingPlanes = true;
  List<Map<String, dynamic>> _packs = [];
  List<Map<String, dynamic>> _planes = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
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
  bool get _isGiftTab => _tabController.index == 2;

  void _continuar() {
    if (_isGiftTab) {
      if (_selectedPackGift == null) return;
      _abrirBottomSheetRegalo();
      return;
    }
    if (_isPackTab) {
      if (_selectedPack == null) return;
      final pack = _packs[_selectedPack!];
      final creditos = (pack['creditos'] as num).toInt();
      context.push('/checkout', extra: {
        'type': 'pack',
        'volver': widget.volver,
        'nombre': pack['nombre'],
        'creditos': creditos,
        'precio': (pack['precio'] as num).toInt(),
        'vigencia_dias': (pack['vigencia_dias'] as num?)?.toInt() ??
            _vigenciaDiasPorCreditos(creditos),
        'descripcion': pack['descripcion']?.toString() ?? '',
      });
    } else {
      if (_selectedPlan == null) return;
      final plan = _planes[_selectedPlan!];
      context.push('/checkout', extra: {
        'type': 'plan',
        'volver': widget.volver,
        'nombre': plan['nombre'],
        'creditos': (plan['creditos'] as num).toInt(),
        'precio': (plan['precio'] as num).toInt(),
        'descripcion': plan['descripcion']?.toString() ?? '',
      });
    }
  }

  String _btnLabel() {
    if (_isGiftTab) {
      if (_selectedPackGift == null) return 'Seleccioná un pack para regalar';
      return 'Continuar →';
    }
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

  // Vigencia por defecto si la fila de pricing_credit_packs no la trae.
  // Pack Prueba (20 cr): 30 dias. Esencial/Popular/Full: 60 dias.
  int _vigenciaDiasPorCreditos(int creditos) => creditos <= 20 ? 30 : 60;

  void _abrirBottomSheetRegalo() {
    final emailCtrl = TextEditingController();
    final mensajeCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7F5F2),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(ctx).padding.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCCC5BD),
                    borderRadius: BorderRadius.circular(AuraRadio.pastilla),
                  ),
                ),
              ),
              const Text(
                '¿A quién le regalás?',
                style: TextStyle(
                    color: AppColors.black,
                    fontSize: AuraTipo.titulo,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email de la persona',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: mensajeCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Mensaje (opcional)',
                  hintText: '¡Espero que lo disfrutes! 🧡',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              StatefulBuilder(
                builder: (ctx2, setSheetState) {
                  return SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        final email = emailCtrl.text.trim();
                        final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                        if (!regex.hasMatch(email)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Ingresá un email válido'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                          return;
                        }
                        Navigator.pop(ctx);
                        _irACheckoutRegalo(email, mensajeCtrl.text);
                      },
                      child: const Text('Continuar al pago →'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Regalar = comprar un pack con destinatario. Va al MISMO checkout de packs
  /// (Mercado Pago) con type='gift'. Recién cuando el pago se aprueba, el
  /// webhook crea el regalo y le manda el código por mail al destinatario. Ya
  /// no se insertan regalos gratis desde el cliente.
  void _irACheckoutRegalo(String email, String mensaje) {
    if (_selectedPackGift == null) return;
    final pack = _packs[_selectedPackGift!];
    final creditos = (pack['creditos'] as num).toInt();
    context.push('/checkout', extra: {
      'type': 'gift',
        'volver': widget.volver,
      'nombre': pack['nombre'],
      'creditos': creditos,
      'precio': (pack['precio'] as num).toInt(),
      'vigencia_dias': (pack['vigencia_dias'] as num?)?.toInt() ??
          _vigenciaDiasPorCreditos(creditos),
      'descripcion': pack['descripcion']?.toString() ?? '',
      'gift_email': email.trim().toLowerCase(),
      'gift_mensaje': mensaje.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final loading = _isGiftTab
        ? _loadingPacks
        : _isPackTab
            ? _loadingPacks
            : _loadingPlanes;
    final selected = _isGiftTab
        ? _selectedPackGift
        : _isPackTab
            ? _selectedPack
            : _selectedPlan;

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
            Tab(text: '🎁 Regalar'),
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
                _RegalarTab(
                  packs: _packs,
                  loading: _loadingPacks,
                  selectedIndex: _selectedPackGift,
                  onSelect: (i) => setState(() => _selectedPackGift = i),
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
                if (!_isPackTab && !_isGiftTab && selected != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Renovación automática · Cancelá cuando quieras',
                      style: TextStyle(
                        fontSize: AuraTipo.secundario,
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
            borderRadius: BorderRadius.circular(AuraRadio.boton),
          ),
          child: const Text(
            'Pago seguro con Mercado Pago. Vas a completar la compra en el checkout oficial.',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: AuraTipo.secundario,
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
            borderRadius: BorderRadius.circular(AuraRadio.boton),
            border: Border.all(color: AppColors.warmBorder),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vencimiento de los packs',
                style: TextStyle(color: AppColors.black, fontSize: AuraTipo.secundario, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 6),
              Text(
                'Pack Prueba: vence a los 30 días. Pack Esencial, Popular y Full: vencen a los 60 días.',
                style: TextStyle(color: AppColors.grey, fontSize: AuraTipo.secundario, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ...packs.asMap().entries.map((entry) {
          final i = entry.key;
          final pack = entry.value;
          final selected = selectedIndex == i;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.white,
                borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
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
                                  fontSize: AuraTipo.titulo,
                                  fontWeight: FontWeight.w700,
                                  color: selected ? AppColors.white : AppColors.black,
                                ),
                              ),
                            ),
                            if ((pack['badge']?.toString() ?? '').isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: selected ? AppColors.white : AppColors.primary,
                                  borderRadius: BorderRadius.circular(AuraRadio.pastilla),
                                ),
                                child: Text(
                                  pack['badge'].toString(),
                                  style: TextStyle(
                                    fontSize: AuraTipo.etiqueta,
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
                            fontSize: AuraTipo.secundario,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '\$${_fmt((pack['precio'] as num).toInt())}',
                          style: TextStyle(
                            color: selected ? AppColors.white : AppColors.black,
                            fontSize: AuraTipo.titulo,
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

  /// Sale de `pricing_planes.destacado`, no del nombre. Antes se buscaba
  /// 'explorer'/'unlimited' a mano, así que al renombrar los planes el badge
  /// desaparecía sin que nadie se enterara.
  String? _badge(Map<String, dynamic> plan) =>
      plan['destacado'] == true ? 'MÁS POPULAR' : null;

  /// Texto de uso del plan, tomado de `pricing_planes.descripcion`. Sin
  /// cantidades de clases: cada estudio negocia su propio precio en créditos
  /// y en modo rango además varía por horario, así que un "~5 clases" no se
  /// puede sostener.
  String? _subtitulo(Map<String, dynamic> plan) {
    final d = plan['descripcion']?.toString().trim() ?? '';
    return d.isEmpty ? null : d;
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
            borderRadius: BorderRadius.circular(AuraRadio.boton),
          ),
          child: const Text(
            'Podés cancelar cuando quieras desde tu perfil.',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: AuraTipo.secundario,
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
          final badge = _badge(plan);
          final subtitulo = _subtitulo(plan);
          return GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFFDF0E8) : AppColors.white,
                borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
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
                            borderRadius: BorderRadius.circular(AuraRadio.pastilla),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: AuraTipo.etiqueta,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    plan['descripcion']?.toString() ?? '',
                    style: const TextStyle(color: AppColors.grey, fontSize: 12),
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
                            style: TextStyle(fontSize: AuraTipo.secundario, color: AppColors.grey),
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
                          fontSize: AuraTipo.secundario,
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

// ─────────────────────────────────────────────────────────────
// Tab: Regalar (gift a pack to a friend)
// ─────────────────────────────────────────────────────────────

class _RegalarTab extends StatelessWidget {
  final List<Map<String, dynamic>> packs;
  final bool loading;
  final int? selectedIndex;
  final void Function(int) onSelect;

  const _RegalarTab({
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
        Text('Regalá créditos', style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.white,
        )),
        const SizedBox(height: 6),
        Text(
          'Elegí un pack y enviáselo a alguien especial.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 20),
        ...packs.asMap().entries.map((entry) {
          final i = entry.key;
          final pack = entry.value;
          final selected = selectedIndex == i;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
                border: Border.all(
                  color: selected ? AppColors.primary : const Color(0xFF3A3A3A),
                  width: 2,
                ),
              ),
              child: Stack(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${pack['nombre']} · ${pack['creditos']} créditos',
                              style: const TextStyle(
                                fontSize: AuraTipo.titulo,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              pack['descripcion']?.toString() ?? '',
                              style: TextStyle(
                                color: selected ? Colors.white70 : Colors.white54,
                                fontSize: AuraTipo.secundario,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '\$${_fmt((pack['precio'] as num).toInt())}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: AuraTipo.titulo,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected ? AppColors.white : Colors.white38,
                        size: 24,
                      ),
                    ],
                  ),
                  // Gift bow decoration top-right
                  Positioned(
                    top: 0,
                    right: 30,
                    child: Text(
                      '🎁',
                      style: TextStyle(
                        fontSize: selected ? 22 : 18,
                      ),
                    ),
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
