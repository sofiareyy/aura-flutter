import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../services/pricing_service.dart';
import '../../services/usuarios_service.dart';
// ignore_for_file: use_build_context_synchronously

class CambiarPlanScreen extends StatefulWidget {
  const CambiarPlanScreen({super.key});

  @override
  State<CambiarPlanScreen> createState() => _CambiarPlanScreenState();
}

class _CambiarPlanScreenState extends State<CambiarPlanScreen> {
  int? _selectedPlan;
  bool _loading = false;
  bool _loadingPlanes = true;
  final _usuariosService = UsuariosService();
  final _pricingService = PricingService();
  List<Map<String, dynamic>> _planes = [];

  @override
  void initState() {
    super.initState();
    _loadPlanes();
  }

  Future<void> _loadPlanes() async {
    final planes = await _pricingService.getPlanes();
    planes.sort((a, b) {
      final ordenA = (a['orden'] as num?)?.toInt() ?? 999;
      final ordenB = (b['orden'] as num?)?.toInt() ?? 999;
      if (ordenA != ordenB) return ordenA.compareTo(ordenB);
      final precioA = (a['precio'] as num?)?.toInt() ?? 0;
      final precioB = (b['precio'] as num?)?.toInt() ?? 0;
      return precioA.compareTo(precioB);
    });
    if (mounted) {
      setState(() {
        _planes = planes;
        _loadingPlanes = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fromRegistro =
        GoRouterState.of(context).uri.queryParameters['from'] == 'registro';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(fromRegistro ? 'Elegí tu plan' : 'Cambiar plan'),
        automaticallyImplyLeading: !fromRegistro,
        leading: fromRegistro
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              ),
        actions: fromRegistro
            ? [
                TextButton(
                  onPressed:
                      _loading ? null : () => _omitir(context.read<AppProvider>()),
                  child: const Text(
                    'Omitir',
                    style: TextStyle(
                      color: Color(0xFF8F877F),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ]
            : null,
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          final planActual = provider.usuario?.plan ?? '';
          return Column(
            children: [
              Expanded(
                child: _loadingPlanes
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          Text(
                            'Elegí tu plan',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Los créditos se renuevan mensualmente',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.grey),
                          ),
                          const SizedBox(height: 20),
                          ..._planes.asMap().entries.map((entry) {
                            final i = entry.key;
                            final plan = entry.value;
                            final selected = _selectedPlan == i;
                            final esCurrent = plan['nombre'] == planActual;

                            return GestureDetector(
                              onTap: esCurrent
                                  ? null
                                  : () => setState(() => _selectedPlan = i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppColors.primary
                                      : esCurrent
                                          ? AppColors.primaryLight
                                          : AppColors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: selected
                                        ? AppColors.primary
                                        : esCurrent
                                            ? AppColors.primary
                                            : AppColors.lightGrey,
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
                                              color: selected
                                                  ? AppColors.white
                                                  : AppColors.black,
                                            ),
                                          ),
                                        ),
                                        if (plan['destacado'] == true)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: selected
                                                  ? AppColors.white
                                                  : AppColors.primary,
                                              borderRadius:
                                                  BorderRadius.circular(9999),
                                            ),
                                            child: Text(
                                              'Más popular',
                                              style: TextStyle(
                                                color: selected
                                                    ? AppColors.primary
                                                    : AppColors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        if (esCurrent)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.2),
                                              borderRadius:
                                                  BorderRadius.circular(9999),
                                            ),
                                            child: const Text(
                                              'Actual',
                                              style: TextStyle(
                                                color: AppColors.primary,
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
                                        color: selected
                                            ? Colors.white70
                                            : AppColors.grey,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${plan['creditos']}',
                                          style: TextStyle(
                                            fontSize: 32,
                                            fontWeight: FontWeight.w700,
                                            color: selected
                                                ? AppColors.white
                                                : AppColors.black,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              bottom: 6, left: 4),
                                          child: Text(
                                            'cr/mes',
                                            style: TextStyle(
                                              color: selected
                                                  ? Colors.white60
                                                  : AppColors.grey,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          '\$${_fmt((plan['precio'] as num).toInt())}',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                            color: selected
                                                ? AppColors.white
                                                : AppColors.black,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _ejemploPlan(plan),
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white70
                                            : AppColors.primary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
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
                    20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
                color: AppColors.white,
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (_selectedPlan == null || _loadingPlanes)
                        ? null
                        : () => _cambiar(fromRegistro: fromRegistro),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: AppColors.white, strokeWidth: 2),
                          )
                        : const Text('Confirmar plan'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _cambiar({required bool fromRegistro}) {
    if (_selectedPlan == null) return;
    final plan = _planes[_selectedPlan!];
    context.push(
      '/checkout',
      extra: {
        'type': 'plan',
        'nombre': plan['nombre'],
        'creditos': (plan['creditos'] as num).toInt(),
        'precio': (plan['precio'] as num).toInt(),
        'descripcion': plan['descripcion']?.toString() ?? '',
      },
    );
  }

  String _ejemploPlan(Map<String, dynamic> plan) {
    final nombre = (plan['nombre'] ?? '').toString().toLowerCase();
    if (nombre.contains('starter')) {
      return 'Ejemplo: 4 pilates + 1 yoga por mes';
    }
    if (nombre.contains('explorer')) {
      return 'Ejemplo: 6 pilates + 1 yoga por mes';
    }
    if (nombre.contains('unlimited')) {
      return 'Ejemplo: pensado para usarlo todas las semanas';
    }
    return 'Ejemplo: combiná tus créditos como prefieras';
  }

  Future<void> _omitir(AppProvider provider) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      if (provider.userId.isNotEmpty) {
        await _usuariosService.updateUsuario(provider.userId, {
          'plan': 'Sin plan',
          'creditos': provider.usuario?.creditos ?? 0,
          'creditos_vencimiento': null,
        });
        await provider.refrescarUsuario();
      }
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(int n) => n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
}
