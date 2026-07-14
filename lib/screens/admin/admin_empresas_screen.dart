import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';

/// Backoffice — Empresas (usuarios corporativos).
///
/// Permite listar empresas, crear/editar (nombre, dominio, créditos/empleado),
/// activar/desactivar y ver los empleados registrados de cada una con cuántos
/// créditos usaron este mes.
class AdminEmpresasScreen extends StatefulWidget {
  const AdminEmpresasScreen({super.key});

  @override
  State<AdminEmpresasScreen> createState() => _AdminEmpresasScreenState();
}

class _AdminEmpresasScreenState extends State<AdminEmpresasScreen> {
  final _service = AdminService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _empresas = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final empresas = await _service.listEmpresas();
      if (!mounted) return;
      setState(() {
        _empresas = empresas;
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

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  Future<void> _openForm([Map<String, dynamic>? empresa]) async {
    final nombreCtrl =
        TextEditingController(text: empresa?['nombre']?.toString() ?? '');
    final dominioCtrl =
        TextEditingController(text: empresa?['dominio_mail']?.toString() ?? '');
    final creditosCtrl = TextEditingController(
      text: (empresa?['creditos_por_empleado'] as num?)?.toInt().toString() ??
          '',
    );
    bool activa = empresa?['activa'] as bool? ?? true;
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(empresa == null ? 'Nueva empresa' : 'Editar empresa'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: nombreCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de la empresa',
                      ),
                      validator: (v) => (v == null || v.trim().length < 2)
                          ? 'Ingresá un nombre'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: dominioCtrl,
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Dominio de mail',
                        hintText: 'empresa.com',
                        helperText:
                            'Solo el dominio, sin @. Los empleados que se '
                            'registren con este dominio se vinculan solos.',
                        helperMaxLines: 3,
                      ),
                      validator: (v) {
                        final d = v?.trim().toLowerCase() ?? '';
                        if (d.isEmpty) return 'Ingresá el dominio';
                        if (d.contains('@') || !d.contains('.')) {
                          return 'Dominio inválido (ej: empresa.com)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: creditosCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Créditos por empleado',
                        helperText:
                            'Se acreditan al vincularse y el día 1 de cada mes.',
                        helperMaxLines: 2,
                        suffixText: 'cr',
                      ),
                      validator: (v) {
                        final n = int.tryParse(v?.trim() ?? '');
                        if (n == null || n <= 0) return 'Ingresá un número > 0';
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: activa,
                      onChanged: (value) => setLocal(() => activa = value),
                      title: Text(activa ? 'Activa' : 'Inactiva'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setLocal(() => saving = true);
                      try {
                        await _service.upsertEmpresa(
                          empresaId: (empresa?['id'] as num?)?.toInt(),
                          nombre: nombreCtrl.text,
                          dominioMail: dominioCtrl.text,
                          creditosPorEmpleado:
                              int.parse(creditosCtrl.text.trim()),
                          activa: activa,
                        );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx, true);
                      } catch (e) {
                        setLocal(() => saving = false);
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content:
                                Text(e.toString().replaceFirst('Exception: ', '')),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    nombreCtrl.dispose();
    dominioCtrl.dispose();
    creditosCtrl.dispose();

    if (ok == true) {
      _snack(empresa == null ? 'Empresa creada.' : 'Empresa actualizada.');
      await _load();
    }
  }

  Future<void> _toggleActiva(Map<String, dynamic> empresa) async {
    final id = (empresa['id'] as num?)?.toInt();
    if (id == null) return;
    final activa = empresa['activa'] as bool? ?? false;
    try {
      await _service.setEmpresaActiva(empresaId: id, activa: !activa);
      _snack(!activa ? 'Empresa activada.' : 'Empresa desactivada.');
      await _load();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _verEmpleados(Map<String, dynamic> empresa) async {
    final id = (empresa['id'] as num?)?.toInt();
    if (id == null) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _EmpleadosDialog(
        empresaId: id,
        empresaNombre: empresa['nombre']?.toString() ?? 'Empresa',
        service: _service,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Empresas',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Nueva empresa',
              icon: const Icon(Icons.add_rounded, color: AppColors.primary),
              onPressed: () => _openForm(),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  const Text(
                    'Empresas que ofrecen Aura como beneficio. Los empleados que '
                    'se registran con el dominio de la empresa reciben créditos '
                    'automáticamente cada mes.',
                    style: TextStyle(color: AppColors.grey, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        'No se pudieron cargar las empresas.\n$_error',
                        style: const TextStyle(color: AppColors.error),
                      ),
                    )
                  else if (_empresas.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Text(
                        'Todavía no hay empresas cargadas.',
                        style: TextStyle(color: AppColors.grey),
                      ),
                    )
                  else
                    ..._empresas.map(_buildEmpresaCard),
                ],
              ),
            ),
    );
  }

  Widget _buildEmpresaCard(Map<String, dynamic> empresa) {
    final activa = empresa['activa'] as bool? ?? false;
    final empleados = (empresa['empleados_count'] as num?)?.toInt() ?? 0;
    final usados = (empresa['creditos_usados_mes'] as num?)?.toInt() ?? 0;
    final creditos = (empresa['creditos_por_empleado'] as num?)?.toInt() ?? 0;

    return Container(
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
                  empresa['nombre']?.toString() ?? 'Sin nombre',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (activa ? AppColors.success : AppColors.grey)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  activa ? 'Activa' : 'Inactiva',
                  style: TextStyle(
                    color: activa ? AppColors.success : AppColors.grey,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.grey),
                onSelected: (value) {
                  if (value == 'toggle') _toggleActiva(empresa);
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem<String>(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(
                          activa
                              ? Icons.pause_circle_outline_rounded
                              : Icons.play_circle_outline_rounded,
                          size: 20,
                          color: AppColors.black,
                        ),
                        const SizedBox(width: 8),
                        Text(activa ? 'Desactivar' : 'Activar'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${empresa['dominio_mail'] ?? ''}  ·  $creditos cr/empleado',
            style: const TextStyle(color: AppColors.grey, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MetricPill(
                icon: Icons.people_outline_rounded,
                label: '$empleados empleado${empleados == 1 ? '' : 's'}',
              ),
              const SizedBox(width: 8),
              _MetricPill(
                icon: Icons.bolt_outlined,
                label: '$usados cr usados este mes',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openForm(empresa),
                  child: const Text('Editar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _verEmpleados(empresa),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.black,
                  ),
                  child: const Text('Empleados'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetricPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.grey),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.blackSoft,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Diálogo con los empleados registrados de una empresa y sus créditos.
class _EmpleadosDialog extends StatefulWidget {
  final int empresaId;
  final String empresaNombre;
  final AdminService service;

  const _EmpleadosDialog({
    required this.empresaId,
    required this.empresaNombre,
    required this.service,
  });

  @override
  State<_EmpleadosDialog> createState() => _EmpleadosDialogState();
}

class _EmpleadosDialogState extends State<_EmpleadosDialog> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _empleados = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.service.listEmpresaEmpleados(widget.empresaId);
      if (!mounted) return;
      setState(() {
        _empleados = data;
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Empleados · ${widget.empresaNombre}'),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            : _error != null
                ? Text(_error!, style: const TextStyle(color: AppColors.error))
                : _empleados.isEmpty
                    ? const Text(
                        'Todavía no hay empleados registrados con este dominio.',
                        style: TextStyle(color: AppColors.grey),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: _empleados.map((e) {
                            final saldo =
                                (e['creditos'] as num?)?.toInt() ?? 0;
                            final usados =
                                (e['creditos_usados_mes'] as num?)?.toInt() ??
                                    0;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e['nombre']?.toString() ?? 'Sin nombre',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          e['email']?.toString() ?? '',
                                          style: const TextStyle(
                                            color: AppColors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '$saldo cr',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      Text(
                                        '$usados usados este mes',
                                        style: const TextStyle(
                                          color: AppColors.grey,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
