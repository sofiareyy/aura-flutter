import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';
import 'admin_export_helper.dart';

class AdminUsuariosScreen extends StatefulWidget {
  const AdminUsuariosScreen({super.key});

  @override
  State<AdminUsuariosScreen> createState() => _AdminUsuariosScreenState();
}

class _AdminUsuariosScreenState extends State<AdminUsuariosScreen> {
  final _service = AdminService();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _users = [];

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
      if (!mounted) return;
      setState(() {
        _users = users;
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
    final nombreCtrl =
        TextEditingController(text: user['nombre']?.toString() ?? '');
    final planCtrl = TextEditingController(text: user['plan']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar usuario'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: planCtrl,
              decoration: const InputDecoration(labelText: 'Plan'),
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
    );
    if (ok != true) return;

    await _service.updateUsuario(
      userId: user['id'].toString(),
      nombre: nombreCtrl.text,
      plan: planCtrl.text,
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
          downloaded ? 'Usuarios exportados.' : 'Usuarios copiados para compartir.',
        ),
        backgroundColor: AppColors.success,
      ),
    );
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
