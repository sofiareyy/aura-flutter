import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';
import '../../services/media_upload_service.dart';
import 'admin_pricing_screen.dart';

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

  Future<void> _openCreateWithAccountDialog() async {
    final nombreCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final direccionCtrl = TextEditingController();
    final barrioCtrl = TextEditingController();
    String? categoria;

    final formKey = GlobalKey<FormState>();
    bool obscurePassword = true;
    bool saving = false;
    Map<String, dynamic>? creado;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Crear estudio con cuenta'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'La cuenta se crea con email pre-verificado. '
                      'Anotá las credenciales al final.',
                      style: TextStyle(color: AppColors.grey, fontSize: 12),
                    ),
                  ),
                  TextFormField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del estudio',
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? 'Ingresá un nombre'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Email (puede ser inventado)',
                      helperText: 'No se manda mail de verificación',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    validator: (v) {
                      final email = v?.trim() ?? '';
                      final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                      if (!regex.hasMatch(email)) return 'Email inválido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: passwordCtrl,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Contraseña inicial',
                      helperText: 'Mínimo 6 caracteres',
                      suffixIcon: IconButton(
                        icon: Icon(obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setLocal(
                            () => obscurePassword = !obscurePassword),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 6)
                        ? 'Mínimo 6 caracteres'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: categoria,
                    decoration: const InputDecoration(labelText: 'Categoría'),
                    items: _categories
                        .map((c) =>
                            DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setLocal(() => categoria = v),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Elegí una categoría' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: direccionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Dirección (opcional)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: barrioCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Barrio (opcional)',
                    ),
                  ),
                ],
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
                      if (!(formKey.currentState?.validate() ?? false)) {
                        return;
                      }
                      setLocal(() => saving = true);
                      try {
                        final res =
                            await _service.crearEstudioConCuenta(
                          estudioNombre: nombreCtrl.text,
                          email: emailCtrl.text.trim(),
                          password: passwordCtrl.text,
                          categoria: categoria,
                          direccion: direccionCtrl.text.trim(),
                          barrio: barrioCtrl.text.trim(),
                        );
                        creado = res;
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx, true);
                        await _mostrarCredencialesCreadas(
                          email: res['email']?.toString() ?? '',
                          password: res['password']?.toString() ?? '',
                          nombre: nombreCtrl.text,
                        );
                      } catch (e) {
                        if (!ctx.mounted) return;
                        setLocal(() => saving = false);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(e
                                .toString()
                                .replaceFirst('Exception: ', '')),
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
                  : const Text('Crear'),
            ),
          ],
        ),
      ),
    );

    final nombreFinal = nombreCtrl.text;

    nombreCtrl.dispose();
    emailCtrl.dispose();
    passwordCtrl.dispose();
    direccionCtrl.dispose();
    barrioCtrl.dispose();

    if (ok == true) {
      if (mounted && creado != null) {
        final estudioId = (creado!['estudio_id'] as num?)?.toInt();
        if (estudioId != null) {
          await _mostrarPasoPricing(
            estudioId: estudioId,
            nombre: nombreFinal,
          );
        }
      }
      await _load();
    }
  }

  Future<void> _mostrarPasoPricing({
    required int estudioId,
    required String nombre,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Configuración de precios'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              nombre,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Podés configurarlo ahora o más tarde desde la ficha del estudio.',
              style: TextStyle(
                color: AppColors.grey,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Lo que vas a configurar:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '• Rango de precios por categoría (mín/máx en créditos)\n• Grilla de horarios pico y valle',
              style: TextStyle(
                color: AppColors.grey,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Configurar después'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AdminPricingScreen(
                    estudioId: estudioId,
                    estudioNombre: nombre,
                  ),
                ),
              );
            },
            child: const Text('Configurar ahora'),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarCredencialesCreadas({
    required String email,
    required String password,
    required String nombre,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 22),
            SizedBox(width: 8),
            Text('Estudio creado'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              nombre,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 12),
            const Text(
              'Pasá estas credenciales al estudio:',
              style: TextStyle(color: AppColors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _CredencialRow(label: 'Email', value: email),
            const SizedBox(height: 8),
            _CredencialRow(label: 'Contraseña', value: password),
            const SizedBox(height: 12),
            const Text(
              'Una vez cerrado este diálogo no vamos a volver a mostrarte la contraseña en claro.',
              style: TextStyle(color: AppColors.grey, fontSize: 11, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
  }

  void _abrirPricing(Map<String, dynamic> estudio) {
    final estudioId = (estudio['id'] as num?)?.toInt();
    if (estudioId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminPricingScreen(
          estudioId: estudioId,
          estudioNombre: estudio['nombre']?.toString(),
        ),
      ),
    );
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
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'estudio_con_cuenta',
            onPressed: _openCreateWithAccountDialog,
            backgroundColor: AppColors.black,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('Crear con cuenta'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'estudio_solo',
            onPressed: () => _openForm(),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_business_rounded, size: 18),
            label: const Text('Solo estudio'),
          ),
        ],
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
                                  child: const Text('Editar'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _abrirPricing(studio),
                                  child: const Text('Precios'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => _openLinkAccessDialog(studio),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: AppColors.black,
                                  ),
                                  child: const Text('Acceso'),
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

class _CredencialRow extends StatelessWidget {
  final String label;
  final String value;

  const _CredencialRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.grey,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                color: AppColors.black,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 16),
            tooltip: 'Copiar',
            color: AppColors.primary,
            visualDensity: VisualDensity.compact,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$label copiado al portapapeles'),
                  duration: const Duration(seconds: 2),
                  backgroundColor: AppColors.blackSoft,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
