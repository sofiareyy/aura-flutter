import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../models/estudio.dart';
import '../../services/admin_service.dart';
import '../../services/media_upload_service.dart';
import '../../widgets/categorias_checklist.dart';
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

  Future<void> _confirmarEliminarEstudio(Map<String, dynamic> studio) async {
    final nombre = studio['nombre']?.toString() ?? 'este estudio';
    final id = (studio['id'] as num?)?.toInt();
    if (id == null) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Eliminar $nombre?'),
        content: const Text(
          'Esta acción es permanente y no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.grey),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Sí, eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await _service.eliminarEstudio(id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Estudio "$nombre" eliminado'),
          backgroundColor: AppColors.black,
          behavior: SnackBarBehavior.floating,
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
    final comisionCtrl = TextEditingController(
      text: (estudio?['comision_aura'] as num?)?.toInt().toString() ?? '30',
    );
    final comisionWorkshopCtrl = TextEditingController(
      text: (estudio?['comision_workshop'] as num?)?.toInt().toString() ?? '15',
    );
    final cbuCtrl =
        TextEditingController(text: estudio?['cbu']?.toString() ?? '');

    // Tipo de precio por estudio (fijo / rango). Editable solo desde acá.
    String tipoPrecio = estudio?['tipo_precio']?.toString() ?? 'rango';
    if (tipoPrecio != 'fijo' && tipoPrecio != 'rango') tipoPrecio = 'rango';
    final creditosMinCtrl = TextEditingController(
      text: (estudio?['creditos_min'] as num?)?.toInt().toString() ?? '',
    );
    final creditosMaxCtrl = TextEditingController(
      text: (estudio?['creditos_max'] as num?)?.toInt().toString() ?? '',
    );
    // Precio original, para detectar si cambió al guardar y ofrecer propagarlo.
    final origTipoPrecio = tipoPrecio;
    final origMin = (estudio?['creditos_min'] as num?)?.toInt();
    final origMax = (estudio?['creditos_max'] as num?)?.toInt();

    // Un estudio puede tener varias categorias (Pilates + Barre + Yoga).
    final categorias = estudio == null
        ? <String>[]
        : Estudio.parseCategorias(Map<String, dynamic>.from(estudio));
    bool activo = estudio?['activo'] as bool? ?? true;
    DateTime? fechaInicioCobro = estudio?['fecha_inicio_cobro'] != null
        ? DateTime.tryParse(estudio!['fecha_inicio_cobro'].toString())
        : null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(estudio == null ? 'Nuevo estudio' : 'Editar estudio'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── SECCIÓN 1 — INFORMACIÓN BÁSICA ──────────────────────
                  const _FormSectionHeader('INFORMACIÓN BÁSICA'),
                  TextField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descripcionCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Descripción'),
                  ),
                  const SizedBox(height: 10),
                  CategoriasChecklist(
                    disponibles: _categories,
                    seleccionadas: categorias,
                    onToggle: (cat, marcada) => setLocal(() {
                      if (marcada) {
                        if (!categorias.contains(cat)) categorias.add(cat);
                      } else {
                        categorias.remove(cat);
                      }
                    }),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: barrioCtrl,
                    decoration: const InputDecoration(labelText: 'Barrio'),
                  ),
                  const SizedBox(height: 20),

                  // ── SECCIÓN 2 — UBICACIÓN Y CONTACTO ────────────────────
                  const _FormSectionHeader('UBICACIÓN Y CONTACTO'),
                  TextField(
                    controller: direccionCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Dirección exacta'),
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
                  const SizedBox(height: 6),
                  const Text(
                    'Podés pegarlas manualmente desde Google Maps o Apple Maps hasta que automaticemos la geocodificación.',
                    style: TextStyle(
                      color: AppColors.grey,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: instagramCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Instagram (sin @)',
                      hintText: 'auraestudio',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: whatsappCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'WhatsApp (con código de área)',
                      hintText: '+54 9 11 ...',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: webCtrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Link web del estudio (URL)',
                      hintText: 'https://...',
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Solo para mostrar información — no para comprar clases.',
                    style: TextStyle(
                      color: AppColors.grey,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── SECCIÓN 3 — FOTO ────────────────────────────────────
                  const _FormSectionHeader('FOTO'),
                  TextField(
                    controller: fotoCtrl,
                    decoration:
                        const InputDecoration(labelText: 'URL de imagen'),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: fotoCtrl.text.trim().isEmpty
                        ? Container(
                            height: 130,
                            width: double.infinity,
                            color: const Color(0xFFEDE7E1),
                            child: const Icon(
                              Icons.image_outlined,
                              color: AppColors.grey,
                              size: 44,
                            ),
                          )
                        : Image.network(
                            fotoCtrl.text.trim(),
                            height: 130,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              height: 130,
                              width: double.infinity,
                              color: const Color(0xFFEDE7E1),
                              child: const Icon(
                                Icons.broken_image_outlined,
                                color: AppColors.grey,
                                size: 44,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final currentUserId =
                            Supabase.instance.client.auth.currentUser?.id ??
                                'admin';
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
                      icon: const Icon(Icons.upload_outlined, size: 18),
                      label: const Text('Subir imagen'),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── SECCIÓN 4 — COBROS ──────────────────────────────────
                  const _FormSectionHeader('COBROS'),
                  TextField(
                    controller: cbuCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'CBU',
                      hintText: '22 dígitos',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: comisionCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Comisión clases (%)',
                      helperText: 'Porcentaje que retiene Aura. Default 30.',
                      suffixText: '%',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: comisionWorkshopCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Comisión workshops (%)',
                      helperText: 'Comisión de Aura para eventos. Default 15.',
                      suffixText: '%',
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: fechaInicioCobro ?? now,
                        firstDate: DateTime(now.year - 2),
                        lastDate: DateTime(now.year + 5),
                        helpText: 'Fecha inicio de cobro',
                      );
                      if (picked != null) {
                        setLocal(() => fechaInicioCobro = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Fecha inicio de cobro',
                        helperText:
                            'Antes de esta fecha Aura no cobra comisión (estudio recibe 100%).',
                        helperMaxLines: 2,
                        suffixIcon: fechaInicioCobro == null
                            ? const Icon(Icons.calendar_today, size: 18)
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () =>
                                    setLocal(() => fechaInicioCobro = null),
                              ),
                      ),
                      child: Text(
                        fechaInicioCobro == null
                            ? 'Sin fecha (cobra desde siempre)'
                            : '${fechaInicioCobro!.day.toString().padLeft(2, '0')}/'
                                '${fechaInicioCobro!.month.toString().padLeft(2, '0')}/'
                                '${fechaInicioCobro!.year}',
                        style: TextStyle(
                          color: fechaInicioCobro == null
                              ? AppColors.grey
                              : AppColors.black,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── SECCIÓN 5 — PRECIO POR CLASE ────────────────────────
                  const _FormSectionHeader('PRECIO POR CLASE'),
                  const Text(
                    'Cómo se cobran las clases del estudio. El estudio nunca '
                    'edita los créditos: en modo fijo todas las clases valen '
                    'el mismo valor; en modo rango marcás los horarios flojos '
                    'como valle (mínimo) y el resto cobra el máximo.',
                    style: TextStyle(
                      color: AppColors.grey,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3EEE8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _PrecioTipoButton(
                            label: 'Precio fijo',
                            selected: tipoPrecio == 'fijo',
                            onTap: () => setLocal(() => tipoPrecio = 'fijo'),
                          ),
                        ),
                        Expanded(
                          child: _PrecioTipoButton(
                            label: 'Rango',
                            selected: tipoPrecio == 'rango',
                            onTap: () => setLocal(() => tipoPrecio = 'rango'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (tipoPrecio == 'fijo')
                    TextField(
                      controller: creditosMinCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Créditos por clase',
                        helperText:
                            'Todas las clases del estudio valen esto.',
                        suffixText: 'cr',
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: creditosMinCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Mínimo',
                              suffixText: 'cr',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: creditosMaxCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Máximo',
                              suffixText: 'cr',
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (tipoPrecio == 'rango' && estudio?['id'] != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        // Se abre encima del diálogo para no perder lo que
                        // haya tipeado acá.
                        onPressed: () => _abrirPricing(estudio!),
                        icon: const Icon(Icons.grid_view_rounded, size: 18),
                        label: const Text('Marcar horarios pico y valle'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const Text(
                      'Sin horarios marcados, todas las clases cobran el '
                      'máximo. Marcá los flojos para que cobren el mínimo.',
                      style: TextStyle(
                        color: AppColors.grey,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // ── SECCIÓN 6 — ESTADO ──────────────────────────────────
                  const _FormSectionHeader('ESTADO'),
                  SwitchListTile(
                    value: activo,
                    onChanged: (value) => setLocal(() => activo = value),
                    title: Text(activo ? 'Activo' : 'Inactivo'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
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
      categorias: categorias,
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
      comision: int.tryParse(comisionCtrl.text.trim()),
      comisionWorkshop: int.tryParse(comisionWorkshopCtrl.text.trim()),
      cbu: cbuCtrl.text,
      tipoPrecio: tipoPrecio,
      creditosMin: int.tryParse(creditosMinCtrl.text.trim()),
      // En precio fijo, min == max == el valor único.
      creditosMax: tipoPrecio == 'fijo'
          ? int.tryParse(creditosMinCtrl.text.trim())
          : int.tryParse(creditosMaxCtrl.text.trim()),
      fechaInicioCobro: fechaInicioCobro == null
          ? null
          : '${fechaInicioCobro!.year}-'
              '${fechaInicioCobro!.month.toString().padLeft(2, '0')}-'
              '${fechaInicioCobro!.day.toString().padLeft(2, '0')}',
    );

    // Si cambió el precio de un estudio existente, ofrecer propagarlo a las
    // clases futuras. El valor base es el mínimo (= valor único en precio fijo).
    final estudioId = (estudio?['id'] as num?)?.toInt();
    final nuevoMin = int.tryParse(creditosMinCtrl.text.trim());
    final nuevoMax = tipoPrecio == 'fijo'
        ? nuevoMin
        : int.tryParse(creditosMaxCtrl.text.trim());
    final precioCambio = tipoPrecio != origTipoPrecio ||
        nuevoMin != origMin ||
        nuevoMax != origMax;
    if (estudioId != null && precioCambio && nuevoMin != null) {
      await _ofrecerActualizarClasesFuturas(estudioId);
    }

    await _load();
  }

  /// Pregunta si propagar el nuevo precio a las clases del estudio. El precio
  /// no se pasa: lo recalcula la base según el modo (fijo o rango pico/valle).
  Future<void> _ofrecerActualizarClasesFuturas(int estudioId) async {
    int cantidad;
    try {
      cantidad = await _service.contarClasesFuturas(estudioId);
    } catch (_) {
      return;
    }
    if (cantidad <= 0 || !mounted) return;

    final actualizar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Actualizar clases con el nuevo precio'),
        content: Text(
          'Hay $cantidad clase${cantidad == 1 ? '' : 's'} '
          'futura${cantidad == 1 ? '' : 's'}. ¿Recalcular los créditos de las '
          'clases del estudio con esta configuración?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.grey),
            child: const Text('Solo guardar la config'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Sí, actualizar todo'),
          ),
        ],
      ),
    );
    if (actualizar != true) return;

    try {
      final n = await _service.recalcularPreciosEstudio(
        estudioId: estudioId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$n clase${n == 1 ? '' : 's'} '
              'actualizada${n == 1 ? '' : 's'} con el nuevo precio.'),
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
    }
  }

  Future<void> _openCreateWithAccountDialog() async {
    final nombreCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final direccionCtrl = TextEditingController();
    final barrioCtrl = TextEditingController();
    final categorias = <String>[];

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
                  CategoriasChecklist(
                    disponibles: _categories,
                    seleccionadas: categorias,
                    onToggle: (cat, marcada) => setLocal(() {
                      if (marcada) {
                        if (!categorias.contains(cat)) categorias.add(cat);
                      } else {
                        categorias.remove(cat);
                      }
                    }),
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
                      // El checklist no vive en el Form, se valida aparte.
                      if (categorias.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Elegí al menos una categoría'),
                          ),
                        );
                        return;
                      }
                      setLocal(() => saving = true);
                      try {
                        final res =
                            await _service.crearEstudioConCuenta(
                          estudioNombre: nombreCtrl.text,
                          email: emailCtrl.text.trim(),
                          password: passwordCtrl.text,
                          categorias: categorias,
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
    final estudioId = (estudio['id'] as num).toInt();
    await showDialog<void>(
      context: context,
      builder: (ctx) => _StudioAccessDialog(
        estudioId: estudioId,
        estudioNombre: estudio['nombre']?.toString() ?? 'Sin nombre',
        service: _service,
        onChanged: _load,
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
          'Estudios',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PopupMenuButton<String>(
              tooltip: 'Agregar estudio',
              icon: const Icon(Icons.add_rounded, color: AppColors.primary),
              onSelected: (value) {
                if (value == 'con_cuenta') {
                  _openCreateWithAccountDialog();
                } else if (value == 'solo') {
                  _openForm();
                }
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem<String>(
                  value: 'con_cuenta',
                  child: Row(
                    children: [
                      Icon(Icons.person_add_alt_1_rounded,
                          size: 20, color: AppColors.black),
                      SizedBox(width: 10),
                      Text('Crear con cuenta'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'solo',
                  child: Row(
                    children: [
                      Icon(Icons.add_business_rounded,
                          size: 20, color: AppColors.primary),
                      SizedBox(width: 10),
                      Text('Solo estudio'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
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
                              PopupMenuButton<String>(
                                icon: const Icon(
                                  Icons.more_vert,
                                  color: AppColors.grey,
                                ),
                                onSelected: (value) {
                                  if (value == 'eliminar') {
                                    _confirmarEliminarEstudio(studio);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem<String>(
                                    value: 'eliminar',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.delete_outline,
                                          color: AppColors.error,
                                          size: 20,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Eliminar estudio',
                                          style:
                                              TextStyle(color: AppColors.error),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            [
                              Estudio.parseCategorias(studio).join(', '),
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

/// Encabezado de sección del formulario de estudio: título naranja + separador.
class _FormSectionHeader extends StatelessWidget {
  final String title;

  const _FormSectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        const Divider(height: 1, color: Color(0xFFEDE7E1)),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Botón de un segmented control (Precio fijo / Rango) en el form de estudio.
class _PrecioTipoButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PrecioTipoButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.white : AppColors.grey,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
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

/// Panel de gestión de accesos de un estudio, organizado en dos secciones:
/// Administradores (rol admin_estudio / estudio) y Profes (rol profe). Permite
/// agregar admin, agregar profe, cambiar el rol de cada uno y eliminarlos.
class _StudioAccessDialog extends StatefulWidget {
  final int estudioId;
  final String estudioNombre;
  final AdminService service;
  final Future<void> Function() onChanged;

  const _StudioAccessDialog({
    required this.estudioId,
    required this.estudioNombre,
    required this.service,
    required this.onChanged,
  });

  @override
  State<_StudioAccessDialog> createState() => _StudioAccessDialogState();
}

class _StudioAccessDialogState extends State<_StudioAccessDialog> {
  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _members = [];
  String? _error;

  List<Map<String, dynamic>> get _admins =>
      _members.where((m) => m['rol']?.toString() != 'profe').toList();

  List<Map<String, dynamic>> get _profes =>
      _members.where((m) => m['rol']?.toString() == 'profe').toList();

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final members =
          await widget.service.listEstudioMembers(estudioId: widget.estudioId);
      if (!mounted) return;
      setState(() {
        _members = members;
        _loading = false;
      });
    } catch (e, st) {
      // Error exacto en consola para diagnóstico.
      debugPrint('[accesos] error listando miembros del estudio '
          '${widget.estudioId}: $e');
      debugPrintStack(stackTrace: st);
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

  Future<String?> _promptEmail({
    required String title,
    required String helper,
  }) async {
    final emailCtrl = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              helper,
              style: const TextStyle(color: AppColors.grey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'persona@correo.com',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, emailCtrl.text.trim()),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    emailCtrl.dispose();
    return (email == null || email.isEmpty) ? null : email;
  }

  Future<void> _addAdmin() async {
    final email = await _promptEmail(
      title: 'Agregar admin',
      helper:
          'El admin ve todo el panel (clases, cobros, configuración). Tiene '
          'que tener una cuenta Aura ya registrada.',
    );
    if (email == null) return;
    setState(() => _saving = true);
    try {
      await widget.service
          .linkEstudioAccess(estudioId: widget.estudioId, email: email);
      await _loadMembers();
      await widget.onChanged();
      _snack('Admin agregado correctamente.');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addProfe() async {
    final email = await _promptEmail(
      title: 'Agregar profe',
      helper:
          'La profe ve solo Mis Clases y Asistencia (sin cobros ni '
          'configuración). Tiene que tener una cuenta Aura ya registrada.',
    );
    if (email == null) return;
    setState(() => _saving = true);
    try {
      await widget.service
          .addEstudioProfe(estudioId: widget.estudioId, email: email);
      await _loadMembers();
      await widget.onChanged();
      _snack('Profe agregada correctamente.');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cambiarRol(Map<String, dynamic> member, String nuevoRol) async {
    final label = nuevoRol == 'profe' ? 'profe' : 'administrador';
    setState(() => _saving = true);
    try {
      await widget.service.setEstudioAccessRol(
        estudioId: widget.estudioId,
        userId: member['id'].toString(),
        rol: nuevoRol,
      );
      await _loadMembers();
      await widget.onChanged();
      _snack('Ahora es $label.');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeMember(Map<String, dynamic> member) async {
    final email = member['email']?.toString() ?? 'este usuario';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar acceso'),
        content: Text('¿Querés quitar el acceso de $email?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      await widget.service.removeEstudioAccess(
        estudioId: widget.estudioId,
        userId: member['id'].toString(),
      );
      await _loadMembers();
      await widget.onChanged();
      _snack('Acceso quitado correctamente.');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Accesos · ${widget.estudioNombre}'),
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
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AccessSection(
                          title: 'ADMINISTRADORES DEL ESTUDIO',
                          subtitle:
                              'Acceso completo: clases, cobros y configuración.',
                          members: _admins,
                          emptyLabel: 'Todavía no hay administradores.',
                          addLabel: 'Agregar admin',
                          onAdd: _saving ? null : _addAdmin,
                          saving: _saving,
                          // A un admin se lo puede convertir en profe.
                          otherRoleLabel: 'Convertir en profe',
                          onChangeRole: (m) => _cambiarRol(m, 'profe'),
                          onRemove: _removeMember,
                        ),
                        const SizedBox(height: 20),
                        _AccessSection(
                          title: 'PROFES DEL ESTUDIO',
                          subtitle:
                              'Vista limitada: solo Mis Clases y Asistencia.',
                          members: _profes,
                          emptyLabel: 'Todavía no hay profes.',
                          addLabel: 'Agregar profe',
                          onAdd: _saving ? null : _addProfe,
                          saving: _saving,
                          // A una profe se la puede promover a admin.
                          otherRoleLabel: 'Convertir en admin',
                          onChangeRole: (m) => _cambiarRol(m, 'admin_estudio'),
                          onRemove: _removeMember,
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
      ],
    );
  }
}

/// Una sección (Admins o Profes) del panel de accesos: encabezado, lista de
/// miembros con menú de acciones (cambiar rol / eliminar) y botón de agregar.
class _AccessSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> members;
  final String emptyLabel;
  final String addLabel;
  final VoidCallback? onAdd;
  final bool saving;
  final String otherRoleLabel;
  final void Function(Map<String, dynamic>) onChangeRole;
  final void Function(Map<String, dynamic>) onRemove;

  const _AccessSection({
    required this.title,
    required this.subtitle,
    required this.members,
    required this.emptyLabel,
    required this.addLabel,
    required this.onAdd,
    required this.saving,
    required this.otherRoleLabel,
    required this.onChangeRole,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.grey,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(color: AppColors.grey, fontSize: 12),
        ),
        const SizedBox(height: 10),
        if (members.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              emptyLabel,
              style: const TextStyle(color: AppColors.grey),
            ),
          )
        else
          ...members.map(
            (member) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                          member['email']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if ((member['nombre']?.toString() ?? '').isNotEmpty)
                          Text(
                            member['nombre'].toString(),
                            style: const TextStyle(
                              color: AppColors.grey,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    enabled: !saving,
                    icon: const Icon(Icons.more_vert, color: AppColors.grey),
                    onSelected: (value) {
                      if (value == 'rol') {
                        onChangeRole(member);
                      } else if (value == 'eliminar') {
                        onRemove(member);
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem<String>(
                        value: 'rol',
                        child: Row(
                          children: [
                            const Icon(Icons.swap_horiz_rounded,
                                size: 20, color: AppColors.grey),
                            const SizedBox(width: 8),
                            Text(otherRoleLabel),
                          ],
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'eliminar',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline,
                                size: 20, color: AppColors.error),
                            SizedBox(width: 8),
                            Text('Eliminar acceso',
                                style: TextStyle(color: AppColors.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(addLabel),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
          ),
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
