import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../services/pricing_service.dart';

class ComprarCreditosScreen extends StatefulWidget {
  const ComprarCreditosScreen({super.key});

  @override
  State<ComprarCreditosScreen> createState() => _ComprarCreditosScreenState();
}

class _ComprarCreditosScreenState extends State<ComprarCreditosScreen> {
  int? _selectedPack;
  bool _loadingPacks = true;
  final _pricingService = PricingService();
  List<Map<String, dynamic>> _packs = [];

  @override
  void initState() {
    super.initState();
    _loadPacks();
  }

  Future<void> _loadPacks() async {
    final packs = await _pricingService.getPacks();
    if (!mounted) return;
    setState(() {
      _packs = packs;
      _loadingPacks = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Comprar créditos'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loadingPacks
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        'Elegí un pack',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Comprá créditos cuando quieras y usalos para reservar tus clases y experiencias.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.grey),
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
                              style: TextStyle(
                                color: AppColors.black,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Pack Prueba: vence a los 60 días. Pack Esencial, Popular y Full: vencen a los 90 días.',
                              style: TextStyle(
                                color: AppColors.grey,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      ..._packs.asMap().entries.map((entry) {
                        final i = entry.key;
                        final pack = entry.value;
                        final selected = _selectedPack == i;
                        final vigencia =
                            (pack['vigencia_dias'] as num?)?.toInt() ?? 90;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedPack = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color:
                                  selected ? AppColors.primary : AppColors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.lightGrey,
                                width: 2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${pack['nombre']} · ${pack['creditos']} créditos',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w700,
                                                color: selected
                                                    ? AppColors.white
                                                    : AppColors.black,
                                              ),
                                            ),
                                          ),
                                          if (pack['popular'] == true) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: selected
                                                    ? AppColors.white
                                                    : AppColors.primary,
                                                borderRadius:
                                                    BorderRadius.circular(9999),
                                              ),
                                              child: Text(
                                                'Más elegido',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: selected
                                                      ? AppColors.primary
                                                      : AppColors.white,
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
                                          color: selected
                                              ? Colors.white70
                                              : AppColors.grey,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Vigencia: $vigencia días',
                                        style: TextStyle(
                                          color: selected
                                              ? Colors.white70
                                              : AppColors.grey,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        '\$${_formatPrecio((pack['precio'] as num).toInt())}',
                                        style: TextStyle(
                                          color: selected
                                              ? AppColors.white
                                              : AppColors.black,
                                          fontSize: 18,
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
                                  color: selected
                                      ? AppColors.white
                                      : AppColors.lightGrey,
                                  size: 24,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
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
                onPressed:
                    (_selectedPack == null || _loadingPacks) ? null : _continuarAlPago,
                child: Text(
                  _selectedPack != null
                      ? 'Continuar al checkout'
                      : 'Seleccioná un pack',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatPrecio(int precio) {
    return precio.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
  }

  void _continuarAlPago() {
    if (_selectedPack == null) return;
    final pack = _packs[_selectedPack!];
    context.push(
      '/checkout',
      extra: {
        'type': 'pack',
        'nombre': pack['nombre'],
        'creditos': (pack['creditos'] as num).toInt(),
        'precio': (pack['precio'] as num).toInt(),
        'vigencia_dias': (pack['vigencia_dias'] as num?)?.toInt() ?? 90,
        'descripcion': pack['descripcion']?.toString() ?? '',
      },
    );
  }
}
