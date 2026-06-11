import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../services/aviso_alumnos_service.dart';
import '../../services/clases_service.dart';
import '../../utils/pricing.dart';
import '../../services/estudio_admin_service.dart';
import '../../services/media_upload_service.dart';
import '../../services/notificaciones_service.dart';
import '../../services/reservas_service.dart';
import '../../services/admin_service.dart';

String _toSupaDate(DateTime dt) {
  return '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:00';
}

class MisClasesScreen extends StatefulWidget {
  const MisClasesScreen({super.key});
  @override
  State<MisClasesScreen> createState() => _MisClasesScreenState();
}

class _MisClasesScreenState extends State<MisClasesScreen> {
  final _service = EstudioAdminService();
  final _reservasService = ReservasService();
  final _clasesService = ClasesService();
  final _mediaUploadService = MediaUploadService();
  final _adminService = AdminService();
  final _avisoService = AvisoAlumnosService();
  List<Map<String, dynamic>> _clases = [], _horarios = [];
  List<String> _categorias = [];
  List<Map<String, dynamic>> _reservas = [];
  bool _loading = true, _tablaOk = true, _studio = false, _showFixed = true, _publishingWeek = false, _togglingFixed = false;
  bool _estudiosDefinenCreditos = true;
  Map<String, dynamic>? _estudio;
  String? _error;
  String? _estudioNombre;
  DateTime _selectedDay = DateTime.now(), _weekAnchor = DateTime.now(), _monthAnchor = DateTime.now();

