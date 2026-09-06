import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';
import '../../services/pricing_service.dart';
import 'admin_export_helper.dart';
import '../../widgets/ancho_maximo.dart';

class AdminUsuariosScreen extends StatefulWidget {
  const AdminUsuariosScreen({super.key});

  @override
  State<AdminUsuariosScreen> createState() => _AdminUsuariosScreenState();
}

class _AdminUsuariosScreenState extends State<AdminUsuariosScreen> {
  final _service = AdminService();
  final _pricing = PricingService();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _users = [];

  /// Nombres de plan reales, leídos de `pricing_planes`. Antes era una lista
  /// fija que mezclaba planes con nombres de packs ('Essential', 'Popular',
  /// 'Full') y quedaba desactualizada cada vez que se renombraba un plan.
  List<String> _planesDisponibles = const [];

  List<String> get _planOptions => ['Sin plan', ..._planesDisponibles];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await _service.listUsuarios(search: _searchCtrl.text);
      final planes = await _cargarNombresDePlan();
      if (!mounted) return;
      setState(() {
        _users = users;
        _planesDisponibles = planes;
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

  /// Si `pricing_planes` falla, cae al fallback de AppConstants en vez de
  /// dejar el desplegable vacío.
  Future<List<String>> _cargarNombresDePlan() async {
    try {
      final planes = await _pricing.getPlanes();
      final nombres = planes
          .map((p) => p['nombre']?.toString().trim() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      if (nombres.isNotEmpty) return nombres;
    } catch (_) {
      // Cae al fallback de abajo.
    }
    return AppConstants.planes.map((p) => p['nombre'].toString()).toList();
  }

  Future<void> _confirmarEliminarUsuario(Map<String, dynamic> user) async {
    final nombre = user['nombre']?.toString().trim().isNotEmpty == true
        ? user['nombre'].toString().trim()
        : (user['email']?.toString() ?? 'este usuario');
    final uid = user['id']?.toString() ?? '';
    if (uid.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '¿Eliminar la cuenta?',
          style: TextStyle(
            color: AppColors.black,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '¿Eliminar la cuenta de $nombre? Se eliminarán todos sus datos '
          'y reservas. No se puede deshacer.',
          style: const TextStyle(
            color: AppColors.black,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: AppColors.grey),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text(
              'Sí, eliminar',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    // Loader bloqueante mientras la edge function corre.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    try {
      await _service.eliminarUsuario(uid);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      // Sacar de la lista en memoria + refrescar desde server para
      // sumar el cleanup colateral.
      setState(() {
        _users = _users.where((u) => u['id']?.toString() != uid).toList();
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text('Cuenta de $nombre eliminada.'),
          backgroundColor: AppColors.blackSoft,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo eliminar: '
            '${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _ajustarCreditos(Map<String, dynamic> user) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ajustar créditos de ${user['nombre'] ?? 'usuario'}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Cantidad',
            hintText: 'Ej: 20 o -10',
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
    );
    if (ok != true) return;

    final delta = int.tryParse(ctrl.text.trim());
    if (delta == null) return;
    await _service.adjustCreditos(userId: user['id'].toString(), delta: delta);
    await _load();
  }

  Future<void> _editarUsuario(Map<String, dynamic> user) async {
    final nombreCtrl = TextEditingController(
      text: user['nombre']?.toString() ?? '',
    );

    // Normaliza el plan actual contra las opciones (case-insensitive).
    final planActual = user['plan']?.toString().trim() ?? '';
    String selectedPlan = _planOptions.firstWhere(
      (p) => p.toLowerCase() == planActual.toLowerCase(),
      orElse: () => 'Sin plan',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Editar usuario'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedPlan,
                decoration: const InputDecoration(labelText: 'Plan'),
                items: _planOptions
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) =>
                    setDialogState(() => selectedPlan = v ?? 'Sin plan'),
              ),
            ],
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

    await _service.updateUsuario(
      userId: user['id'].toString(),
      nombre: nombreCtrl.text,
      // 'Sin plan' se guarda como null en usuarios.plan.
      plan: selectedPlan == 'Sin plan' ? null : selectedPlan,
    );
    await _load();
  }

  Future<void> _exportarUsuarios() async {
    if (_users.isEmpty) return;
    final buffer = StringBuffer()
      ..writeln('Usuarios Aura')
      ..writeln('');
    for (final user in _users) {
      buffer.writeln(
        '${user['nombre'] ?? 'Sin nombre'} | ${user['email'] ?? ''} | Plan: ${((user['plan']?.toString().isNotEmpty ?? false) ? user['plan'] : 'Sin plan')} | Créditos: ${user['creditos'] ?? 0}',
      );
    }

    final content = buffer.toString();
    final downloaded = await downloadAdminReport(
      filename: 'aura-usuarios.txt',
      content: content,
    );
    if (!downloaded) {
      await Clipboard.setData(ClipboardData(text: content));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          downloaded
              ? 'Usuarios exportados.'
              : 'Usuarios copiados para compartir.',
        ),
        backgroundColor: AppColors.success,
      ),
    );
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
      body: AnchoMaximo(
        child: _loading
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
                          'Usuarios',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _users.isEmpty ? null : _exportarUsuarios,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Exportar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Buscá usuarios y resolvé rápido créditos o plan cuando haga falta.',
                    style: TextStyle(color: AppColors.grey),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre o email',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _load,
                      ),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    _ErrorCard(message: _error!)
                  else if (_users.isEmpty)
                    const _EmptyCard(message: 'No hay usuarios para mostrar.')
                  else
                    ..._users.map(
                      (user) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    user['nombre']?.toString() ?? 'Sin nombre',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${user['creditos'] ?? 0} cr',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                PopupMenuButton<String>(
                                  icon: const Icon(
                                    Icons.more_vert_rounded,
                                    color: AppColors.grey,
                                    size: 20,
                                  ),
                                  tooltip: 'Más opciones',
                                  onSelected: (value) async {
                                    if (value == 'eliminar') {
                                      await _confirmarEliminarUsuario(user);
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    const PopupMenuItem(
                                      value: 'eliminar',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.delete_forever_rounded,
                                            color: AppColors.error,
                                            size: 18,
                                          ),
                                          SizedBox(width: 10),
                                          Text(
                                            'Eliminar cuenta',
                                            style: TextStyle(
                                              color: AppColors.error,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user['email']?.toString() ?? '',
                              style: const TextStyle(color: AppColors.grey),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Plan actual: ${(user['plan']?.toString().isNotEmpty == true) ? user['plan'] : 'Sin plan'}',
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _editarUsuario(user),
                                    child: const Text('Editar'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => _ajustarCreditos(user),
                                    child: const Text('Ajustar créditos'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(message, style: const TextStyle(color: AppColors.error)),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;

  const _EmptyCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(message, style: const TextStyle(color: AppColors.grey)),
    );
  }
}
