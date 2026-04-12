import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';

class AdminConfigScreen extends StatefulWidget {
  const AdminConfigScreen({super.key});

  @override
  State<AdminConfigScreen> createState() => _AdminConfigScreenState();
}

class _AdminConfigScreenState extends State<AdminConfigScreen> {
  final _service = AdminService();
  final _creditValueCtrl = TextEditingController();
  final _newCategoryCtrl = TextEditingController();

  bool _loading = true;
  bool _savingCredit = false;
  bool _savingCategory = false;
  String? _error;
  Map<String, dynamic>? _pricing;
  List<String> _categories = [];
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _packs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _creditValueCtrl.dispose();
    _newCategoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pricing = await _service.getPricingSnapshot();
      final categories = await _service.listStudyCategories();
      final plans = await _service.listPricingPlans();
      final packs = await _service.listPricingPacks();
      if (!mounted) return;
      _creditValueCtrl.text =
          '${(pricing['valor_credito'] as num?)?.toInt() ?? 6000}';
      setState(() {
        _pricing = pricing;
        _categories = categories;
        _plans = plans;
        _packs = packs;
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

  Future<void> _guardarValorCredito() async {
    final value = int.tryParse(_creditValueCtrl.text.trim());
    if (value == null || value <= 0) return;

    setState(() => _savingCredit = true);
    try {
      await _service.updateGlobalCreditValue(value);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Valor del crédito actualizado y precios recalculados.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingCredit = false);
    }
  }

  Future<void> _agregarCategoria() async {
    final value = _newCategoryCtrl.text.trim();
    if (value.isEmpty) return;
    setState(() => _savingCategory = true);
    try {
      await _service.addStudyCategory(value);
      _newCategoryCtrl.clear();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Categoría agregada.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingCategory = false);
    }
  }