  Future<String?> _subirImagenClase() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return null;
    return _mediaUploadService.pickAndUpload(
      bucket: 'study-media',
      folder: 'class-media',
      userId: userId,
    );
  }

  List<String> _parseGaleria(String raw) => raw
      .split(RegExp(r'[\n,]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  Future<List<String>> _loadCategoriasDisponibles([String? current]) async {
    final categoriasAdmin = await _adminService.listStudyCategories();
    final categorias = <String>{
      ..._categorias.where((item) => item.trim().isNotEmpty),
      ...categoriasAdmin.where((item) => item.trim().isNotEmpty),
      if (current != null && current.trim().isNotEmpty) current.trim(),
    }.toList()
      ..sort();
    return categorias;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final studio = GoRouterState.of(context).matchedLocation.startsWith('/estudio');
    if (studio != _studio || _loading) {
      _studio = studio;
      _weekAnchor = _weekStart(DateTime.now());
      _monthAnchor = DateTime(DateTime.now().year, DateTime.now().month, 1);
      _load();
    }
  }

  Future<void> _load() async => _studio ? _loadStudio() : _loadUser();

  Future<void> _toggleFixed(int id, bool activo) async {
    if (_togglingFixed) return;
    setState(() => _togglingFixed = true);
    try {
      final updated = await _service.actualizarHorarioFijo(id, {'activo': activo});
      if (!mounted) return;
      setState(() {
        _horarios = _horarios.map((h) => ((h['id'] as num?)?.toInt() == (updated['id'] as num?)?.toInt()) ? updated : h).toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo actualizar: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _togglingFixed = false);
    }
  }

  Future<void> _showClaseSheet(Map<String, dynamic> clase) async {
    final claseId = (clase['id'] as num?)?.toInt();
    if (claseId == null) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ClaseDetalleSheet(
        clase: clase,
        onEdit: () async {
          Navigator.pop(context);
          await _editClaseDialog(clase);
        },
        onCancel: () async {
          Navigator.pop(context);
          await _confirmarCancelacion(clase);
        },
        onAvisar: () async {
          Navigator.pop(context);
          await _mostrarAvisoSheet(clase);
        },
      ),
    );
  }

  Future<void> _mostrarAvisoSheet(Map<String, dynamic> clase) async {
    final claseId = (clase['id'] as num?)?.toInt();
    if (claseId == null) return;
    final claseNombre = clase['nombre']?.toString() ?? 'Clase';
    final estudioNombre = _estudioNombre ?? 'Aura';
    final cantAlumnos = await _avisoService.contarAlumnosReservados(claseId);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _AvisoSheet(
        claseId: claseId,
        claseNombre: claseNombre,
        cantidadAlumnos: cantAlumnos,
        estudioNombre: estudioNombre,
        onEnviar: (mensaje, tipo) async {
          await _avisoService.enviarAviso(
            claseId: claseId,
            mensaje: mensaje,
            tipo: tipo,
            tituloEstudio: estudioNombre,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✓ Aviso enviado a $cantAlumnos alumnos'),
                backgroundColor: const Color(0xFF1A1A1A),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _editClaseDialog(Map<String, dynamic> clase) async {
    final claseId = (clase['id'] as num?)?.toInt();
    if (claseId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final categoriasDisponibles = await _loadCategoriasDisponibles(
      clase['categoria']?.toString(),
    );
    final n = TextEditingController(text: clase['nombre']?.toString() ?? '');
    final ins = TextEditingController(text: clase['instructor']?.toString() ?? '');
    final insDesc = TextEditingController(
      text: clase['instructor_descripcion']?.toString() ?? '',
    );
    final incluye = TextEditingController(
      text: clase['incluye']?.toString() ?? '',
    );
    final imagenUrl = TextEditingController(
      text: clase['imagen_url']?.toString() ?? '',
    );
    final galeria = TextEditingController(
      text: ((clase['galeria_urls'] as List?) ?? const [])
          .map((item) => item.toString())
          .join('\n'),
    );
    final cupos = TextEditingController(text: ((clase['lugares_total'] as num?)?.toInt() ?? 12).toString());
    final cred = TextEditingController(text: ((clase['creditos'] as num?)?.toInt() ?? 10).toString());
    int cierreReserva = (clase['reserva_cierre_minutos'] as num?)?.toInt() ?? 0;
    String? cat = clase['categoria']?.toString();
    final fechaOrig = DateTime.tryParse(clase['fecha']?.toString() ?? '');
    DateTime fechaSel = fechaOrig ?? DateTime.now();
    TimeOfDay horaSel = TimeOfDay(hour: fechaSel.hour, minute: fechaSel.minute);
    if (!mounted) return;
    bool showExtraFields = false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final mq = MediaQuery.of(ctx);
        return AnimatedPadding(
          padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
          duration: const Duration(milliseconds: 100),
          child: FractionallySizedBox(
            heightFactor: 0.92,
            child: Container(
              decoration: const BoxDecoration(
                color: _kFieldFill,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1CAC3),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Editar clase',
                            style: TextStyle(
                              color: Color(0xFF1A1A1A),
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          icon: const Icon(Icons.close_rounded,
                              color: Color(0xFF1A1A1A)),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Column(
                        children: [
                          // Card 1: Información básica
                          _SectionCard(
                            title: 'Información básica',
                            children: [
                              _AuraTextField(
                                controller: n,
                                label: 'Nombre de la clase',
                                hint: 'Yoga restaurativo',
                              ),
                              const SizedBox(height: 12),
                              _AuraTextField(
                                controller: ins,
                                label: 'Instructor/a',
                                hint: 'Florencia Pérez',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Card 2: Horario (fecha + hora)
                          _SectionCard(
                            title: 'Horario',
                            children: [
                              _AuraTapField(
                                label: 'Fecha',
                                value: DateFormat('EEE d MMM yyyy', 'es')
                                    .format(fechaSel),
                                icon: Icons.calendar_today_rounded,
                                onTap: () async {
                                  final d = await showDatePicker(
                                    context: ctx,
                                    initialDate: fechaSel,
                                    firstDate: DateTime.now()
                                        .subtract(const Duration(days: 30)),
                                    lastDate: DateTime.now()
                                        .add(const Duration(days: 90)),
                                  );
                                  if (d != null) {
                                    setD(() => fechaSel = DateTime(
                                          d.year,
                                          d.month,
                                          d.day,
                                          horaSel.hour,
                                          horaSel.minute,
                                        ));
                                  }
                                },
                              ),
                              const SizedBox(height: 12),
                              _AuraTapField(
                                label: 'Hora',
                                value: DateFormat('HH:mm').format(DateTime(
                                    2024,
                                    1,
                                    1,
                                    horaSel.hour,
                                    horaSel.minute)),
                                icon: Icons.schedule_rounded,
                                onTap: () async {
                                  final t = await showTimePicker(
                                      context: ctx, initialTime: horaSel);
                                  if (t != null) {
                                    setD(() {
                                      horaSel = t;
                                      fechaSel = DateTime(
                                        fechaSel.year,
                                        fechaSel.month,
                                        fechaSel.day,
                                        t.hour,
                                        t.minute,
                                      );
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Card 3: Capacidad
                          _SectionCard(
                            title: 'Capacidad',
                            children: [
                              _AuraTextField(
                                controller: cupos,
                                label: 'Cupos disponibles',
                                hint: '12',
                                keyboardType: TextInputType.number,
                              ),
                              const SizedBox(height: 12),
                              _AuraDropdown<int>(
                                label: 'Cierre de reservas',
                                value: cierreReserva,
                                items: _bookingCutoffOptions
                                    .map((v) => DropdownMenuItem(
                                          value: v,
                                          child:
                                              Text(_bookingCutoffLabel(v)),
                                        ))
                                    .toList(),
                                onChanged: (v) =>
                                    setD(() => cierreReserva = v ?? 0),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Card 4: Categoría y precio
                          _SectionCard(
                            title: 'Categoría y precio',
                            children: [
                              if (categoriasDisponibles.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF1E8),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'Primero creá categorías desde Admin Aura > Config.',
                                    style: TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 13),
                                  ),
                                )
                              else
                                _AuraDropdown<String>(
                                  label: 'Categoría',
                                  value: categoriasDisponibles.contains(cat)
                                      ? cat
                                      : null,
                                  items: categoriasDisponibles
                                      .map((v) => DropdownMenuItem(
                                            value: v,
                                            child: Text(v),
                                          ))
                                      .toList(),
                                  onChanged: (v) => setD(() => cat = v),
                                ),
                              const SizedBox(height: 12),
                              _PricingPreview(
                                estudio: _estudio,
                                hora: '${horaSel.hour.toString().padLeft(2, '0')}:${horaSel.minute.toString().padLeft(2, '0')}',
                                dia: fechaSel.weekday,
                                categoria: cat,
                                onComputed: (creditos) {
                                  if (cred.text != creditos.toString()) {
                                    cred.text = creditos.toString();
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Card 5: Detalles adicionales (colapsable)
                          _CollapsibleSectionCard(
                            title: 'Detalles adicionales',
                            expanded: showExtraFields,
                            onToggle: () => setD(
                                () => showExtraFields = !showExtraFields),
                            children: [
                              _AuraTextField(
                                controller: insDesc,
                                label: 'Descripción del instructor/a',
                                hint:
                                    'Profesora certificada con 10 años de experiencia',
                                maxLines: 2,
                              ),
                              const SizedBox(height: 12),
                              _AuraTextField(
                                controller: incluye,
                                label: 'Qué incluye la clase',
                                hint: 'Mat, agua, vestuario',
                                maxLines: 2,
                              ),
                              const SizedBox(height: 12),
                              _AuraTextField(
                                controller: imagenUrl,
                                label: 'Imagen principal (URL)',
                                hint: 'https://...',
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final uploaded =
                                        await _subirImagenClase();
                                    if (uploaded != null) {
                                      imagenUrl.text = uploaded;
                                      setD(() {});
                                    }
                                  },
                                  icon: const Icon(Icons.image_outlined),
                                  label:
                                      const Text('Subir imagen principal'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _AuraTextField(
                                controller: galeria,
                                label: 'Galería de fotos',
                                hint: 'Una URL por línea',
                                maxLines: 3,
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final uploaded =
                                        await _subirImagenClase();
                                    if (uploaded != null) {
                                      galeria.text =
                                          galeria.text.trim().isEmpty
                                              ? uploaded
                                              : '${galeria.text.trim()}\n$uploaded';
                                      setD(() {});
                                    }
                                  },
                                  icon: const Icon(
                                      Icons.photo_library_outlined),
                                  label: const Text(
                                      'Agregar imagen a galería'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        16, 12, 16, mq.padding.bottom + 32),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('Guardar cambios'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
    if (ok != true || !mounted) { n.dispose(); ins.dispose(); insDesc.dispose(); incluye.dispose(); imagenUrl.dispose(); galeria.dispose(); cupos.dispose(); cred.dispose(); return; }
    try {
      // 0 es valido: "clase visible pero no reservable". Si el usuario
      // explicitamente puso 0, lo aceptamos. Solo caemos al default (12)
      // cuando el campo quedo vacio o con texto invalido.
      final cuposText = cupos.text.trim();
      final lugaresTotal = cuposText.isEmpty
          ? 12
          : (int.tryParse(cuposText) ?? 12);
      final categoriaTrim = cat?.trim() ?? '';
      final payload = {
        'nombre': n.text.trim().isEmpty ? clase['nombre'] : n.text.trim(),
        'instructor': ins.text.trim().isEmpty ? null : ins.text.trim(),
        'instructor_descripcion':
            insDesc.text.trim().isEmpty ? null : insDesc.text.trim(),
        'incluye': incluye.text.trim().isEmpty ? null : incluye.text.trim(),
        'imagen_url':
            imagenUrl.text.trim().isEmpty ? null : imagenUrl.text.trim(),
        'galeria_urls': _parseGaleria(galeria.text),
        'fecha': _toSupaDate(fechaSel),
        'lugares_total': lugaresTotal,
        // Si la clase pasa a 0 cupos, sincronizamos lugares_disponibles para
        // que el flujo de reservar la rechace (sino quedaba el viejo valor
        // de disponibles y la clase aparecia reservable).
        if (lugaresTotal == 0) 'lugares_disponibles': 0,
        'creditos': int.tryParse(cred.text.trim()) ?? 10,
        // Solo incluir categoria si tiene valor — evita pisar con null si la
        // columna tiene constraint NOT NULL o si el dropdown quedo vacio.
        if (categoriaTrim.isNotEmpty) 'categoria': categoriaTrim,
        'reserva_cierre_minutos': cierreReserva,
      };
      await _service.editarClase(claseId, payload);
      await _loadStudio();
      NotificacionesService.instance.scheduleListaAsistentesReminder(
        claseId: claseId,
        claseNombre: payload['nombre']?.toString() ?? '',
        fechaClase: fechaSel,
        cantidadReservas: 0,
        estudioNombre: '',
      ).ignore();
      messenger.showSnackBar(const SnackBar(content: Text('Clase actualizada')));
    } catch (e) {
      final msg = e is PostgrestException
          ? (e.message.toLowerCase().contains('row-level security')
              ? 'No tenés permisos para editar esta clase. Contactá soporte.'
              : 'No se pudo guardar: ${e.message}')
          : 'No se pudo guardar: ${e.toString()}';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      n.dispose(); ins.dispose(); insDesc.dispose(); incluye.dispose(); imagenUrl.dispose(); galeria.dispose(); cupos.dispose(); cred.dispose();
    }
  }

  Future<void> _confirmarCancelacion(Map<String, dynamic> clase) async {
    final claseId = (clase['id'] as num?)?.toInt();
    if (claseId == null) return;
    final nombre = clase['nombre']?.toString() ?? 'esta clase';

    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20, 20, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8E5E0),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Cancelar "$nombre"',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.black,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Todos los alumnos que reservaron recibirán sus créditos de vuelta automáticamente.',
              style: TextStyle(
                color: Color(0xFF8F877F),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Cancelar clase',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8F877F),
                  side: const BorderSide(color: Color(0xFFE8E5E0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Volver',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) return;
    try {
      final devueltos = await _reservasService.cancelarClaseConDevolucion(claseId, nombre);
      await _loadStudio();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            devueltos > 0
                ? 'Clase cancelada. Se devolvieron créditos a $devueltos alumno${devueltos != 1 ? 's' : ''}.'
                : 'Clase cancelada.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cancelar: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _loadUser() async {
    final results = await Future.wait([
      _reservasService.getReservasUsuario(),
      // Trae las clases del proximo mes para que el calendario muestre
      // todas las opciones por dia (no solo lo que el user ya reservo).
      _clasesService.getProximasClases(limit: 200),
    ]);
    final reservasList = List<Map<String, dynamic>>.from(results[0] as List);
    final clasesList = List<Map<String, dynamic>>.from(results[1] as List);
    if (!mounted) return;
    setState(() {
      _clases = clasesList;
      _reservas = reservasList;
      _loading = false;
    });
  }

  Future<void> _loadStudio() async {
    try {
      // Auto-mantener 3 meses (13 semanas) de clases concretas a partir de
      // los horarios fijos activos. La funcion es idempotente: salta las que
      // ya existen. Asi el "horario fijo activo" siempre coincide con clases
      // visibles para los usuarios, sin que el estudio tenga que apretar
      // "Generar 3 meses" manualmente.
      await _service.generarProximasSemanasDesdeHorarios(weeks: 13);
    } catch (e) {
      if (mounted) {
        setState(() {
          _tablaOk = false;
          _error = 'Error al generar clases: ${e.toString()}';
        });
      }
    }

    try {
      final now = DateTime.now().toUtc().subtract(const Duration(hours: 3));
      final results = await Future.wait([
        _service.getClasesDeEstudio(
          from: now.subtract(const Duration(days: 1)),
          to: now.add(const Duration(days: 14)),
          limit: 200,
        ),
        _service.getHorariosFijosDeEstudio(),
        _adminService.listStudyCategories(),
        _adminService.getConfigGlobal('estudios_definen_creditos'),
        _service.getCurrentStudio(),
      ]);
      final clases = results[0] as List<Map<String, dynamic>>;
      final horarios = results[1] as List<Map<String, dynamic>>;
      final categoriasAdmin = results[2] as List<String>;
      final configCreditos = results[3] as String?;
      final estudio = results[4] as Map<String, dynamic>?;
      final categorias = <String>{
        ...categoriasAdmin.where((item) => item.trim().isNotEmpty),
        ...horarios
            .map((item) => item['categoria']?.toString() ?? '')
            .where((item) => item.trim().isNotEmpty),
        ...clases
            .map((item) => item['categoria']?.toString() ?? '')
            .where((item) => item.trim().isNotEmpty),
      }.toList()
        ..sort();
      if (!mounted) return;
      setState(() {
        _clases = clases;
        _horarios = horarios;
        _categorias = categorias;
        _estudiosDefinenCreditos = configCreditos == 'true';
        _estudio = estudio;
        _estudioNombre = estudio?['nombre']?.toString();
        _loading = false;
        _tablaOk = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _tablaOk = false;
        _error = e.toString();
      });
    }
  }


  Future<void> _openForm([Map<String, dynamic>? item]) async {
    final edit = item != null;
    final messenger = ScaffoldMessenger.of(context);
    final categoriasDisponibles = await _loadCategoriasDisponibles(
      item?['categoria']?.toString(),
    );
    final n = TextEditingController(text: item?['nombre']?.toString() ?? '');
    final i = TextEditingController(text: item?['instructor']?.toString() ?? '');
    final iDesc = TextEditingController(
      text: item?['instructor_descripcion']?.toString() ?? '',
    );
    final incluye = TextEditingController(
      text: item?['incluye']?.toString() ?? '',
    );
    final imagenUrl = TextEditingController(
      text: item?['imagen_url']?.toString() ?? '',
    );
    final galeria = TextEditingController(
      text: ((item?['galeria_urls'] as List?) ?? const [])
          .map((entry) => entry.toString())
          .join('\n'),
    );
    final s = TextEditingController(text: item?['sala']?.toString() ?? '');
    final c = TextEditingController(text: ((item?['lugares_total'] as num?)?.toInt() ?? 12).toString());
    final cr = TextEditingController(text: ((item?['creditos'] as num?)?.toInt() ?? 10).toString());
    int cierreReserva = (item?['reserva_cierre_minutos'] as num?)?.toInt() ?? 0;
    int d = (item?['dia_semana'] as num?)?.toInt() ?? 1;
    // Clase individual (solo al crear): fecha concreta del evento único.
    final nowLocal = DateTime.now();
    DateTime fecha = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final hh = (item?['hora_inicio']?.toString() ?? '08:00').split(':');
    TimeOfDay t = TimeOfDay(hour: int.tryParse(hh.first) ?? 8, minute: int.tryParse(hh.length > 1 ? hh[1] : '0') ?? 0);
    int dur = (item?['duracion_min'] as num?)?.toInt() ?? 60;
    String? cat = item?['categoria']?.toString();
    if (!mounted) return;
    bool showExtraFields = false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final mq = MediaQuery.of(ctx);
        return AnimatedPadding(
          padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
          duration: const Duration(milliseconds: 100),
          child: FractionallySizedBox(
            heightFactor: 0.92,
            child: Container(
              decoration: const BoxDecoration(
                color: _kFieldFill,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1CAC3),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            edit ? 'Editar clase' : 'Nueva clase',
                            style: const TextStyle(
                              color: Color(0xFF1A1A1A),
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          icon: const Icon(Icons.close_rounded,
                              color: Color(0xFF1A1A1A)),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Column(
                        children: [
                          if (!edit) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF1E8),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Esta es una clase individual: un evento único en la fecha que elijas. No se repite. Si querés clases que se repitan todas las semanas, usá "Crear grilla".',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          // Card 1: Información básica
                          _SectionCard(
                            title: 'Información básica',
                            children: [
                              _AuraTextField(
                                controller: n,
                                label: 'Nombre de la clase',
                                hint: 'Yoga restaurativo',
                              ),
                              const SizedBox(height: 12),
                              _AuraTextField(
                                controller: i,
                                label: 'Instructor/a',
                                hint: 'Florencia Pérez',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Card 2: Horario
                          _SectionCard(
                            title: 'Horario',
                            children: [
                              if (edit)
                                _AuraDropdown<int>(
                                  label: 'Día',
                                  value: d,
                                  items: List.generate(
                                      7,
                                      (x) => DropdownMenuItem(
                                            value: x + 1,
                                            child: Text(_dayName(x + 1)),
                                          )),
                                  onChanged: (v) => setD(() => d = v ?? d),
                                )
                              else
                                _AuraTapField(
                                  label: 'Fecha',
                                  value:
                                      '${_dayName(fecha.weekday)} ${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}',
                                  icon: Icons.calendar_today_rounded,
                                  onTap: () async {
                                    final hoy = DateTime.now();
                                    final p = await showDatePicker(
                                      context: ctx,
                                      initialDate: fecha,
                                      firstDate:
                                          DateTime(hoy.year, hoy.month, hoy.day),
                                      lastDate: DateTime(hoy.year + 1, hoy.month,
                                          hoy.day),
                                    );
                                    if (p != null) {
                                      setD(() => fecha =
                                          DateTime(p.year, p.month, p.day));
                                    }
                                  },
                                ),
                              const SizedBox(height: 12),
                              _AuraTapField(
                                label: 'Hora de inicio',
                                value: _timeText(t),
                                icon: Icons.schedule_rounded,
                                onTap: () async {
                                  final p = await showTimePicker(
                                      context: ctx, initialTime: t);
                                  if (p != null) setD(() => t = p);
                                },
                              ),
                              const SizedBox(height: 12),
                              _AuraDropdown<int>(
                                label: 'Duración',
                                value: dur,
                                items: const [
                                  DropdownMenuItem(
                                      value: 45, child: Text('45 min')),
                                  DropdownMenuItem(
                                      value: 60, child: Text('60 min')),
                                  DropdownMenuItem(
                                      value: 75, child: Text('75 min')),
                                  DropdownMenuItem(
                                      value: 90, child: Text('90 min')),
                                ],
                                onChanged: (v) => setD(() => dur = v ?? dur),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Card 3: Capacidad
                          _SectionCard(
                            title: 'Capacidad',
                            children: [
                              _AuraTextField(
                                controller: c,
                                label: 'Cupos disponibles',
                                hint: '12',
                                keyboardType: TextInputType.number,
                              ),
                              const SizedBox(height: 12),
                              _AuraDropdown<int>(
                                label: 'Cierre de reservas',
                                value: cierreReserva,
                                items: _bookingCutoffOptions
                                    .map((v) => DropdownMenuItem(
                                          value: v,
                                          child: Text(_bookingCutoffLabel(v)),
                                        ))
                                    .toList(),
                                onChanged: (v) =>
                                    setD(() => cierreReserva = v ?? 0),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Card 4: Categoría y precio
                          _SectionCard(
                            title: 'Categoría y precio',
                            children: [
                              if (categoriasDisponibles.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF1E8),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'Primero creá categorías desde Admin Aura > Config.',
                                    style: TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 13),
                                  ),
                                )
                              else
                                _AuraDropdown<String>(
                                  label: 'Categoría',
                                  value: categoriasDisponibles.contains(cat)
                                      ? cat
                                      : null,
                                  items: categoriasDisponibles
                                      .map((v) => DropdownMenuItem(
                                            value: v,
                                            child: Text(v),
                                          ))
                                      .toList(),
                                  onChanged: (v) => setD(() => cat = v),
                                ),
                              const SizedBox(height: 12),
                              _PricingPreview(
                                estudio: _estudio,
                                hora: '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                                dia: edit ? d : fecha.weekday,
                                categoria: cat,
                                onComputed: (creditos) {
                                  if (cr.text != creditos.toString()) {
                                    cr.text = creditos.toString();
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Card 5: Detalles adicionales (colapsable)
                          _CollapsibleSectionCard(
                            title: 'Detalles adicionales',
                            expanded: showExtraFields,
                            onToggle: () => setD(
                                () => showExtraFields = !showExtraFields),
                            children: [
                              _AuraTextField(
                                controller: iDesc,
                                label: 'Descripción del instructor/a',
                                hint:
                                    'Profesora certificada con 10 años de experiencia',
                                maxLines: 2,
                              ),
                              const SizedBox(height: 12),
                              _AuraTextField(
                                controller: incluye,
                                label: 'Qué incluye la clase',
                                hint: 'Mat, agua, vestuario',
                                maxLines: 2,
                              ),
                              const SizedBox(height: 12),
                              _AuraTextField(
                                controller: imagenUrl,
                                label: 'Imagen principal (URL)',
                                hint: 'https://...',
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final uploaded =
                                        await _subirImagenClase();
                                    if (uploaded != null) {
                                      imagenUrl.text = uploaded;
                                      setD(() {});
                                    }
                                  },
                                  icon: const Icon(Icons.image_outlined),
                                  label:
                                      const Text('Subir imagen principal'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _AuraTextField(
                                controller: galeria,
                                label: 'Galería de fotos',
                                hint: 'Una URL por línea',
                                maxLines: 3,
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final uploaded =
                                        await _subirImagenClase();
                                    if (uploaded != null) {
                                      galeria.text =
                                          galeria.text.trim().isEmpty
                                              ? uploaded
                                              : '${galeria.text.trim()}\n$uploaded';
                                      setD(() {});
                                    }
                                  },
                                  icon: const Icon(
                                      Icons.photo_library_outlined),
                                  label: const Text(
                                      'Agregar imagen a galería'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _AuraTextField(
                                controller: s,
                                label: 'Sala',
                                hint: 'Sala 1',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        16, 12, 16, mq.padding.bottom + 32),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: Text(
                            edit ? 'Guardar cambios' : 'Guardar clase'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
    if (ok != true) {
      n.dispose(); i.dispose(); iDesc.dispose(); incluye.dispose(); imagenUrl.dispose(); galeria.dispose(); s.dispose(); c.dispose(); cr.dispose(); return;
    }
    if (n.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Completá al menos el nombre de la clase')));
      n.dispose(); i.dispose(); iDesc.dispose(); incluye.dispose(); imagenUrl.dispose(); galeria.dispose(); s.dispose(); c.dispose(); cr.dispose(); return;
    }
    final payload = {
      'nombre': n.text.trim(),
      'dia_semana': d,
      'hora_inicio': '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
      'duracion_min': dur,
      'lugares_total': int.tryParse(c.text.trim()) ?? 12,
      'creditos': int.tryParse(cr.text.trim()) ?? 10,
      'reserva_cierre_minutos': cierreReserva,
      'instructor': i.text.trim().isEmpty ? null : i.text.trim(),
      'instructor_descripcion':
          iDesc.text.trim().isEmpty ? null : iDesc.text.trim(),
      'incluye': incluye.text.trim().isEmpty ? null : incluye.text.trim(),
      'imagen_url':
          imagenUrl.text.trim().isEmpty ? null : imagenUrl.text.trim(),
      'galeria_urls': _parseGaleria(galeria.text),
      'sala': s.text.trim().isEmpty ? null : s.text.trim(),
      'activo': item?['activo'] ?? true,
      if (cat != null) 'categoria': cat,
    };
    try {
      if (edit) {
        final updated = await _service.actualizarHorarioFijo((item['id'] as num).toInt(), payload);
        setState(() {
          _horarios = _horarios.map((h) => ((h['id'] as num?)?.toInt() == (updated['id'] as num?)?.toInt()) ? updated : h).toList();
          _sortFixed();
        });
        messenger.showSnackBar(const SnackBar(content: Text('Horario fijo actualizado')));
      } else {
        // Clase INDIVIDUAL: evento único en la fecha elegida. No crea horario
        // fijo ni genera repeticiones semanales.
        final fechaHora = DateTime(
          fecha.year,
          fecha.month,
          fecha.day,
          t.hour,
          t.minute,
        );
        await _service.crearClaseIndividual(
          fechaHora: fechaHora,
          payload: payload,
        );
        setState(() {
          _showFixed = false; // mostrar la solapa "Clases cargadas"
          _tablaOk = true;
          _error = null;
        });
        await _loadStudio();
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Clase individual creada (no se repite).')),
          );
        }
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo guardar: ${e.toString()}')));
      setState(() {
        _tablaOk = false;
        _error = e.toString();
      });
    } finally {
      n.dispose(); i.dispose(); iDesc.dispose(); incluye.dispose(); imagenUrl.dispose(); galeria.dispose(); s.dispose(); c.dispose(); cr.dispose();
    }
  }

  Future<void> _openGridForm() async {
    final messenger = ScaffoldMessenger.of(context);
    final categoriasDisponibles = await _loadCategoriasDisponibles();
    final n = TextEditingController();
    final i = TextEditingController();
    final iDesc = TextEditingController();
    final incluye = TextEditingController();
    final imagenUrl = TextEditingController();
    final galeria = TextEditingController();
    final s = TextEditingController();
    final c = TextEditingController(text: '12');
    final cr = TextEditingController(text: '10');
    int cierreReserva = 0;
    int dur = 60;
    String? cat;
    final diasSeleccionados = <int>{1, 2, 3, 4, 5};
    TimeOfDay horaInicio = const TimeOfDay(hour: 7, minute: 0);
    TimeOfDay horaFin = const TimeOfDay(hour: 21, minute: 0);

    if (!mounted) return;
    bool showExtraFields = false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final mq = MediaQuery.of(ctx);
        return AnimatedPadding(
          padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
          duration: const Duration(milliseconds: 100),
          child: FractionallySizedBox(
            heightFactor: 0.92,
            child: Container(
              decoration: const BoxDecoration(
                color: _kFieldFill,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1CAC3),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Nueva grilla',
                            style: TextStyle(
                              color: Color(0xFF1A1A1A),
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          icon: const Icon(Icons.close_rounded,
                              color: Color(0xFF1A1A1A)),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Column(
                        children: [
                          // Caption explicativo
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF1E8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Esto crea muchos horarios fijos de una sola vez. Las clases se van a programar automáticamente para los próximos 3 meses; pasado ese tiempo vas a tener que renovarlas para que sigan apareciendo a los usuarios. Después podés editar cada día y horario por separado sin tocar el resto de la grilla.',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Card 1: Información básica
                          _SectionCard(
                            title: 'Información básica',
                            children: [
                              _AuraTextField(
                                controller: n,
                                label: 'Nombre de la clase',
                                hint: 'Yoga restaurativo',
                              ),
                              const SizedBox(height: 12),
                              _AuraTextField(
                                controller: i,
                                label: 'Instructor/a',
                                hint: 'Florencia Pérez',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Card 2: Horario (días, rango, duración)
                          _SectionCard(
                            title: 'Horario',
                            children: [
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Días',
                                  style: TextStyle(
                                    color: Color(0xFF6E6761),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: List.generate(7, (index) {
                                  final dia = index + 1;
                                  final selected =
                                      diasSeleccionados.contains(dia);
                                  return FilterChip(
                                    label: Text(_dayName(dia)),
                                    selected: selected,
                                    backgroundColor: _kFieldFill,
                                    selectedColor:
                                        const Color(0xFFFFF1E8),
                                    checkmarkColor: AppColors.primary,
                                    labelStyle: TextStyle(
                                      color: selected
                                          ? AppColors.primary
                                          : const Color(0xFF6E6761),
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                    side: BorderSide(
                                      color: selected
                                          ? AppColors.primary
                                          : const Color(0xFFE5E0DA),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(99),
                                    ),
                                    onSelected: (value) {
                                      setD(() {
                                        if (value) {
                                          diasSeleccionados.add(dia);
                                        } else {
                                          diasSeleccionados.remove(dia);
                                        }
                                      });
                                    },
                                  );
                                }),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: _AuraTapField(
                                      label: 'Desde',
                                      value: _timeText(horaInicio),
                                      icon: Icons.schedule_rounded,
                                      onTap: () async {
                                        final picked = await showTimePicker(
                                          context: ctx,
                                          initialTime: horaInicio,
                                        );
                                        if (picked != null) {
                                          setD(() => horaInicio = picked);
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _AuraTapField(
                                      label: 'Hasta',
                                      value: _timeText(horaFin),
                                      icon: Icons.schedule_rounded,
                                      onTap: () async {
                                        final picked = await showTimePicker(
                                          context: ctx,
                                          initialTime: horaFin,
                                        );
                                        if (picked != null) {
                                          setD(() => horaFin = picked);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _AuraDropdown<int>(
                                label: 'Duración de cada clase',
                                value: dur,
                                items: const [
                                  DropdownMenuItem(
                                      value: 30, child: Text('30 min')),
                                  DropdownMenuItem(
                                      value: 45, child: Text('45 min')),
                                  DropdownMenuItem(
                                      value: 60, child: Text('60 min')),
                                  DropdownMenuItem(
                                      value: 75, child: Text('75 min')),
                                  DropdownMenuItem(
                                      value: 90, child: Text('90 min')),
                                ],
                                onChanged: (v) => setD(() => dur = v ?? dur),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Card 3: Capacidad
                          _SectionCard(
                            title: 'Capacidad',
                            children: [
                              _AuraTextField(
                                controller: c,
                                label: 'Cupos disponibles',
                                hint: '12',
                                keyboardType: TextInputType.number,
                              ),
                              const SizedBox(height: 12),
                              _AuraDropdown<int>(
                                label: 'Cierre de reservas',
                                value: cierreReserva,
                                items: _bookingCutoffOptions
                                    .map((v) => DropdownMenuItem(
                                          value: v,
                                          child:
                                              Text(_bookingCutoffLabel(v)),
                                        ))
                                    .toList(),
                                onChanged: (v) =>
                                    setD(() => cierreReserva = v ?? 0),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Card 4: Categoría y precio
                          _SectionCard(
                            title: 'Categoría y precio',
                            children: [
                              if (categoriasDisponibles.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF1E8),
                                    borderRadius:
                                        BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'Primero creá categorías desde Admin Aura > Config.',
                                    style: TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 13),
                                  ),
                                )
                              else
                                _AuraDropdown<String>(
                                  label: 'Categoría',
                                  value: categoriasDisponibles.contains(cat)
                                      ? cat
                                      : null,
                                  items: categoriasDisponibles
                                      .map((v) => DropdownMenuItem(
                                            value: v,
                                            child: Text(v),
                                          ))
                                      .toList(),
                                  onChanged: (v) => setD(() => cat = v),
                                ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF1E8),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Los créditos de cada clase se calculan automáticamente según el día y horario, usando la configuración de precios pico/valle del estudio.',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Card 5: Detalles adicionales (colapsable)
                          _CollapsibleSectionCard(
                            title: 'Detalles adicionales',
                            expanded: showExtraFields,
                            onToggle: () => setD(() =>
                                showExtraFields = !showExtraFields),
                            children: [
                              _AuraTextField(
                                controller: iDesc,
                                label: 'Descripción del instructor/a',
                                hint:
                                    'Profesora certificada con 10 años de experiencia',
                                maxLines: 2,
                              ),
                              const SizedBox(height: 12),
                              _AuraTextField(
                                controller: incluye,
                                label: 'Qué incluye la clase',
                                hint: 'Mat, agua, vestuario',
                                maxLines: 2,
                              ),
                              const SizedBox(height: 12),
                              _AuraTextField(
                                controller: imagenUrl,
                                label: 'Imagen principal (URL)',
                                hint: 'https://...',
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final uploaded =
                                        await _subirImagenClase();
                                    if (uploaded != null) {
                                      imagenUrl.text = uploaded;
                                      setD(() {});
                                    }
                                  },
                                  icon: const Icon(Icons.image_outlined),
                                  label:
                                      const Text('Subir imagen principal'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _AuraTextField(
                                controller: galeria,
                                label: 'Galería de fotos',
                                hint: 'Una URL por línea',
                                maxLines: 3,
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final uploaded =
                                        await _subirImagenClase();
                                    if (uploaded != null) {
                                      galeria.text =
                                          galeria.text.trim().isEmpty
                                              ? uploaded
                                              : '${galeria.text.trim()}\n$uploaded';
                                      setD(() {});
                                    }
                                  },
                                  icon: const Icon(
                                      Icons.photo_library_outlined),
                                  label: const Text(
                                      'Agregar imagen a galería'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _AuraTextField(
                                controller: s,
                                label: 'Sala',
                                hint: 'Sala 1',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        16, 12, 16, mq.padding.bottom + 32),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('Crear grilla'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );

    if (ok != true) {
      n.dispose();
      i.dispose();
      iDesc.dispose();
      incluye.dispose();
      imagenUrl.dispose();
      galeria.dispose();
      s.dispose();
      c.dispose();
      cr.dispose();
      return;
    }

    if (n.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Completá al menos el nombre de la clase')),
      );
      n.dispose();
      i.dispose();
      iDesc.dispose();
      incluye.dispose();
      imagenUrl.dispose();
      galeria.dispose();
      s.dispose();
      c.dispose();
      cr.dispose();
      return;
    }
    final payloadBase = {
      'nombre': n.text.trim(),
      'lugares_total': int.tryParse(c.text.trim()) ?? 12,
      'creditos': int.tryParse(cr.text.trim()) ?? 10,
      'reserva_cierre_minutos': cierreReserva,
      'instructor': i.text.trim().isEmpty ? null : i.text.trim(),
      'instructor_descripcion':
          iDesc.text.trim().isEmpty ? null : iDesc.text.trim(),
      'incluye': incluye.text.trim().isEmpty ? null : incluye.text.trim(),
      'imagen_url':
          imagenUrl.text.trim().isEmpty ? null : imagenUrl.text.trim(),
      'galeria_urls': _parseGaleria(galeria.text),
      'sala': s.text.trim().isEmpty ? null : s.text.trim(),
      'activo': true,
      if (cat != null) 'categoria': cat,
    };

    try {
      final creados = await _service.crearHorariosFijosEnGrilla(
        diasSemana: diasSeleccionados.toList(),
        horaInicio: horaInicio,
        horaFin: horaFin,
        duracionMin: dur,
        payloadBase: payloadBase,
      );
      await _loadStudio();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Grilla creada: $creados horarios fijos. Generando próximos 3 meses…')),
      );
      try {
        final result = await _service.generarProximasSemanasDesdeHorarios(weeks: 13);
        await _loadStudio();
        if (!mounted) return;
        final creadas = result['creadas'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Clases programadas para 3 meses ($creadas nuevas).')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Grilla creada pero falló la generación automática: ${e.toString()}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear la grilla: ${e.toString()}')),
      );
    } finally {
      n.dispose();
      i.dispose();
      iDesc.dispose();
      incluye.dispose();
      imagenUrl.dispose();
      galeria.dispose();
      s.dispose();
      c.dispose();
      cr.dispose();
    }
  }

  void _sortFixed() {
    _horarios.sort((a, b) {
      final da = (a['dia_semana'] as num?)?.toInt() ?? 1;
      final db = (b['dia_semana'] as num?)?.toInt() ?? 1;
      if (da != db) return da.compareTo(db);
      return (a['hora_inicio']?.toString() ?? '').compareTo(b['hora_inicio']?.toString() ?? '');
    });
  }

  Future<void> _deleteFixed(int id) async {
    try {
      await _service.eliminarHorarioFijo(id);
      if (!mounted) return;
      setState(() => _horarios.removeWhere((h) => (h['id'] as num?)?.toInt() == id));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo eliminar el horario.')));
    }
  }

  Future<void> _generateWeek() async {
    setState(() => _publishingWeek = true);
    try {
      final result = await _service.generarProximasSemanasDesdeHorarios(weeks: 13);
      await _loadStudio();
      if (!mounted) return;
      final creadas = result['creadas'] ?? 0;
      final omitidas = result['omitidas'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '3 meses publicados: $creadas clases creadas${omitidas > 0 ? ', $omitidas ya existían o se omitieron' : ''}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar la semana: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _publishingWeek = false);
    }
  }

  Widget _buildDesktopContent() {
    const headerStyle = TextStyle(
      color: Color(0xFF888888),
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
    );

    final start = _weekStart(_weekAnchor);
    final days = List.generate(7, (i) => start.add(Duration(days: i)));
    // All clases for the selected week, flattened and sorted
    final weekClases = days.expand((d) => _classesOn(d)).toList()
      ..sort((a, b) => (a['fecha']?.toString() ?? '').compareTo(b['fecha']?.toString() ?? ''));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header row ────────────────────────────────────────────────────
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SegmentButton(
                    label: 'Horarios fijos',
                    selected: _showFixed,
                    onTap: () => setState(() => _showFixed = true),
                  ),
                  _SegmentButton(
                    label: 'Clases cargadas',
                    selected: !_showFixed,
                    onTap: () => setState(() => _showFixed = false),
                  ),
                ],
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: _openGridForm,
              icon: const Icon(Icons.grid_view_rounded),
              color: AppColors.primary,
              tooltip: 'Crear grilla',
            ),
            IconButton(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              color: AppColors.primary,
              tooltip: 'Nueva clase',
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Horarios fijos table ──────────────────────────────────────────
        if (_showFixed) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: const Border(bottom: BorderSide(color: AppColors.warmBorder)),
            ),
            child: const Row(
              children: [
                SizedBox(width: 80, child: Text('DÍA', style: headerStyle)),
                SizedBox(width: 72, child: Text('HORA', style: headerStyle)),
                Expanded(flex: 3, child: Text('CLASE', style: headerStyle)),
                Expanded(flex: 2, child: Text('INSTRUCTOR', style: headerStyle)),
                SizedBox(width: 60, child: Text('CUPOS', style: headerStyle, textAlign: TextAlign.center)),
                SizedBox(width: 72, child: Text('CRÉDITOS', style: headerStyle, textAlign: TextAlign.center)),
                SizedBox(width: 72, child: Text('ESTADO', style: headerStyle, textAlign: TextAlign.center)),
                SizedBox(width: 60, child: SizedBox()),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _horarios.isEmpty
                    ? Center(
                        child: Text(
                          'Todavía no hay horarios fijos.\nUsá "Crear grilla" o "Nueva clase" para empezar.',
                          style: const TextStyle(color: AppColors.grey, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Container(
                        decoration: const BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                        ),
                        child: ListView.separated(
                          itemCount: _horarios.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.warmBorder),
                          itemBuilder: (context, index) {
                            final h = _horarios[index];
                            final dia = (h['dia_semana'] as num?)?.toInt() ?? 1;
                            final hora = h['hora_inicio']?.toString() ?? '--:--';
                            final nombre = h['nombre']?.toString() ?? 'Clase';
                            final instructor = h['instructor']?.toString();
                            final cupos = (h['lugares_total'] as num?)?.toInt() ?? 0;
                            final creditos = (h['creditos'] as num?)?.toInt() ?? 0;
                            final activo = h['activo'] != false;
                            return InkWell(
                              onTap: () => _openForm(h),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 80,
                                      child: Text(
                                        _shortDay(dia),
                                        style: const TextStyle(
                                          color: AppColors.black,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 72,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.blackSoft,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          hora.length > 5 ? hora.substring(0, 5) : hora,
                                          style: const TextStyle(
                                            color: AppColors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        nombre,
                                        style: const TextStyle(
                                          color: AppColors.black,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        instructor ?? '—',
                                        style: const TextStyle(color: Color(0xFF8F877F), fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 60,
                                      child: Text(
                                        '$cupos',
                                        style: const TextStyle(color: AppColors.black, fontSize: 13),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 72,
                                      child: Text(
                                        '$creditos cr.',
                                        style: const TextStyle(color: AppColors.black, fontSize: 13),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 72,
                                      child: Center(
                                        child: Switch(
                                          value: activo,
                                          activeColor: AppColors.primary,
                                          onChanged: _togglingFixed ? null : (v) => _toggleFixed((h['id'] as num?)?.toInt() ?? 0, v),
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 60,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            onPressed: () => _openForm(h),
                                            icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF8F877F)),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                          ),
                                          IconButton(
                                            onPressed: () => _deleteFixed((h['id'] as num?)?.toInt() ?? 0),
                                            icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFE53935)),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ] else ...[
          // ── Clases cargadas: week selector + table ────────────────────
          Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _weekAnchor = _weekAnchor.subtract(const Duration(days: 7))),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  '${DateFormat('d MMM', 'es').format(days.first)} — ${DateFormat('d MMM yyyy', 'es').format(days.last)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.black, fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _weekAnchor = _weekAnchor.add(const Duration(days: 7))),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 38,
                child: ElevatedButton.icon(
                  onPressed: _publishingWeek ? null : _generateWeek,
                  icon: _publishingWeek
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                      : const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: Text(_publishingWeek ? 'Generando…' : 'Generar 3 meses'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: const Border(bottom: BorderSide(color: AppColors.warmBorder)),
            ),
            child: const Row(
              children: [
                SizedBox(width: 80, child: Text('HORA', style: headerStyle)),
                Expanded(flex: 3, child: Text('CLASE', style: headerStyle)),
                Expanded(flex: 2, child: Text('INSTRUCTOR', style: headerStyle)),
                SizedBox(width: 100, child: Text('CUPOS', style: headerStyle, textAlign: TextAlign.center)),
                SizedBox(width: 80, child: Text('CRÉDITOS', style: headerStyle, textAlign: TextAlign.center)),
                SizedBox(width: 100, child: Text('ESTADO', style: headerStyle, textAlign: TextAlign.center)),
                SizedBox(width: 48, child: SizedBox()),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : weekClases.isEmpty
                    ? Center(
                        child: Text(
                          'Sin clases para esta semana.\nUsá "Generar 3 meses" para crear desde los horarios fijos.',
                          style: const TextStyle(color: AppColors.grey, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Container(
                        decoration: const BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                        ),
                        child: ListView.separated(
                          itemCount: weekClases.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.warmBorder),
                          itemBuilder: (context, index) {
                            final c = weekClases[index];
                            final dt = DateTime.tryParse(c['fecha']?.toString() ?? '');
                            final hora = dt != null ? DateFormat('HH:mm').format(dt) : '--:--';
                            final diaLabel = dt != null ? DateFormat('EEE d/M', 'es').format(dt) : '';
                            final nombre = c['nombre']?.toString() ?? 'Clase';
                            final instructor = c['instructor']?.toString();
                            final total = (c['lugares_total'] as num?)?.toInt() ?? 0;
                            final disp = (c['lugares_disponibles'] as num?)?.toInt() ?? 0;
                            final ocupados = (total - disp).clamp(0, total);
                            final creditos = (c['creditos'] as num?)?.toInt() ?? 0;
                            final dt2 = DateTime.tryParse(c['fecha']?.toString() ?? '');
                            final now2 = DateTime.now();
                            final status = dt2 == null
                                ? 'Programada'
                                : (dt2.isBefore(now2) && now2.difference(dt2).inMinutes < 90)
                                    ? 'En curso'
                                    : dt2.difference(now2).inHours < 8
                                        ? 'Confirmada'
                                        : 'Programada';
                            final statusColor = status == 'Confirmada'
                                ? const Color(0xFFE3F3E5)
                                : status == 'En curso'
                                    ? const Color(0xFFFFF3DE)
                                    : const Color(0xFFF1E7FF);
                            return InkWell(
                              onTap: () => _showClaseSheet(c),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 80,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: AppColors.blackSoft,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              hora,
                                              style: const TextStyle(color: AppColors.white, fontSize: 11, fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            diaLabel,
                                            style: const TextStyle(color: Color(0xFF9A928B), fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        nombre,
                                        style: const TextStyle(color: AppColors.black, fontSize: 14, fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        instructor ?? '—',
                                        style: const TextStyle(color: Color(0xFF8F877F), fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 100,
                                      child: Column(
                                        children: [
                                          Text(
                                            '$ocupados / $total',
                                            style: const TextStyle(color: AppColors.black, fontSize: 13, fontWeight: FontWeight.w600),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 4),
                                          LinearProgressIndicator(
                                            value: total > 0 ? ocupados / total : 0,
                                            backgroundColor: const Color(0xFFEEEEEE),
                                            color: AppColors.primary,
                                            minHeight: 4,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: 80,
                                      child: Text(
                                        '$creditos cr.',
                                        style: const TextStyle(color: AppColors.black, fontSize: 13),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 100,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: statusColor,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            status,
                                            style: TextStyle(
                                              color: status == 'En curso'
                                                  ? const Color(0xFF7C5400)
                                                  : status == 'Confirmada'
                                                      ? const Color(0xFF2E7D32)
                                                      : const Color(0xFF6B3FA0),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => _mostrarAvisoSheet(c),
                                      icon: const Icon(Icons.notifications_outlined, size: 18, color: Color(0xFF8F877F)),
                                      tooltip: 'Avisar a alumnos',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    ),
                                    SizedBox(
                                      width: 48,
                                      child: IconButton(
                                        onPressed: () => _showClaseSheet(c),
                                        icon: const Icon(Icons.more_vert_rounded, size: 18, color: Color(0xFF8F877F)),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    // Studio: solo lo que reservo el user (dueño viendo sus alumnos).
    // User: TODAS las clases disponibles ese dia (para que pueda reservar
    // tocando una). Marcamos cuales ya reservo el user.
    final dayClasses = _studio
        ? _reservedClassesOn(_selectedDay)
        : _userClassesOn(_selectedDay);
    final upcomingReservas = _proximasReservas;

    if (isDesktop && _studio) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : Padding(
                padding: const EdgeInsets.all(28),
                child: _buildDesktopContent(),
              ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SafeArea(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                  children: [
                    Row(children: [
                      const Expanded(child: Text('Mis clases', style: TextStyle(color: AppColors.black, fontSize: 22, fontWeight: FontWeight.w700))),
                      if (_studio) ...[
                        IconButton(
                          onPressed: _openGridForm,
                          icon: const Icon(Icons.grid_view_rounded),
                          color: AppColors.primary,
                          tooltip: 'Crear grilla',
                        ),
                        IconButton(
                          onPressed: () => _openForm(),
                          icon: const Icon(Icons.add),
                          color: AppColors.primary,
                          tooltip: 'Nuevo horario',
                        ),
                      ] else
                        SizedBox(
                          height: 40,
                          child: ElevatedButton(
                            onPressed: () => context.go('/explorar'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                            ),
                            child: const Text('Nueva clase'),
                          ),
                        ),
                    ]),
                    if (_studio) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16)),
                        child: Row(children: [
                          Expanded(child: _SegmentButton(label: 'Horarios fijos', selected: _showFixed, onTap: () => setState(() => _showFixed = true))),
                          Expanded(child: _SegmentButton(label: 'Clases cargadas', selected: !_showFixed, onTap: () => setState(() => _showFixed = false))),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_studio && _showFixed) ..._buildFixed()
                    else if (_studio) ..._buildWeekLoaded()
                    else ...[
                      _buildMonthCalendar(),
                      const SizedBox(height: 14),
                      Center(child: Text(DateFormat("EEEE d 'de' MMMM", 'es').format(_selectedDay).toUpperCase(), style: const TextStyle(color: Color(0xFF9A928B), fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1))),
                      const SizedBox(height: 16),
                      if (dayClasses.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text(
                              _studio
                                  ? 'No hay clases cargadas para este día'
                                  : 'No hay clases disponibles este día',
                              style: const TextStyle(color: Color(0xFF8F877F)),
                            ),
                          ),
                        )
                      else
                        ...dayClasses.map((c) {
                          final card = _StudioClassCard(
                            clase: c,
                            studioMode: _studio,
                            onAvisar: _studio ? () => _mostrarAvisoSheet(c) : null,
                          );
                          if (_studio) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: card,
                            );
                          }
                          final claseId = (c['id'] as num?)?.toInt();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(22),
                              onTap: claseId == null
                                  ? null
                                  : () => context.push('/clase/$claseId'),
                              child: card,
                            ),
                          );
                        }),
                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Próximas reservas',
                            style: TextStyle(
                              color: AppColors.black,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (upcomingReservas.isNotEmpty)
                            GestureDetector(
                              onTap: () => context.go('/mis-reservas'),
                              child: const Text(
                                'Ver todas',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (upcomingReservas.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Text(
                            'Todavía no tenés reservas próximas.',
                            style: TextStyle(color: Color(0xFF8F877F), fontSize: 14),
                          ),
                        )
                      else
                        ...upcomingReservas.take(3).map(
                              (r) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _UpcomingReservaCard(reserva: r),
                              ),
                            ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  List<Map<String, dynamic>> get _proximasReservas {
    final now = DateTime.now();
    final result = _reservas.where((r) {
      final estado = r['estado']?.toString() ?? '';
      if (estado == 'cancelada' || estado == 'completada') return false;
      final clase = r['clases'] as Map<String, dynamic>?;
      final fecha = DateTime.tryParse(clase?['fecha']?.toString() ?? '');
      return fecha != null && fecha.isAfter(now.subtract(const Duration(hours: 2)));
    }).toList();

    result.sort((a, b) {
      final fechaA = DateTime.tryParse((a['clases'] as Map<String, dynamic>?)?['fecha']?.toString() ?? '');
      final fechaB = DateTime.tryParse((b['clases'] as Map<String, dynamic>?)?['fecha']?.toString() ?? '');
      if (fechaA == null && fechaB == null) return 0;
      if (fechaA == null) return 1;
      if (fechaB == null) return -1;
      return fechaA.compareTo(fechaB);
    });
    return result;
  }

  List<Map<String, dynamic>> get _reservasActivas {
    final now = DateTime.now();
    final result = _reservas.where((r) {
      final estado = r['estado']?.toString() ?? '';
      if (estado != 'confirmada' && estado != 'presente') return false;
      final clase = r['clases'] as Map<String, dynamic>?;
      final fecha = DateTime.tryParse(clase?['fecha']?.toString() ?? '');
      return fecha != null && fecha.isAfter(now.subtract(const Duration(hours: 2)));
    }).toList();
    result.sort((a, b) {
      final fechaA = DateTime.tryParse((a['clases'] as Map<String, dynamic>?)?['fecha']?.toString() ?? '');
      final fechaB = DateTime.tryParse((b['clases'] as Map<String, dynamic>?)?['fecha']?.toString() ?? '');
      if (fechaA == null && fechaB == null) return 0;
      if (fechaA == null) return 1;
      if (fechaB == null) return -1;
      return fechaA.compareTo(fechaB);
    });
    return result;
  }

  /// Para el calendario user-side: lista las clases disponibles para
  /// reservar ese dia, marcando cuales el user ya reservo (tienen
  /// `_user_reserva_qr` seteado). Combina `_clases` (proximas
  /// disponibles) + `_reservas` (las que ya tomo).
  List<Map<String, dynamic>> _userClassesOn(DateTime day) {
    // QRs por clase_id para enriquecer las clases con reserva del user.
    final qrPorClase = <int, String>{};
    for (final r in _reservasActivas) {
      final claseId = (r['clase_id'] as num?)?.toInt();
      final qr = r['codigo_qr']?.toString();
      if (claseId != null && qr != null && qr.isNotEmpty) {
        qrPorClase[claseId] = qr;
      }
    }

    final result = _clases.where((c) {
      final dt = DateTime.tryParse(c['fecha']?.toString() ?? '');
      return dt != null &&
          dt.year == day.year &&
          dt.month == day.month &&
          dt.day == day.day;
    }).map((c) {
      final id = (c['id'] as num?)?.toInt();
      final total = (c['lugares_total'] as num?)?.toInt() ?? 0;
      final disponibles = (c['lugares_disponibles'] as num?)?.toInt() ?? 0;
      final ocupacion = (c['_ocupacion'] as num?)?.toInt();
      return {
        ...c,
        if (id != null && qrPorClase.containsKey(id))
          '_user_reserva_qr': qrPorClase[id],
        '_ocupados_real': ocupacion ?? (total > 0 ? (total - disponibles).clamp(0, total) : 0),
        '_disponibles_real': disponibles,
      };
    }).toList();

    result.sort((a, b) {
      final fa = DateTime.tryParse(a['fecha']?.toString() ?? '');
      final fb = DateTime.tryParse(b['fecha']?.toString() ?? '');
      if (fa == null || fb == null) return 0;
      return fa.compareTo(fb);
    });
    return result;
  }

  List<Map<String, dynamic>> _reservedClassesOn(DateTime day) {
    final list = _reservasActivas.where((r) {
      final clase = r['clases'] as Map<String, dynamic>?;
      final dt = DateTime.tryParse(clase?['fecha']?.toString() ?? '');
      return dt != null && dt.year == day.year && dt.month == day.month && dt.day == day.day;
    }).map((r) {
      final clase = Map<String, dynamic>.from((r['clases'] as Map<String, dynamic>?) ?? const {});
      final total = (clase['lugares_total'] as num?)?.toInt() ?? 0;
      final disponibles = ((clase['lugares_disponibles'] ?? clase['lugares_ disponibles']) as num?)?.toInt() ?? 0;
      return {
        ...clase,
        '_user_reserva_qr': r['codigo_qr'],
        '_ocupados_real': total > 0 ? (total - disponibles).clamp(0, total) : 0,
        '_disponibles_real': disponibles,
      };
    }).toList();
    list.sort((a, b) => (a['fecha']?.toString() ?? '').compareTo(b['fecha']?.toString() ?? ''));
    return list;
  }

  Widget _buildMonthCalendar() {
    final monthStart = DateTime(_monthAnchor.year, _monthAnchor.month, 1);
    final gridStart = monthStart.subtract(Duration(days: monthStart.weekday - 1));
    final gridDays = List.generate(42, (index) => gridStart.add(Duration(days: index)));
    final reservedKeys = _reservasActivas.map((r) {
      final clase = r['clases'] as Map<String, dynamic>?;
      final dt = DateTime.tryParse(clase?['fecha']?.toString() ?? '');
      return dt == null ? null : '${dt.year}-${dt.month}-${dt.day}';
    }).whereType<String>().toSet();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => setState(() {
                  _monthAnchor = DateTime(_monthAnchor.year, _monthAnchor.month - 1, 1);
                  _selectedDay = DateTime(_monthAnchor.year, _monthAnchor.month, 1);
                }),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDay,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      locale: const Locale('es'),
                    );
                    if (picked == null || !mounted) return;
                    setState(() {
                      _selectedDay = picked;
                      _monthAnchor = DateTime(picked.year, picked.month, 1);
                    });
                  },
                  child: Column(
                    children: [
                      Text(
                        DateFormat('MMMM yyyy', 'es').format(monthStart),
                        style: const TextStyle(color: AppColors.black, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Tocá para elegir otro mes',
                        style: TextStyle(color: Color(0xFF9A928B), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() {
                  _monthAnchor = DateTime(_monthAnchor.year, _monthAnchor.month + 1, 1);
                  _selectedDay = DateTime(_monthAnchor.year, _monthAnchor.month, 1);
                }),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              _WeekHeader('LUN'),
              _WeekHeader('MAR'),
              _WeekHeader('MIÉ'),
              _WeekHeader('JUE'),
              _WeekHeader('VIE'),
              _WeekHeader('SÁB'),
              _WeekHeader('DOM'),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: gridDays.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.82,
            ),
            itemBuilder: (context, index) {
              final day = gridDays[index];
              final selected = day.day == _selectedDay.day && day.month == _selectedDay.month && day.year == _selectedDay.year;
              final inMonth = day.month == monthStart.month && day.year == monthStart.year;
              final hasReserva = reservedKeys.contains('${day.year}-${day.month}-${day.day}');
              return GestureDetector(
                onTap: () => setState(() => _selectedDay = day),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.blackSoft : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            color: selected
                                ? AppColors.white
                                : (inMonth ? const Color(0xFF8F877F) : const Color(0xFFD2CAC3)),
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: hasReserva ? AppColors.primary : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    final start = _weekStart(_weekAnchor);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        Row(
          children: [
            IconButton(
              onPressed: () => setState(() {
                _weekAnchor = _weekAnchor.subtract(const Duration(days: 7));
                _selectedDay = _selectedDay.subtract(const Duration(days: 7));
              }),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDay,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    locale: const Locale('es'),
                  );
                  if (picked == null || !mounted) return;
                  setState(() {
                    _selectedDay = picked;
                    _weekAnchor = _weekStart(picked);
                  });
                },
                child: Column(
                  children: [
                    Text(
                      '${DateFormat('d MMM', 'es').format(start)} - ${DateFormat('d MMM', 'es').format(start.add(const Duration(days: 6)))}',
                      style: const TextStyle(color: AppColors.black, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Tocá para elegir otra semana',
                      style: TextStyle(color: Color(0xFF9A928B), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              onPressed: () => setState(() {
                _weekAnchor = _weekAnchor.add(const Duration(days: 7));
                _selectedDay = _selectedDay.add(const Duration(days: 7));
              }),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
          _WeekHeader('LUN'), _WeekHeader('MAR'), _WeekHeader('MIÉ'), _WeekHeader('JUE'), _WeekHeader('VIE'), _WeekHeader('SÁB'), _WeekHeader('DOM')
        ]),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (index) {
            final day = start.add(Duration(days: index));
            final selected = day.day == _selectedDay.day && day.month == _selectedDay.month;
            return GestureDetector(
              onTap: () => setState(() => _selectedDay = day),
              child: Column(children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(color: selected ? AppColors.blackSoft : Colors.transparent, shape: BoxShape.circle),
                  child: Center(child: Text('${day.day}', style: TextStyle(color: selected ? AppColors.white : const Color(0xFF8F877F), fontWeight: selected ? FontWeight.w700 : FontWeight.w500))),
                ),
                const SizedBox(height: 8),
                Container(width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
              ]),
            );
          }),
        ),
      ]),
    );
  }

  List<Widget> _buildFixed() {
    if (!_tablaOk) {
      return [_InfoPanel(title: 'No se pudieron cargar los horarios fijos', body: _error ?? 'Hubo un problema leyendo la tabla horarios_fijos.')];
    }
    if (_horarios.isEmpty) {
      return const [_InfoPanel(title: 'Todavía no hay horarios fijos', body: 'Podés cargar una grilla semanal tipo Deportnet con el botón "Nuevo horario".')];
    }
    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final h in _horarios) {
      final d = (h['dia_semana'] as num?)?.toInt() ?? 1;
      grouped.putIfAbsent(d, () => []).add(h);
    }
    return List.generate(7, (index) {
      final dia = index + 1;
      final items = grouped[dia] ?? [];
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_dayName(dia), style: const TextStyle(color: AppColors.black, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (items.isEmpty)
              const Text('Sin horarios cargados.', style: TextStyle(color: Color(0xFF8F877F)))
            else
              ...items.map((h) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _HorarioFijoCard(
                      horario: h,
                      onEdit: () => _openForm(h),
                      onDelete: () => _deleteFixed((h['id'] as num?)?.toInt() ?? 0),
                      onToggle: (v) => _toggleFixed((h['id'] as num?)?.toInt() ?? 0, v),
                    ),
                  )),
          ]),
        ),
      );
    });
  }

  List<Widget> _buildWeekLoaded() {
    final start = _weekStart(_weekAnchor);
    final days = List.generate(7, (i) => start.add(Duration(days: i)));
    return [
      Row(children: [
        IconButton(onPressed: () => setState(() => _weekAnchor = _weekAnchor.subtract(const Duration(days: 7))), icon: const Icon(Icons.chevron_left_rounded)),
        Expanded(
          child: Text(
            '${DateFormat('d MMM', 'es').format(days.first)} - ${DateFormat('d MMM', 'es').format(days.last)}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.black, fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(onPressed: () => setState(() => _weekAnchor = _weekAnchor.add(const Duration(days: 7))), icon: const Icon(Icons.chevron_right_rounded)),
      ]),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          height: 40,
          child: ElevatedButton.icon(
            onPressed: _publishingWeek ? null : _generateWeek,
            icon: _publishingWeek
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.white,
                    ),
                  )
                : const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(_publishingWeek ? 'Generando…' : 'Generar 3 meses'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(7, (i) {
            final day = days[i];
            final classes = _weekItemsOn(day);
            return Container(
              width: 150,
              margin: EdgeInsets.only(right: i == 6 ? 0 : 8),
              decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(18)),
              child: Column(children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.warmBorder))),
                  child: Column(children: [
                    Text(_shortDay(day.weekday).toUpperCase(), style: const TextStyle(fontSize: 11, color: Color(0xFF8F877F), fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('${day.day}', style: const TextStyle(fontSize: 18, color: AppColors.black, fontWeight: FontWeight.w700)),
                  ]),
                ),
                SizedBox(
                  height: 460,
                  child: classes.isEmpty
                      ? const Center(child: Padding(padding: EdgeInsets.all(8), child: Text('Sin clases', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFFB0A8A0)))))
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: classes.length,
                              itemBuilder: (context, x) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _WeekClassChip(
                              clase: classes[x],
                              onTap: classes[x]['_kind'] == 'loaded'
                                  ? () => _showClaseSheet(classes[x])
                                  : null,
                            ),
                          ),
                        ),
                ),
              ]),
            );
          }),
        ),
      ),
    ];
  }

  List<Map<String, dynamic>> _classesOn(DateTime day) {
    final list = _clases.where((c) {
      final dt = DateTime.tryParse(c['fecha']?.toString() ?? '');
      return dt != null && dt.year == day.year && dt.month == day.month && dt.day == day.day;
    }).toList();
    list.sort((a, b) => (a['fecha']?.toString() ?? '').compareTo(b['fecha']?.toString() ?? ''));
    return list;
  }

  List<Map<String, dynamic>> _weekItemsOn(DateTime day) {
    final loaded = _classesOn(day)
        .map((c) => {
              ...c,
              '_kind': 'loaded',
              '_sort_time': DateTime.tryParse(c['fecha']?.toString() ?? '') != null
                  ? DateFormat('HH:mm').format(DateTime.parse(c['fecha'].toString()))
                  : '99:99',
            })
        .toList();

    // Suprimir horarios fijos que ya tienen una clase cargada con el mismo horario_fijo_id
    final loadedHorarioIds = loaded
        .map((c) => (c['horario_fijo_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet();

    final fixed = _horarios.where((h) {
      final dia = (h['dia_semana'] as num?)?.toInt() ?? 0;
      if (dia != day.weekday) return false;
      final hId = (h['id'] as num?)?.toInt();
      // Suprimir si ya hay clase cargada con este horario_fijo_id
      if (hId != null && loadedHorarioIds.contains(hId)) return false;
      return true;
    }).map((h) => {
          ...h,
          '_kind': 'fixed',
          '_sort_time': h['hora_inicio']?.toString() ?? '99:99',
        });

    final merged = [...loaded, ...fixed];
    merged.sort(
      (a, b) => (a['_sort_time'] as String).compareTo(b['_sort_time'] as String),
    );
    return merged;
  }

  DateTime _weekStart(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
  static const List<int> _bookingCutoffOptions = [0, 30, 60, 120, 180, 360, 720, 1440];
  String _bookingCutoffLabel(int minutes) {
    if (minutes <= 0) return 'Hasta el inicio de la clase';
    if (minutes == 30) return 'Hasta 30 min antes';
    if (minutes % 1440 == 0) {
      final dias = minutes ~/ 1440;
      return dias == 1 ? 'Hasta 1 día antes' : 'Hasta $dias días antes';
    }
    if (minutes % 60 == 0) {
      final horas = minutes ~/ 60;
      return horas == 1 ? 'Hasta 1 hora antes' : 'Hasta $horas horas antes';
    }
    return 'Hasta $minutes min antes';
  }
  String _shortDay(int d) => const {1: 'Lun', 2: 'Mar', 3: 'Mié', 4: 'Jue', 5: 'Vie', 6: 'Sáb', 7: 'Dom'}[d] ?? 'Lun';
  String _dayName(int d) => const {1: 'Lunes', 2: 'Martes', 3: 'Miércoles', 4: 'Jueves', 5: 'Viernes', 6: 'Sábado', 7: 'Domingo'}[d] ?? 'Lunes';
  String _timeText(TimeOfDay t) => DateFormat('HH:mm').format(DateTime(2024, 1, 1, t.hour, t.minute));
}

class _WeekHeader extends StatelessWidget {
  final String text;
  const _WeekHeader(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(color: Color(0xFF9A928B), fontSize: 12, fontWeight: FontWeight.w600));
}

class _StudioClassCard extends StatelessWidget {
  final Map<String, dynamic> clase;
  final bool studioMode;
  final VoidCallback? onAvisar;
  const _StudioClassCard({required this.clase, required this.studioMode, this.onAvisar});
  @override
  Widget build(BuildContext context) {
    final dt = DateTime.tryParse(clase['fecha']?.toString() ?? '');
    final time = dt != null ? DateFormat('hh:mm a').format(dt) : '07:00 AM';
    final instructor = clase['instructor']?.toString() ?? 'Sin instructor';
    final total = (clase['lugares_total'] as num?)?.toInt() ?? 20;
    final disp = (clase['_disponibles_real'] as num?)?.toInt() ??
        ((clase['lugares_disponibles'] ?? clase['lugares_ disponibles']) as num?)?.toInt() ??
        0;
    final ocupados = (clase['_ocupados_real'] as num?)?.toInt() ?? (total - disp);
    final progress = total <= 0 ? 0.0 : (ocupados / total).clamp(0.0, 1.0);
    final status = _status(clase);
    final statusColor = _statusColor(status);
    final barColor = status == 'En curso' ? AppColors.primary : status == 'Confirmada' ? const Color(0xFF4CAF50) : const Color(0xFFB28CFF);
    final codigoQr = clase['_user_reserva_qr']?.toString();
    final userHasReserva = !studioMode && codigoQr != null && codigoQr.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(22), boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 6))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: AppColors.blackSoft, borderRadius: BorderRadius.circular(8)),
            child: Text(time.toUpperCase(), style: const TextStyle(color: AppColors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(999)),
            child: Text(status, style: const TextStyle(color: Color(0xFF5F5953), fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 14),
        Text(clase['nombre']?.toString() ?? 'Clase', style: const TextStyle(color: AppColors.black, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Instructora: $instructor', style: const TextStyle(color: Color(0xFF8F877F), fontSize: 14)),
        const SizedBox(height: 12),
        const Text('Ocupación', style: TextStyle(color: Color(0xFF8F877F), fontSize: 13)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: progress, minHeight: 6, color: barColor, backgroundColor: const Color(0xFFEDE7E1)),
            ),
          ),
          const SizedBox(width: 10),
          Text('$ocupados/$total lugares', style: const TextStyle(color: Color(0xFF6A635D), fontSize: 13)),
        ]),
        const SizedBox(height: 14),
        if (userHasReserva) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.push('/reserva-confirmada/${Uri.encodeComponent(codigoQr)}'),
              child: const Text('Ver ticket QR'),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (studioMode)
          Row(children: [
            _ActionButton(label: 'Ver lista', background: AppColors.primary, foreground: AppColors.white, onTap: () => context.push('/estudio/asistencia')),
            const SizedBox(width: 8),
            _ActionButton(label: 'Editar', background: const Color(0xFFF1F1F1), foreground: const Color(0xFF6A635D), onTap: () {}),
            const SizedBox(width: 8),
            _ActionButton(label: 'Avisar', background: const Color(0xFFF1F1F1), foreground: const Color(0xFF6A635D), onTap: onAvisar ?? () {}),
          ]),
      ]),
    );
  }

  String _status(Map<String, dynamic> c) {
    final dt = DateTime.tryParse(c['fecha']?.toString() ?? '');
    if (dt == null) return 'Programada';
    final now = DateTime.now();
    if (dt.isBefore(now) && now.difference(dt).inMinutes < 90) return 'En curso';
    if (dt.difference(now).inHours < 8) return 'Confirmada';
    return 'Programada';
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'Confirmada':
        return const Color(0xFFE3F3E5);
      case 'En curso':
        return const Color(0xFFFFF3DE);
      default:
        return const Color(0xFFF1E7FF);
    }
  }
}

// ─── Aviso a alumnos ─────────────────────────────────────────────────────────

class _AvisoSheet extends StatefulWidget {
  final int claseId;
  final String claseNombre;
  final int cantidadAlumnos;
  final String estudioNombre;
  final Future<void> Function(String mensaje, String tipo) onEnviar;

  const _AvisoSheet({
    required this.claseId,
    required this.claseNombre,
    required this.cantidadAlumnos,
    required this.estudioNombre,
    required this.onEnviar,
  });

  @override
  State<_AvisoSheet> createState() => _AvisoSheetState();
}

class _AvisoSheetState extends State<_AvisoSheet> {
  final _ctrl = TextEditingController();
  bool _urgente = false;
  bool _enviando = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() => _enviando = true);
    try {
      await widget.onEnviar(
        _ctrl.text.trim(),
        _urgente ? 'urgente' : 'aviso_general',
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mensaje = _ctrl.text.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20, 12, 20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFE0DBD6),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 18),
          // Título
          const Text(
            'Avisar a alumnos',
            style: TextStyle(color: AppColors.black, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.cantidadAlumnos} alumno${widget.cantidadAlumnos != 1 ? 's' : ''} va${widget.cantidadAlumnos != 1 ? 'n' : ''} a recibir una notificación',
            style: const TextStyle(color: Color(0xFF8F877F), fontSize: 13),
          ),
          const SizedBox(height: 16),
          // Campo de texto
          StatefulBuilder(
            builder: (_, setLocal) => TextField(
              controller: _ctrl,
              maxLines: 4,
              minLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Ej: La clase de hoy se traslada al salón 2. ¡Los esperamos!',
                hintStyle: const TextStyle(color: Color(0xFFB0A8A0), fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFF7F5F2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Selector de urgencia
          Row(
            children: [
              _UrgenciaChip(
                label: '📢  Aviso general',
                selected: !_urgente,
                onTap: () => setState(() => _urgente = false),
              ),
              const SizedBox(width: 10),
              _UrgenciaChip(
                label: '🚨  Urgente',
                selected: _urgente,
                onTap: () => setState(() => _urgente = true),
              ),
            ],
          ),
          // Preview
          if (mensaje.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.estudioNombre,
                        style: const TextStyle(
                          color: Color(0xFFF7F5F2),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_urgente) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'URGENTE',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mensaje,
                    style: const TextStyle(color: Color(0xFFF7F5F2), fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          // Botón enviar
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: (_enviando || mensaje.isEmpty) ? null : _enviar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              child: _enviando
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : Text('Enviar a ${widget.cantidadAlumnos} alumno${widget.cantidadAlumnos != 1 ? 's' : ''}'),
            ),
          ),
          const SizedBox(height: 8),
          // Botón cancelar
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _enviando ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Color(0xFF8F877F))),
            ),
          ),
        ],
      ),
    );
  }
}

class _UrgenciaChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _UrgenciaChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.blackSoft : const Color(0xFFF1F1F1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF6A635D),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color background, foreground;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.background, required this.foreground, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
        child: SizedBox(
          height: 38,
          child: ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(backgroundColor: background, foregroundColor: foreground, elevation: 0, padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            child: Text(label),
          ),
        ),
      );
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SegmentButton({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: selected ? AppColors.blackSoft : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: selected ? AppColors.white : const Color(0xFF8F877F), fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      );
}

class _HorarioFijoCard extends StatelessWidget {
  final Map<String, dynamic> horario;
  final VoidCallback onEdit, onDelete;
  final ValueChanged<bool> onToggle;
  const _HorarioFijoCard({required this.horario, required this.onEdit, required this.onDelete, required this.onToggle});
  @override
  Widget build(BuildContext context) {
    final nombre = horario['nombre']?.toString() ?? 'Clase';
    final instructor = horario['instructor']?.toString();
    final hora = horario['hora_inicio']?.toString() ?? '08:00';
    final duracion = (horario['duracion_min'] as num?)?.toInt() ?? 60;
    final cupos = (horario['lugares_total'] as num?)?.toInt() ?? 12;
    final creditos = (horario['creditos'] as num?)?.toInt() ?? 10;
    final sala = horario['sala']?.toString();
    final cat = horario['categoria']?.toString();
    final activo = horario['activo'] != false;
    final extras = <String>['$duracion min', '$cupos lugares', '$creditos créditos', if (instructor != null && instructor.isNotEmpty) instructor, if (sala != null && sala.isNotEmpty) sala, if (cat != null && cat.isNotEmpty) cat];
    return Opacity(
      opacity: activo ? 1.0 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFFBFAF8), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: activo ? AppColors.blackSoft : const Color(0xFFB0A8A0), borderRadius: BorderRadius.circular(8)),
            child: Text(hora, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre, style: const TextStyle(color: AppColors.black, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(extras.join(' · '), style: const TextStyle(color: Color(0xFF8F877F), fontSize: 13)),
            ]),
          ),
          Switch(
            value: activo,
            onChanged: onToggle,
            activeThumbColor: AppColors.primary,
            activeTrackColor: AppColors.primaryLight,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, color: AppColors.primary)),
          IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error)),
        ]),
      ),
    );
  }
}

class _WeekClassChip extends StatelessWidget {
  final Map<String, dynamic> clase;
  final VoidCallback? onTap;
  const _WeekClassChip({required this.clase, this.onTap});
  @override
  Widget build(BuildContext context) {
    final isFixed = clase['_kind'] == 'fixed';
    final dt = DateTime.tryParse(clase['fecha']?.toString() ?? '');
    final hora = isFixed
        ? (clase['hora_inicio']?.toString() ?? '--:--')
        : (dt != null ? DateFormat('HH:mm').format(dt) : '--:--');
    final badgeBg = isFixed ? AppColors.primaryLight : const Color(0xFFF1F1F1);
    final badgeFg = isFixed ? AppColors.primary : const Color(0xFF6A635D);
    return GestureDetector(
      onTap: onTap,
      child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFAF8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onTap != null ? AppColors.warmBorder : AppColors.warmBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(hora, style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(clase['nombre']?.toString() ?? 'Clase', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.black, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(999)),
          child: Text(
            isFixed ? 'Horario fijo' : 'Clase cargada',
            style: TextStyle(color: badgeFg, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
      ),
    );
  }
}

class _ClaseDetalleSheet extends StatelessWidget {
  final Map<String, dynamic> clase;
  final VoidCallback onEdit, onCancel;
  final VoidCallback? onAvisar;
  const _ClaseDetalleSheet({required this.clase, required this.onEdit, required this.onCancel, this.onAvisar});

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.tryParse(clase['fecha']?.toString() ?? '');
    final hora = dt != null ? DateFormat('HH:mm').format(dt) : '--:--';
    final fechaStr = dt != null ? DateFormat("EEE d 'de' MMM yyyy", 'es').format(dt) : '—';
    final nombre = clase['nombre']?.toString() ?? 'Clase';
    final instructor = clase['instructor']?.toString();
    final total = (clase['lugares_total'] as num?)?.toInt() ?? 0;
    final disponibles = ((clase['lugares_disponibles'] ?? clase['lugares_ disponibles']) as num?)?.toInt() ?? 0;
    final ocupados = total > 0 ? (total - disponibles).clamp(0, total) : 0;
    final duracion = (clase['duracion_min'] as num?)?.toInt() ?? 60;
    final creditos = (clase['creditos'] as num?)?.toInt() ?? 10;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF7F5F2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: const Color(0xFFCCC5BD), borderRadius: BorderRadius.circular(99))),
        ),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: AppColors.blackSoft, borderRadius: BorderRadius.circular(10)),
            child: Text(hora, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(nombre, style: const TextStyle(color: AppColors.black, fontSize: 18, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 12),
        _DetailRow(icon: Icons.calendar_today_rounded, text: fechaStr),
        if (instructor != null && instructor.isNotEmpty)
          _DetailRow(icon: Icons.person_outline_rounded, text: instructor),
        _DetailRow(icon: Icons.people_outline_rounded, text: '$ocupados/$total reservas · $disponibles disponibles'),
        _DetailRow(icon: Icons.timer_outlined, text: '$duracion min · $creditos créditos'),
        const SizedBox(height: 20),
        if (onAvisar != null) ...[
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onAvisar,
              icon: const Icon(Icons.notifications_outlined, size: 16, color: Color(0xFF8F877F)),
              label: const Text('Avisar a alumnos', style: TextStyle(color: Color(0xFF8F877F))),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12)),
            ),
          ),
          const SizedBox(height: 4),
        ],
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Editar'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary), padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.cancel_outlined, size: 16),
              label: const Text('Cancelar clase'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF44336), foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _DetailRow({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, size: 16, color: const Color(0xFF8F877F)),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(color: Color(0xFF5F5953), fontSize: 14))),
    ]),
  );
}

class _UpcomingReservaCard extends StatelessWidget {
  final Map<String, dynamic> reserva;
  const _UpcomingReservaCard({required this.reserva});

  @override
  Widget build(BuildContext context) {
    final clase = reserva['clases'] as Map<String, dynamic>?;
    final estudio = clase?['estudios'] as Map<String, dynamic>?;
    final fecha = DateTime.tryParse(clase?['fecha']?.toString() ?? '');
    final codigoQr = reserva['codigo_qr']?.toString();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (codigoQr != null && codigoQr.isNotEmpty) {
            context.push('/reserva-confirmada/${Uri.encodeComponent(codigoQr)}');
          } else {
            context.go('/mis-reservas');
          }
        },
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.event_available_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clase?['nombre']?.toString() ?? 'Reserva',
                      style: const TextStyle(
                        color: AppColors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      estudio?['nombre']?.toString() ?? 'Estudio',
                      style: const TextStyle(
                        color: Color(0xFF8F877F),
                        fontSize: 13,
                      ),
                    ),
                    if (fecha != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        DateFormat('EEE d MMM · HH:mm', 'es').format(fecha),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFB3ACA5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final String title, body;
  const _InfoPanel({required this.title, required this.body});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: AppColors.black, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: Color(0xFF8F877F), fontSize: 14)),
        ]),
      );
}

// ─── Form helpers (sistema de diseno Aura para forms del panel estudio) ───
// Reusables entre _editClaseDialog, _openForm, _openGridForm.

const _kFieldFill = Color(0xFFF7F5F2);
const _kCardShadow = [
  BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 2)),
];

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _CollapsibleSectionCard extends StatelessWidget {
  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;
  const _CollapsibleSectionCard({
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  Text(
                    expanded ? 'Ocultar' : 'Mostrar más opciones',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 14),
            ...children,
          ],
        ],
      ),
    );
  }
}

InputDecoration _formInputDecoration({
  required String label,
  String? hint,
}) {
  OutlineInputBorder border([Color? color]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: color == null
            ? BorderSide.none
            : BorderSide(color: color, width: 1.5),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: _kFieldFill,
    floatingLabelBehavior: FloatingLabelBehavior.always,
    labelStyle: const TextStyle(color: Color(0xFF6E6761), fontSize: 13),
    hintStyle: const TextStyle(color: Color(0xFFB0A89F), fontSize: 14),
    border: border(),
    enabledBorder: border(),
    focusedBorder: border(AppColors.primary),
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
}

class _AuraTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final int maxLines;
  const _AuraTextField({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 15),
      decoration: _formInputDecoration(label: label, hint: hint),
    );
  }
}

class _AuraDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const _AuraDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      // ignore: deprecated_member_use
      value: value,
      items: items,
      onChanged: onChanged,
      style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 15),
      decoration: _formInputDecoration(label: label),
    );
  }
}

class _AuraTapField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  const _AuraTapField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _formInputDecoration(label: label),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Text(value,
                style: const TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 15,
                )),
          ],
        ),
      ),
    );
  }
}

class _AuraReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  final String? caption;
  const _AuraReadOnlyField({
    required this.label,
    required this.value,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: _formInputDecoration(label: label),
          child: Text(value,
              style: const TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: 15,
              )),
        ),
        if (caption != null) ...[
          const SizedBox(height: 6),
          Text(
            caption!,
            style: const TextStyle(color: AppColors.grey, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// Muestra los creditos calculados automaticamente segun pricing dinamico
/// del estudio (pico/valle/normal). Tambien muestra cuanto paga el usuario
/// y cuanto recibe el estudio (en pesos).
class _PricingPreview extends StatelessWidget {
  final Map<String, dynamic>? estudio;
  final String hora;
  final int dia; // isodow 1=lunes..7=domingo
  final String? categoria;
  final void Function(int creditos) onComputed;

  const _PricingPreview({
    required this.estudio,
    required this.hora,
    required this.dia,
    required this.categoria,
    required this.onComputed,
  });

  @override
  Widget build(BuildContext context) {
    if (estudio == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1E8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Cargando configuración de precios…',
          style: TextStyle(color: AppColors.primary, fontSize: 13),
        ),
      );
    }
    final pricing = PricingCalculator.calcular(
      estudio: estudio!,
      categoria: categoria,
      hora: hora,
      dia: dia,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => onComputed(pricing.creditos));

    final valorCredito = (estudio!['valor_credito'] as num?)?.toInt() ?? 6000;
    final comisionAura = (estudio!['comision_aura'] as num?)?.toDouble() ?? 30;
    final precioBruto = pricing.creditos * valorCredito;
    final estudioRecibe = (precioBruto * (100 - comisionAura) / 100).round();

    Color badgeColor;
    String badgeText;
    bool mostrarBadge = true;
    switch (pricing.tipo) {
      case TipoPrecio.pico:
        badgeColor = const Color(0xFFE8763A);
        badgeText = '⚡ Horario pico';
        break;
      case TipoPrecio.normal:
        badgeColor = const Color(0xFF4CAF50);
        badgeText = '🏷️ Precio reducido';
        break;
      case TipoPrecio.valle:
        badgeColor = const Color(0xFF4CAF50);
        badgeText = '🌙 Precio valle';
        break;
      case TipoPrecio.experiencia:
        badgeColor = const Color(0xFF8F877F);
        badgeText = '📅 Precio fijo';
        mostrarBadge = false; // las experiencias no usan badge "popular/reducido"
        break;
    }

    String fmtPesos(int v) {
      final s = v.toString();
      final buf = StringBuffer();
      for (int i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
        buf.write(s[i]);
      }
      return '\$$buf';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDE7E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (mostrarBadge)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    badgeText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Text(
                  badgeText,
                  style: const TextStyle(
                    color: AppColors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const Spacer(),
              Text(
                '${pricing.creditos} créditos',
                style: const TextStyle(
                  color: AppColors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'El usuario paga: ${fmtPesos(precioBruto)}',
            style: const TextStyle(color: AppColors.grey, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            'Vos recibís: ${fmtPesos(estudioRecibe)} (${(100 - comisionAura).toStringAsFixed(0)}%)',
            style: const TextStyle(
              color: AppColors.black,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

