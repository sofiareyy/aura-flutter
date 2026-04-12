import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';
import '../../services/media_upload_service.dart';

class AdminEstudiosScreen extends StatefulWidget {
  const AdminEstudiosScreen({super.key});

  @override
  State<AdminEstudiosScreen> createState() => _AdminEstudiosScreenState();
}

class _AdminEstudiosScreenState extends State<AdminEstudiosScreen> {
  final _service = AdminService();
  final _mediaUploadService = MediaUploadService();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _studios = [];
  List<String> _categories = [];

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
      final studios = await _service.listEstudios(search: _searchCtrl.text);
      final categories = await _service.listStudyCategories();
      if (!mounted) return;
      setState(() {
        _studios = studios;
        _categories = categories;
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

  Future<void> _openForm([Map<String, dynamic>? estudio]) async {
    final nombreCtrl =
        TextEditingController(text: estudio?['nombre']?.toString() ?? '');
    final barrioCtrl =
        TextEditingController(text: estudio?['barrio']?.toString() ?? '');
    final direccionCtrl =
        TextEditingController(text: estudio?['direccion']?.toString() ?? '');
    final descripcionCtrl =
        TextEditingController(text: estudio?['descripcion']?.toString() ?? '');
    final fotoCtrl =
        TextEditingController(text: estudio?['foto_url']?.toString() ?? '');
    final instagramCtrl =
        TextEditingController(text: estudio?['instagram']?.toString() ?? '');
    final whatsappCtrl =
        TextEditingController(text: estudio?['whatsapp']?.toString() ?? '');
    final webCtrl =
        TextEditingController(text: estudio?['web']?.toString() ?? '');
    final latCtrl =
        TextEditingController(text: estudio?['lat']?.toString() ?? '');
    final lngCtrl =
        TextEditingController(text: estudio?['lng']?.toString() ?? '');

    String? categoria = estudio?['categoria']?.toString();
    bool activo = estudio?['activo'] as bool? ?? true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(estudio == null ? 'Nuevo estudio' : 'Editar estudio'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _categories.contains(categoria) ? categoria : null,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: _categories
                      .map(
                        (item) => DropdownMenuItem<String>(
                          value: item,
                          child: Text(item),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => categoria = value,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: barrioCtrl,
                  decoration: const InputDecoration(labelText: 'Barrio'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: direccionCtrl,
                  decoration: const InputDecoration(labelText: 'Dirección'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descripcionCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: fotoCtrl,
                  decoration: const InputDecoration(labelText: 'URL imagen'),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: () async {
                      final currentUserId =
                          Supabase.instance.client.auth.currentUser?.id ?? 'admin';
                      final url = await _mediaUploadService.pickAndUpload(
                        bucket: 'study-media',
                        folder: 'logos',
                        userId: currentUserId,
                      );
                      if (url != null) {
                        fotoCtrl.text = url;
                        setLocal(() {});
                      }
                    },
                    child: const Text('Subir imagen'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: instagramCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Instagram (opcional)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: whatsappCtrl,
                  decoration:
                      const InputDecoration(labelText: 'WhatsApp (opcional)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: webCtrl,
                  decoration: const InputDecoration(labelText: 'Web (opcional)'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: latCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration:
                            const InputDecoration(labelText: 'Latitud'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: lngCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration:
                            const InputDecoration(labelText: 'Longitud'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Podés pegarlas manualmente desde Google Maps o Apple Maps hasta que automaticemos la geocodificación.',
                    style: TextStyle(
                      color: AppColors.grey,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  value: activo,
                  onChanged: (value) => setLocal(() => activo = value),
                  title: const Text('Activo'),
                  contentPadding: EdgeInsets.zero,
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

    await _service.saveEstudio(
      estudioId: (estudio?['id'] as num?)?.toInt(),
      nombre: nombreCtrl.text,
      categoria: categoria ?? '',
      barrio: barrioCtrl.text,
      direccion: direccionCtrl.text,
      descripcion: descripcionCtrl.text,
      fotoUrl: fotoCtrl.text,
      instagram: instagramCtrl.text,
      whatsapp: whatsappCtrl.text,
      web: webCtrl.text,
      lat: double.tryParse(latCtrl.text.replaceAll(',', '.')),
      lng: double.tryParse(lngCtrl.text.replaceAll(',', '.')),
      activo: activo,
    );
    await _load();
  }

  Future<void> _openLinkAccessDialog(Map<String, dynamic> estudio) async {
    final emailCtrl = TextEditingController();
    final estudioId = (estudio['id'] as num).toInt();
    await showDialog<void>(
      context: context,
      builder: (ctx) => _StudioAccessDialog(
        estudioId: estudioId,
        estudioNombre: estudio['nombre']?.toString() ?? 'Sin nombre',
        service: _service,
        emailCtrl: emailCtrl,
        onChanged: _load,
      ),
    );
    emailCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.primary,
        label: const Text('Nuevo estudio'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Estudios',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Alta, edición y estado general de los estudios publicados.',
                  style: TextStyle(color: AppColors.grey),
                ),
                const SizedBox(height: 12),
                const _InfoBanner(
                  message:
                      'Cada estudio puede tener una o varias cuentas operativas. Primero creás el estudio y después sumás accesos por email.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Buscar estudios',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _load,
                    ),
                  ),
                  onSubmitted: (_) => _load(),
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
                      'No se pudieron cargar los estudios.\n$_error',
                      style: const TextStyle(color: AppColors.error),
                    ),
                  )
                else if (_studios.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Text(
                      'No hay estudios para mostrar todavía.',
                      style: TextStyle(color: AppColors.grey),
                    ),
                  )
                else
                  ..._studios.map(
                    (studio) => Container(
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
                                  studio['nombre']?.toString() ?? 'Sin nombre',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: (studio['activo'] == true
                                          ? AppColors.success
                                          : AppColors.grey)
                                      .withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  studio['activo'] == true
                                      ? 'Activo'
                                      : 'Inactivo',
                                  style: TextStyle(
                                    color: studio['activo'] == true
                                        ? AppColors.success
                                        : AppColors.grey,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            [
                              studio['categoria']?.toString() ?? '',
                              studio['barrio']?.toString() ?? '',
                            ].where((e) => e.isNotEmpty).join(' · '),
                            style: const TextStyle(color: AppColors.grey),
                          ),
                          const SizedBox(height: 12),
                          if ((studio['admin_count'] as num?) != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                '${(studio['admin_count'] as num).toInt()} acceso(s) vinculados',
                                style: const TextStyle(
                                  color: AppColors.grey,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          if ((studio['admin_emails']?.toString() ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                'Accesos: ${studio['admin_emails']}',
                                style: const TextStyle(
                                  color: AppColors.grey,
                                  fontSize: 13,
                                ),
                              ),
                            )
                          else
                            const Padding(
                              padding: EdgeInsets.only(bottom: 10),
                              child: Text(
                                'Todavía no tiene una cuenta operativa vinculada.',
                                style: TextStyle(
                                  color: AppColors.grey,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _openForm(studio),
                                  child: const Text('Editar estudio'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => _openLinkAccessDialog(studio),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: AppColors.black,
                                  ),
                                  child: const Text('Agregar acceso'),
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

class _InfoBanner extends StatelessWidget {
  final String message;

  const _InfoBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AppColors.black,
          height: 1.4,
        ),
      ),
    );
  }
}

class _StudioAccessDialog extends StatefulWidget {
  final int estudioId;
  final String estudioNombre;
  final AdminService service;
  final TextEditingController emailCtrl;
  final Future<void> Function() onChanged;

  const _StudioAccessDialog({
    required this.estudioId,
    required this.estudioNombre,
    required this.service,
    required this.emailCtrl,
    required this.onChanged,
  });

  @override
  State<_StudioAccessDialog> createState() => _StudioAccessDialogState();
}

class _StudioAccessDialogState extends State<_StudioAccessDialog> {
  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _accesses = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAccesses();
  }

  Future<void> _loadAccesses() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final accesses =
          await widget.service.listEstudioAccesses(estudioId: widget.estudioId);
      if (!mounted) return;
      setState(() {
        _accesses = accesses;
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

  Future<void> _addAccess() async {
    final email = widget.emailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.service.linkEstudioAccess(
        estudioId: widget.estudioId,
        email: email,
      );
      widget.emailCtrl.clear();
      await _loadAccesses();
      await widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Acceso agregado correctamente.'),
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
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeAccess(Map<String, dynamic> access) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar acceso'),
        content: Text(
          '¿Querés quitar el acceso de ${access['email'] ?? 'este usuario'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Quitar',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      await widget.service.removeEstudioAccess(
        estudioId: widget.estudioId,
        userId: access['id'].toString(),
      );
      await _loadAccesses();
      await widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Acceso quitado correctamente.'),
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
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar acceso al estudio'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Estudio: ${widget.estudioNombre}'),
              const SizedBox(height: 12),
              const Text(
                'Accesos actuales',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.black,
                ),
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error),
                )
              else if (_accesses.isEmpty)
                const Text(
                  'Todavía no hay mails asociados a este estudio.',
                  style: TextStyle(color: AppColors.grey),
                )
              else
                ..._accesses.map(
                  (access) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
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
                                access['email']?.toString() ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if ((access['nombre']?.toString() ?? '').isNotEmpty)
                                Text(
                                  access['nombre'].toString(),
                                  style: const TextStyle(
                                    color: AppColors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _saving ? null : () => _removeAccess(access),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppColors.error,
                          ),
                          tooltip: 'Quitar acceso',
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              const Text(
                'Sumar nuevo acceso',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.black,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ingresá el email de una cuenta ya registrada en Aura. Esa cuenta se suma como administradora de este estudio.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: widget.emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email de acceso del estudio',
                  hintText: 'estudio@correo.com',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        TextButton(
          onPressed: _saving ? null : _addAccess,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Agregar acceso'),
        ),
      ],
    );
  }
}
