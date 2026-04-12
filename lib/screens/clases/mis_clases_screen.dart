import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../services/estudio_admin_service.dart';
import '../../services/media_upload_service.dart';
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
  final _mediaUploadService = MediaUploadService();
  final _adminService = AdminService();
  List<Map<String, dynamic>> _clases = [], _horarios = [];
  List<String> _categorias = [];
  List<Map<String, dynamic>> _reservas = [];
  bool _loading = true, _tablaOk = true, _studio = false, _showFixed = true, _publishingWeek = false, _togglingFixed = false;
  String? _error;
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
      ),
    );
  }

  Future<void> _editClaseDialog(Map<String, dynamic> clase) async {
    final claseId = (clase['id'] as num?)?.toInt();
    if (claseId == null) return;
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: const Text('Editar clase'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: n, decoration: const InputDecoration(hintText: 'Nombre')),
            const SizedBox(height: 10),
            TextField(controller: ins, decoration: const InputDecoration(hintText: 'Instructor/a (opcional)')),
            const SizedBox(height: 10),
            TextField(controller: imagenUrl, decoration: const InputDecoration(hintText: 'Imagen principal (URL opcional)')),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final uploaded = await _subirImagenClase();
                  if (uploaded != null) {
                    imagenUrl.text = uploaded;
                    setD(() {});
                  }
                },
                icon: const Icon(Icons.image_outlined),
                label: const Text('Subir imagen principal'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: galeria,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Galería (una URL por línea)',
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final uploaded = await _subirImagenClase();
                  if (uploaded != null) {
                    galeria.text = galeria.text.trim().isEmpty
                        ? uploaded
                        : '${galeria.text.trim()}\n$uploaded';
                    setD(() {});
                  }
                },
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Agregar imagen a galería'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(controller: insDesc, maxLines: 2, decoration: const InputDecoration(hintText: 'Descripción del instructor/a (opcional)')),
            const SizedBox(height: 10),
            TextField(controller: incluye, maxLines: 2, decoration: const InputDecoration(hintText: 'Qué incluye la clase (opcional)')),
            const SizedBox(height: 10),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: fechaSel,
                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                  lastDate: DateTime.now().add(const Duration(days: 90)),
                );
                if (d != null) setD(() => fechaSel = DateTime(d.year, d.month, d.day, horaSel.hour, horaSel.minute));
              },
              child: InputDecorator(
                decoration: const InputDecoration(hintText: 'Fecha'),
                child: Row(children: [const Icon(Icons.calendar_today_rounded, size: 16), const SizedBox(width: 8), Text(DateFormat('EEE d MMM yyyy', 'es').format(fechaSel))]),
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () async {
                final t = await showTimePicker(context: ctx, initialTime: horaSel);
                if (t != null) setD(() { horaSel = t; fechaSel = DateTime(fechaSel.year, fechaSel.month, fechaSel.day, t.hour, t.minute); });
              },
              child: InputDecorator(
                decoration: const InputDecoration(hintText: 'Hora'),
                child: Row(children: [const Icon(Icons.schedule_rounded, size: 16), const SizedBox(width: 8), Text(DateFormat('HH:mm').format(DateTime(2024, 1, 1, horaSel.hour, horaSel.minute)))]),
              ),
            ),
            const SizedBox(height: 10),
            TextField(controller: cupos, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Cupos totales')),
            const SizedBox(height: 10),
            TextField(controller: cred, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Créditos')),
            const SizedBox(height: 10),
            if (categoriasDisponibles.isEmpty)
              const InputDecorator(
                decoration: InputDecoration(labelText: 'Categoría'),
                child: Text('Primero crea categorías desde Admin Aura > Config.'),
              )
            else
              DropdownButtonFormField<String>(
                value: categoriasDisponibles.contains(cat) ? cat : null,
                items: categoriasDisponibles
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setD(() => cat = v),
                decoration: const InputDecoration(labelText: 'Categoría'),
              ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              value: cierreReserva,
              items: _bookingCutoffOptions.map((v) => DropdownMenuItem(value: v, child: Text(_bookingCutoffLabel(v)))).toList(),
              onChanged: (v) => setD(() => cierreReserva = v ?? 0),
              decoration: const InputDecoration(labelText: 'Reserva disponible hasta'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar', style: TextStyle(color: AppColors.primary))),
        ],
      )),
    );
    if (ok != true || !mounted) { n.dispose(); ins.dispose(); insDesc.dispose(); incluye.dispose(); imagenUrl.dispose(); galeria.dispose(); cupos.dispose(); cred.dispose(); return; }
    try {
      final lugaresTotal = int.tryParse(cupos.text.trim()) ?? 12;
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
        'creditos': int.tryParse(cred.text.trim()) ?? 10,
        'categoria': cat,
        'reserva_cierre_minutos': cierreReserva,
      };
      await _service.editarClase(claseId, payload);
      await _loadStudio();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clase actualizada')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar: ${e.toString()}')));
    } finally {
      n.dispose(); ins.dispose(); insDesc.dispose(); incluye.dispose(); imagenUrl.dispose(); galeria.dispose(); cupos.dispose(); cred.dispose();
    }
  }

  Future<void> _confirmarCancelacion(Map<String, dynamic> clase) async {
    final claseId = (clase['id'] as num?)?.toInt();
    if (claseId == null) return;
    final nombre = clase['nombre']?.toString() ?? 'esta clase';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar clase'),
        content: Text('Â¿Cancelar "$nombre"? Se cancelarÃ¡n todas las reservas activas. Esta acciÃ³n no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No, volver')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SÃ­, cancelar', style: TextStyle(color: Color(0xFFF44336)))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.cancelarClase(claseId);
      await _loadStudio();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clase cancelada')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo cancelar: ${e.toString()}')));
    }
  }

  Future<void> _loadUser() async {
    final reservas = await _reservasService.getReservasUsuario();
    final reservasList = List<Map<String, dynamic>>.from(reservas as List);
    if (!mounted) return;
    setState(() {
      _clases = const [];
      _reservas = reservasList;
      _loading = false;
    });
  }

  Future<void> _loadStudio() async {
    try {
      // Generar clases de las prÃ³ximas 2 semanas explÃ­citamente
      // (no silenciado, para que los errores sean visibles)
      await _service.generarProximasSemanasDesdeHorarios();
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
      final clases = await _service.getClasesDeEstudio(
        from: now.subtract(const Duration(days: 1)),
        to: now.add(const Duration(days: 14)),
        limit: 200,
      );
      final horarios = await _service.getHorariosFijosDeEstudio();
      final categoriasAdmin = await _adminService.listStudyCategories();
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
    final hh = (item?['hora_inicio']?.toString() ?? '08:00').split(':');
    TimeOfDay t = TimeOfDay(hour: int.tryParse(hh.first) ?? 8, minute: int.tryParse(hh.length > 1 ? hh[1] : '0') ?? 0);
    int dur = (item?['duracion_min'] as num?)?.toInt() ?? 60;
    String? cat = item?['categoria']?.toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: Text(edit ? 'Editar horario fijo' : 'Nuevo horario fijo'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: n, decoration: const InputDecoration(hintText: 'Nombre de la clase')),
              const SizedBox(height: 10),
              if (categoriasDisponibles.isEmpty)
                const InputDecorator(
                  decoration: InputDecoration(
                    hintText: 'Categoría',
                  ),
                  child: Text(
                    'Primero crea categorias desde Admin Aura > Config.',
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  value: categoriasDisponibles.contains(cat) ? cat : null,
                  items: categoriasDisponibles
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setD(() => cat = v),
                  decoration: const InputDecoration(labelText: 'Categoría'),
                ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: d,
                items: List.generate(7, (x) => DropdownMenuItem(value: x + 1, child: Text(_dayName(x + 1)))),
                onChanged: (v) => setD(() => d = v ?? d),
                decoration: const InputDecoration(labelText: 'Día'),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () async {
                  final p = await showTimePicker(context: ctx, initialTime: t);
                  if (p != null) setD(() => t = p);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Hora de inicio'),
                  child: Row(children: [const Icon(Icons.schedule_rounded, size: 18), const SizedBox(width: 8), Text(_timeText(t))]),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: dur,
                items: const [
                  DropdownMenuItem(value: 45, child: Text('45 min')),
                  DropdownMenuItem(value: 60, child: Text('60 min')),
                  DropdownMenuItem(value: 75, child: Text('75 min')),
                  DropdownMenuItem(value: 90, child: Text('90 min')),
                ],
                onChanged: (v) => setD(() => dur = v ?? dur),
                decoration: const InputDecoration(labelText: 'Duración'),
              ),
              const SizedBox(height: 10),
              TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cupos')),
              const SizedBox(height: 10),
              TextField(controller: cr, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Créditos de la clase')),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: cierreReserva,
                items: _bookingCutoffOptions.map((v) => DropdownMenuItem(value: v, child: Text(_bookingCutoffLabel(v)))).toList(),
                onChanged: (v) => setD(() => cierreReserva = v ?? 0),
                decoration: const InputDecoration(labelText: 'Reserva disponible hasta'),
              ),
              const SizedBox(height: 10),
              TextField(controller: i, decoration: const InputDecoration(hintText: 'Instructor/a (opcional)')),
              const SizedBox(height: 10),
              TextField(
                controller: iDesc,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Descripción del instructor/a (opcional)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: incluye,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Qué incluye la clase (opcional)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(controller: imagenUrl, decoration: const InputDecoration(hintText: 'Imagen principal (URL opcional)')),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final uploaded = await _subirImagenClase();
                    if (uploaded != null) {
                      imagenUrl.text = uploaded;
                      setD(() {});
                    }
                  },
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Subir imagen principal'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: galeria,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Galería (una URL por línea)',
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final uploaded = await _subirImagenClase();
                    if (uploaded != null) {
                      galeria.text = galeria.text.trim().isEmpty
                          ? uploaded
                          : '${galeria.text.trim()}\n$uploaded';
                      setD(() {});
                    }
                  },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Agregar imagen a galería'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(controller: s, decoration: const InputDecoration(hintText: 'Sala (opcional)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(edit ? 'Guardar cambios' : 'Guardar', style: const TextStyle(color: AppColors.primary))),
          ],
        );
      }),
    );
    if (ok != true) {
      n.dispose(); i.dispose(); iDesc.dispose(); incluye.dispose(); imagenUrl.dispose(); galeria.dispose(); s.dispose(); c.dispose(); cr.dispose(); return;
    }
    if (n.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Completá al menos el nombre de la clase')));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Horario fijo actualizado')));
      } else {
        final inserted = await _service.crearHorarioFijo(payload);
        setState(() {
          _horarios = [..._horarios, inserted];
          _sortFixed();
          _showFixed = true;
          _tablaOk = true;
          _error = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Horario fijo guardado')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar: ${e.toString()}')));
      setState(() {
        _tablaOk = false;
        _error = e.toString();
      });
    } finally {
      n.dispose(); i.dispose(); iDesc.dispose(); incluye.dispose(); imagenUrl.dispose(); galeria.dispose(); s.dispose(); c.dispose(); cr.dispose();
    }
  }

  Future<void> _openGridForm() async {
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

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Crear grilla de horarios'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Esto crea muchos horarios fijos de una sola vez. Después vas a poder editar cada día y horario por separado sin tocar el resto de la grilla.',
                  style: TextStyle(color: AppColors.grey, fontSize: 13, height: 1.35),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: n,
                  decoration: const InputDecoration(labelText: 'Nombre de la clase'),
                ),
                const SizedBox(height: 10),
                if (categoriasDisponibles.isEmpty)
                  const InputDecorator(
                    decoration: InputDecoration(labelText: 'Categoría'),
                    child: Text('Primero crea categorías desde Admin Aura > Config.'),
                  )
                else
                  DropdownButtonFormField<String>(
                    value: categoriasDisponibles.contains(cat) ? cat : null,
                    items: categoriasDisponibles
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) => setD(() => cat = v),
                    decoration: const InputDecoration(labelText: 'Categoría'),
                  ),
                const SizedBox(height: 10),
                const Text(
                  'Días',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(7, (index) {
                    final dia = index + 1;
                    final selected = diasSeleccionados.contains(dia);
                    return FilterChip(
                      label: Text(_dayName(dia)),
                      selected: selected,
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
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime: horaInicio,
                          );
                          if (picked != null) setD(() => horaInicio = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Horario desde'),
                          child: Text(_timeText(horaInicio)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime: horaFin,
                          );
                          if (picked != null) setD(() => horaFin = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Horario hasta'),
                          child: Text(_timeText(horaFin)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: dur,
                  items: const [
                    DropdownMenuItem(value: 30, child: Text('30 min')),
                    DropdownMenuItem(value: 45, child: Text('45 min')),
                    DropdownMenuItem(value: 60, child: Text('60 min')),
                    DropdownMenuItem(value: 75, child: Text('75 min')),
                    DropdownMenuItem(value: 90, child: Text('90 min')),
                  ],
                  onChanged: (v) => setD(() => dur = v ?? dur),
                  decoration: const InputDecoration(labelText: 'Duración de cada clase'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: c,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Cupos'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: cr,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Créditos de la clase'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: cierreReserva,
                  items: _bookingCutoffOptions
                      .map((v) => DropdownMenuItem(value: v, child: Text(_bookingCutoffLabel(v))))
                      .toList(),
                  onChanged: (v) => setD(() => cierreReserva = v ?? 0),
                  decoration: const InputDecoration(labelText: 'Reserva disponible hasta'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: i,
                  decoration: const InputDecoration(labelText: 'Instructor/a (opcional)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: iDesc,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Descripción del instructor/a (opcional)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: incluye,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Qué incluye la clase (opcional)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: imagenUrl,
                  decoration: const InputDecoration(labelText: 'Imagen principal (URL opcional)'),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final uploaded = await _subirImagenClase();
                      if (uploaded != null) {
                        imagenUrl.text = uploaded;
                        setD(() {});
                      }
                    },
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Subir imagen principal'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: galeria,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Galería (una URL por línea)',
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final uploaded = await _subirImagenClase();
                      if (uploaded != null) {
                        galeria.text = galeria.text.trim().isEmpty
                            ? uploaded
                            : '${galeria.text.trim()}\n$uploaded';
                        setD(() {});
                      }
                    },
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Agregar imagen a galería'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: s,
                  decoration: const InputDecoration(labelText: 'Sala (opcional)'),
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
              child: const Text(
                'Crear grilla',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
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
        SnackBar(content: Text('Grilla creada: $creados horarios fijos')),
      );
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
      final start = _weekStart(_weekAnchor);
      final firstWeek = await _service.generarClasesDesdeHorarios(
        weekStart: start,
      );
      final secondWeek = await _service.generarClasesDesdeHorarios(
        weekStart: start.add(const Duration(days: 7)),
      );
      final result = {
        'creadas': (firstWeek['creadas'] ?? 0) + (secondWeek['creadas'] ?? 0),
        'omitidas': (firstWeek['omitidas'] ?? 0) + (secondWeek['omitidas'] ?? 0),
      };
      await _loadStudio();
      if (!mounted) return;
      final creadas = result['creadas'] ?? 0;
      final omitidas = result['omitidas'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Semana publicada: $creadas clases creadas${omitidas > 0 ? ', $omitidas ya existían o se omitieron' : ''}.',
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

  @override
  Widget build(BuildContext context) {
    final dayClasses = _reservedClassesOn(_selectedDay);
    final upcomingReservas = _proximasReservas;
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
                        SizedBox(
                          height: 40,
                          child: OutlinedButton(
                            onPressed: _openGridForm,
                            child: const Text('Crear grilla'),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      SizedBox(
                        height: 40,
                        child: ElevatedButton(
                          onPressed: _studio ? () => _openForm() : () => context.go('/explorar'),
                          child: Text(_studio ? 'Nuevo horario' : 'Nueva clase'),
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
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(child: Text('No hay clases cargadas para este dÃ­a', style: TextStyle(color: Color(0xFF8F877F)))),
                        )
                      else
                        ...dayClasses.map((c) => Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _StudioClassCard(clase: c, studioMode: _studio),
                            )),
                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'PrÃ³ximas reservas',
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
                            'TodavÃ­a no tenÃ©s reservas prÃ³ximas.',
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
              _WeekHeader('MIÃ‰'),
              _WeekHeader('JUE'),
              _WeekHeader('VIE'),
              _WeekHeader('SÃB'),
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
                      'TocÃ¡ para elegir otra semana',
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
          _WeekHeader('LUN'), _WeekHeader('MAR'), _WeekHeader('MIÃ‰'), _WeekHeader('JUE'), _WeekHeader('VIE'), _WeekHeader('SÃB'), _WeekHeader('DOM')
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
      return const [_InfoPanel(title: 'TodavÃ­a no hay horarios fijos', body: 'PodÃ©s cargar una grilla semanal tipo Deportnet con el botÃ³n "Nuevo horario".')];
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
            label: Text(_publishingWeek ? 'Generando...' : 'Generar semana'),
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
      return dias == 1 ? 'Hasta 1 dÃ­a antes' : 'Hasta $dias dÃ­as antes';
    }
    if (minutes % 60 == 0) {
      final horas = minutes ~/ 60;
      return horas == 1 ? 'Hasta 1 hora antes' : 'Hasta $horas horas antes';
    }
    return 'Hasta $minutes min antes';
  }
  String _shortDay(int d) => const {1: 'Lun', 2: 'Mar', 3: 'MiÃ©', 4: 'Jue', 5: 'Vie', 6: 'SÃ¡b', 7: 'Dom'}[d] ?? 'Lun';
  String _dayName(int d) => const {1: 'Lunes', 2: 'Martes', 3: 'MiÃ©rcoles', 4: 'Jueves', 5: 'Viernes', 6: 'SÃ¡bado', 7: 'Domingo'}[d] ?? 'Lunes';
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
  const _StudioClassCard({required this.clase, required this.studioMode});
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
        const Text('OcupaciÃ³n', style: TextStyle(color: Color(0xFF8F877F), fontSize: 13)),
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
            _ActionButton(label: 'Cancelar', background: const Color(0xFFF44336), foreground: AppColors.white, onTap: () {}),
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
              Text(extras.join(' Â· '), style: const TextStyle(color: Color(0xFF8F877F), fontSize: 13)),
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
  const _ClaseDetalleSheet({required this.clase, required this.onEdit, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.tryParse(clase['fecha']?.toString() ?? '');
    final hora = dt != null ? DateFormat('HH:mm').format(dt) : '--:--';
    final fechaStr = dt != null ? DateFormat("EEE d 'de' MMM yyyy", 'es').format(dt) : 'â€”';
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
                        DateFormat('EEE d MMM Â· HH:mm', 'es').format(fecha),
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





