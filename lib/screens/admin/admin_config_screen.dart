import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';
import '../../services/pricing_service.dart';

class AdminConfigScreen extends StatefulWidget {
  const AdminConfigScreen({super.key});

  @override
  State<AdminConfigScreen> createState() => _AdminConfigScreenState();
}

class _AdminConfigScreenState extends State<AdminConfigScreen> {
  final _service = AdminService();
  final _pricingService = PricingService();
  final _creditValueCtrl = TextEditingController();
  final _newCategoryCtrl = TextEditingController();

  bool _loading = true;
  bool _savingCredit = false;
  bool _savingCategory = false;
  bool _savingToggleCreditos = false;
  bool _savingCreditosCat = false;
  bool _estudiosDefinenCreditos = false;
  String? _error;
  Map<String, dynamic>? _pricing;
  List<String> _categories = [];
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _packs = [];

  // Preview de packs en vivo mientras edita el valor
  int _valorCreditoActual = 1000;
  int _valorCreditoPreview = 1000;

  // Tabla de creditos por categoria
  final Map<String, TextEditingController> _categoriaCreditosCtrls = {};

  @override
  void initState() {
    super.initState();
    _creditValueCtrl.addListener(_actualizarPreviewValor);
    _load();
  }

  @override
  void dispose() {
    _creditValueCtrl.removeListener(_actualizarPreviewValor);
    _creditValueCtrl.dispose();
    _newCategoryCtrl.dispose();
    for (final ctrl in _categoriaCreditosCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _actualizarPreviewValor() {
    final parsed = int.tryParse(_creditValueCtrl.text.trim());
    if (parsed == null || parsed <= 0) return;
    if (parsed == _valorCreditoPreview) return;
    setState(() => _valorCreditoPreview = parsed);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.getPricingSnapshot(),
        _service.listStudyCategories(),
        _service.listPricingPlans(),
        _service.listPricingPacks(),
        _service.getConfigGlobal('estudios_definen_creditos'),
        _service.getValorCreditoArs(),
        _service.getCreditosPorCategoria(),
      ]);
      final pricing = results[0] as Map<String, dynamic>;
      final categories = results[1] as List<String>;
      final plans = results[2] as List<Map<String, dynamic>>;
      final packs = results[3] as List<Map<String, dynamic>>;
      final configCreditos = results[4] as String?;
      final valorCreditoArs = results[5] as int;
      final creditosPorCat = results[6] as Map<String, int>;
      if (!mounted) return;

      _creditValueCtrl.text = '$valorCreditoArs';

      // Sync controllers para creditos por categoria.
      // Las categorias canonicas vienen de la lista de categorias del estudio.
      final mergedCats = <String>{
        ...creditosPorCat.keys,
        ...categories,
      }.toList();
      // Disposear los que ya no estan
      _categoriaCreditosCtrls.removeWhere((key, ctrl) {
        if (!mergedCats.contains(key)) {
          ctrl.dispose();
          return true;
        }
        return false;
      });
      // Crear/actualizar controllers
      for (final cat in mergedCats) {
        final value = creditosPorCat[cat] ?? 0;
        if (_categoriaCreditosCtrls.containsKey(cat)) {
          _categoriaCreditosCtrls[cat]!.text = '$value';
        } else {
          _categoriaCreditosCtrls[cat] =
              TextEditingController(text: '$value');
        }
      }

      setState(() {
        _pricing = pricing;
        _categories = categories;
        _plans = plans;
        _packs = packs;
        _estudiosDefinenCreditos = configCreditos == 'true';
        _valorCreditoActual = valorCreditoArs;
        _valorCreditoPreview = valorCreditoArs;
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

  Future<void> _toggleEstudiosDefinenCreditos(bool value) async {
    setState(() => _savingToggleCreditos = true);
    try {
      await _service.setConfigGlobal(
        'estudios_definen_creditos',
        value ? 'true' : 'false',
      );
      if (!mounted) return;
      setState(() => _estudiosDefinenCreditos = value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Los estudios ahora pueden definir sus propios créditos.'
                : 'Los créditos son asignados automáticamente por Aura.',
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
      if (mounted) setState(() => _savingToggleCreditos = false);
    }
  }

  Future<void> _guardarValorCredito() async {
    final value = int.tryParse(_creditValueCtrl.text.trim());
    if (value == null || value <= 0) return;

    setState(() => _savingCredit = true);
    try {
      await _service.setValorCreditoArs(value);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Valor del crédito actualizado. Los precios de los packs se recalcularon automáticamente.',
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

  List<String> _categoriasParaCreditos() {
    final list = _categoriaCreditosCtrls.keys.toList()..sort();
    return list;
  }

  Future<void> _guardarCreditosPorCategoria() async {
    setState(() => _savingCreditosCat = true);
    try {
      final map = <String, int>{};
      for (final entry in _categoriaCreditosCtrls.entries) {
        final parsed = int.tryParse(entry.value.text.trim());
        if (parsed != null && parsed > 0) {
          map[entry.key] = parsed;
        }
      }
      await _service.setCreditosPorCategoria(map);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Créditos por categoría guardados.'),
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
      if (mounted) setState(() => _savingCreditosCat = false);
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
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
      ),
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
                  Text(
                    'PRECIOS',
                    style: const TextStyle(
                      color: AppColors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ValorCreditoCard(
                    controller: _creditValueCtrl,
                    valorActual: _valorCreditoActual,
                    saving: _savingCredit,
                    onGuardar: _guardarValorCredito,
                  ),
                  const SizedBox(height: 12),
                  _PreviewPacksCard(
                    valorCredito: _valorCreditoPreview,
                    pricingService: _pricingService,
                    cambiado: _valorCreditoPreview != _valorCreditoActual,
                  ),
                  const SizedBox(height: 16),
                  _CreditosPorCategoriaCard(
                    categorias: _categoriasParaCreditos(),
                    controllers: _categoriaCreditosCtrls,
                    valorCredito: _valorCreditoActual,
                    saving: _savingCreditosCat,
                    onGuardar: _guardarCreditosPorCategoria,
                  ),
                  const SizedBox(height: 16),
                  _Panel(
                    title: 'Créditos por clase',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Controlá si los estudios pueden definir el precio de cada clase o si Aura lo asigna según la categoría.',
                          style: TextStyle(color: AppColors.grey, height: 1.5),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _estudiosDefinenCreditos,
                          onChanged: _savingToggleCreditos ? null : _toggleEstudiosDefinenCreditos,
                          title: const Text(
                            'Permitir que estudios definan sus propios créditos',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            _estudiosDefinenCreditos
                                ? 'Activo — cada estudio puede editar los créditos al crear o editar una clase.'
                                : 'Inactivo — el precio lo define Aura según la categoría. Los estudios no pueden modificarlo.',
                            style: const TextStyle(color: AppColors.grey, height: 1.4),
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

class _ValorCreditoCard extends StatelessWidget {
  final TextEditingController controller;
  final int valorActual;
  final bool saving;
  final VoidCallback onGuardar;

  const _ValorCreditoCard({
    required this.controller,
    required this.valorActual,
    required this.saving,
    required this.onGuardar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Valor del crédito',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Actual: \$${_fmt(valorActual)} ARS por crédito',
            style: const TextStyle(color: Color(0xFF8F8A85), fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: const InputDecoration(
              labelText: 'Nuevo valor',
              labelStyle: TextStyle(color: Color(0xFF8F8A85)),
              prefixText: '\$ ',
              prefixStyle: TextStyle(color: Colors.white),
              filled: true,
              fillColor: Color(0xFF222222),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: Color(0xFF333333)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: AppColors.primary, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: saving ? null : onGuardar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Actualizar',
                      style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Al cambiar este valor todos los packs se actualizan solos.',
            style: TextStyle(color: Color(0xFF8F8A85), fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _fmt(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      );
}

class _PreviewPacksCard extends StatelessWidget {
  final int valorCredito;
  final PricingService pricingService;
  final bool cambiado;

  const _PreviewPacksCard({
    required this.valorCredito,
    required this.pricingService,
    required this.cambiado,
  });

  @override
  Widget build(BuildContext context) {
    final packs = pricingService.packsConValor(valorCredito);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: cambiado ? AppColors.primary : AppColors.lightGrey,
          width: cambiado ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  cambiado
                      ? 'Preview con el nuevo valor'
                      : 'Precios actuales de los 4 packs',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (cambiado)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'NUEVO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ...packs.map((pack) {
            final nombre = pack['nombre']?.toString() ?? '';
            final creditos = (pack['creditos'] as num).toInt();
            final precio = (pack['precio'] as num).toInt();
            final mult = (pack['multiplicador'] as num).toDouble();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$nombre · $creditos cr',
                          style:
                              const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '$creditos × \$${_fmt(valorCredito)} × ${(mult * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                              color: AppColors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '\$${_fmt(precio)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _fmt(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      );
}

class _CreditosPorCategoriaCard extends StatelessWidget {
  final List<String> categorias;
  final Map<String, TextEditingController> controllers;
  final int valorCredito;
  final bool saving;
  final VoidCallback onGuardar;

  const _CreditosPorCategoriaCard({
    required this.categorias,
    required this.controllers,
    required this.valorCredito,
    required this.saving,
    required this.onGuardar,
  });

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
          const Text(
            'Créditos por categoría',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'Cuántos créditos vale una clase de cada categoría.',
            style: TextStyle(color: AppColors.grey, fontSize: 12),
          ),
          const SizedBox(height: 14),
          ...categorias.map((cat) {
            final ctrl = controllers[cat]!;
            return _CategoriaCreditosRow(
              categoria: cat,
              controller: ctrl,
              valorCredito: valorCredito,
            );
          }),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: saving ? null : onGuardar,
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Guardar categorías'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoriaCreditosRow extends StatefulWidget {
  final String categoria;
  final TextEditingController controller;
  final int valorCredito;

  const _CategoriaCreditosRow({
    required this.categoria,
    required this.controller,
    required this.valorCredito,
  });

  @override
  State<_CategoriaCreditosRow> createState() => _CategoriaCreditosRowState();
}

class _CategoriaCreditosRowState extends State<_CategoriaCreditosRow> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final creditos = int.tryParse(widget.controller.text.trim()) ?? 0;
    final montoEstudio =
        (widget.valorCredito * creditos * 0.70).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.categoria,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: widget.controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    suffixText: 'cr',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 8, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Estudio recibe \$${_fmt(montoEstudio)} por clase',
            style: const TextStyle(color: AppColors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _fmt(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      );
}