  Future<void> _renameCategory(String current) async {
    final ctrl = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar categoría'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _service.renameStudyCategory(
        oldName: current,
        newName: ctrl.text,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _deleteCategory(String current) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text(
          'Se va a eliminar "$current". Los estudios que la usen quedarán sin categoría.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _service.deleteStudyCategory(current);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _editPlan([Map<String, dynamic>? plan]) async {
    final nombreCtrl =
        TextEditingController(text: plan?['nombre']?.toString() ?? '');
    final creditosCtrl = TextEditingController(
      text: '${(plan?['creditos'] as num?)?.toInt() ?? 0}',
    );
    final precioCtrl = TextEditingController(
      text: '${(plan?['precio'] as num?)?.toInt() ?? 0}',
    );
    final descripcionCtrl =
        TextEditingController(text: plan?['descripcion']?.toString() ?? '');
    final ordenCtrl = TextEditingController(
      text: '${(plan?['orden'] as num?)?.toInt() ?? (_plans.length + 1)}',
    );
    bool activo = plan?['activo'] as bool? ?? true;
    bool destacado = plan?['destacado'] as bool? ?? false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(plan == null ? 'Nuevo plan' : 'Editar plan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: creditosCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Créditos'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: precioCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Precio'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descripcionCtrl,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ordenCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Orden'),
                ),
                SwitchListTile(
                  value: destacado,
                  onChanged: (v) => setLocal(() => destacado = v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Destacado'),
                ),
                SwitchListTile(
                  value: activo,
                  onChanged: (v) => setLocal(() => activo = v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activo'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    await _service.upsertPricingPlan(
      id: (plan?['id'] as num?)?.toInt(),
      nombre: nombreCtrl.text,
      creditos: int.tryParse(creditosCtrl.text) ?? 0,
      precio: int.tryParse(precioCtrl.text) ?? 0,
      descripcion: descripcionCtrl.text,
      ahorro: null,
      destacado: destacado,
      activo: activo,
      orden: int.tryParse(ordenCtrl.text) ?? 0,
    );
    await _load();
  }

  Future<void> _editPack([Map<String, dynamic>? pack]) async {
    final nombreCtrl =
        TextEditingController(text: pack?['nombre']?.toString() ?? '');
    final creditosCtrl = TextEditingController(
      text: '${(pack?['creditos'] as num?)?.toInt() ?? 0}',
    );
    final precioCtrl = TextEditingController(
      text: '${(pack?['precio'] as num?)?.toInt() ?? 0}',
    );
    final descripcionCtrl =
        TextEditingController(text: pack?['descripcion']?.toString() ?? '');
    final ordenCtrl = TextEditingController(
      text: '${(pack?['orden'] as num?)?.toInt() ?? (_packs.length + 1)}',
    );
    bool activo = pack?['activo'] as bool? ?? true;
    bool popular = pack?['popular'] as bool? ?? false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(pack == null ? 'Nuevo pack' : 'Editar pack'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: creditosCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Créditos'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: precioCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Precio'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descripcionCtrl,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ordenCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Orden'),
                ),
                SwitchListTile(
                  value: popular,
                  onChanged: (v) => setLocal(() => popular = v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Popular'),
                ),
                SwitchListTile(
                  value: activo,
                  onChanged: (v) => setLocal(() => activo = v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activo'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    await _service.upsertPricingPack(
      id: (pack?['id'] as num?)?.toInt(),
      nombre: nombreCtrl.text,
      creditos: int.tryParse(creditosCtrl.text) ?? 0,
      precio: int.tryParse(precioCtrl.text) ?? 0,
      descripcion: descripcionCtrl.text,
      popular: popular,
      activo: activo,
      orden: int.tryParse(ordenCtrl.text) ?? 0,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Config global',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => context.go('/home'),
                      child: const Text('Volver a usuario'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Ajustes globales rápidos para operar Aura sin entrar a Supabase.',
                  style: TextStyle(color: AppColors.grey),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  _Block(
                    title: 'No se pudo cargar configuración',
                    body: _error!,
                  )
                else ...[
                  _Panel(
                    title: 'Valor global del crédito',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Al cambiarlo se recalculan automáticamente los precios base de packs y planes.',
                          style: TextStyle(color: AppColors.grey, height: 1.5),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _creditValueCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Valor de 1 crédito',
                            prefixText: '\$ ',
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _savingCredit ? null : _guardarValorCredito,
                            child: _savingCredit
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: AppColors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Guardar valor'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Panel(
                    title: 'Categorías de estudios',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._categories.map(
                          (item) => Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: () => _renameCategory(item),
                                  child: const Text('Editar'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: () => _deleteCategory(item),
                                  child: const Text('Eliminar'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _newCategoryCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Nueva categoría',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: _savingCategory ? null : _agregarCategoria,
                              child: _savingCategory
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        color: AppColors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Agregar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PricingSection(
                    title: 'Planes',
                    items: _plans,
                    onAdd: () => _editPlan(),
                    onEdit: _editPlan,
                  ),
                  const SizedBox(height: 12),
                  _PricingSection(
                    title: 'Packs / compra de créditos',
                    items: _packs,
                    onAdd: () => _editPack(),
                    onEdit: _editPack,
                  ),
                  const SizedBox(height: 12),
                  _Block(
                    title: 'Resumen textual',
                    body:
                        'Planes:\n${(_pricing?['planes_text'] as String?) ?? 'Sin datos'}\n\nPacks:\n${(_pricing?['packs_text'] as String?) ?? 'Sin datos'}',
                  ),
                ],
              ],
            ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;

  const _Panel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _PricingSection extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  final VoidCallback onAdd;
  final void Function(Map<String, dynamic>) onEdit;

  const _PricingSection({
    required this.title,
    required this.items,
    required this.onAdd,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: title,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Agregar'),
            ),
          ),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['nombre']?.toString() ?? 'Sin nombre',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(item['creditos'] as num?)?.toInt() ?? 0} cr · \$${(item['precio'] as num?)?.toInt() ?? 0}',
                          style: const TextStyle(color: AppColors.grey),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => onEdit(item),
                    child: const Text('Editar'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  final String title;
  final String body;

  const _Block({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(color: AppColors.grey, height: 1.5),
          ),
        ],
      ),
    );
  }
}
