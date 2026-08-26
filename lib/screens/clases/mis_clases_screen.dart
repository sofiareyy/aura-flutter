import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/liquidacion.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../services/aviso_alumnos_service.dart';
import '../../services/clases_service.dart';
import '../../utils/pricing.dart';
import '../../models/estudio.dart';
import '../../services/estudio_admin_service.dart';
import '../../widgets/categorias_checklist.dart';
import '../../services/media_upload_service.dart';
import '../../services/notificaciones_service.dart';
import '../../services/reservas_service.dart';
import '../../services/admin_service.dart';

const String _kPrefsClasesGridView = 'mis_clases_grid_view';
const String _kPrefsClasesShowPast = 'mis_clases_show_past';

/// Texto que ve el estudio cuando algo de base falla. El detalle técnico va
/// a debugPrint: un estudio no puede hacer nada con un P0001 en pantalla, y
/// encima asusta (YN Pilates, 24/8). Ojo: NO tapar el error, solo traducirlo.
const String kMsgErrorCarga =
    'Hubo un problema al cargar. Escribinos a aura.hola.app@gmail.com';

/// Mensaje legible de un error: los de la base ya vienen en castellano
/// (candados, guards), el resto se traduce a un texto genérico.
String _mensajeDeError(Object e) {
  if (e is PostgrestException) return e.message;
  final t = e.toString();
  return t.length > 160 || t.contains('Exception') ? 'Hubo un problema' : t;
}

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
  // M1: Próximas (fecha >= hoy AR) vs Pasadas en la vista "Clases cargadas".
  bool _showPast = false;
  // M3: vista lista (default) vs grilla 2 col en "Clases cargadas".
  bool _gridView = false;
  // Modo selección múltiple para cancelar varias clases a la vez.
  bool _seleccionMultiple = false;
  final Set<int> _seleccionadas = {};
  bool _cancelandoLote = false;
  /// Ventana de días que se muestra en "Próximas". null = todo lo cargado.
  /// La grilla publica ~3 meses, así que sin esto la lista es inmanejable,
  /// pero acotarla por defecto era lo que hacía "desaparecer" clases.
  int? _rangoDias = 30;

  // ── Historial (solapa "Pasadas") ──────────────────────────────────────────
  // Las clases pasadas NO se borran ni se archivan con un flag: se filtran por
  // fecha. Pero la carga principal solo trae 30 días para atrás, así que el
  // historial se pide aparte, mes a mes y bajo demanda. Así el estudio llega a
  // cualquier mes sin traerse años de datos a memoria.
  DateTime _mesHistorial = DateTime(DateTime.now().year, DateTime.now().month);
  List<Map<String, dynamic>> _clasesHistorial = [];
  bool _cargandoHistorial = false;
  Map<String, dynamic>? _estudio;
  String? _error;
  String? _estudioNombre;
  // F5 — vista por profe: lista de profes del estudio (solo la carga el admin),
  // filtro "Ver por profe" y datos del profe logueado para el badge "Tu clase".
  List<Map<String, dynamic>> _profesEstudio = [];
  String? _filtroProfe;
  bool _esProfe = false;
  String _miNombre = '';
  DateTime _selectedDay = DateTime.now(), _weekAnchor = DateTime.now(), _monthAnchor = DateTime.now();

  List<String> get _profeNombres => _profesEstudio
      .map((p) => (p['nombre']?.toString() ?? '').trim())
      .where((n) => n.isNotEmpty)
      .toList();

  String _normNombre(dynamic v) => (v?.toString() ?? '').trim().toLowerCase();

  bool _matchInstructor(dynamic instructor, String? profeNombre) {
    if (profeNombre == null || profeNombre.trim().isEmpty) return true;
    return _normNombre(instructor) == _normNombre(profeNombre);
  }

  bool _esMiClase(dynamic instructor) =>
      _esProfe &&
      _miNombre.isNotEmpty &&
      _normNombre(instructor) == _normNombre(_miNombre);

  /// 'HH:mm' para pasarle la hora a [PricingCalculator].
  static String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Precio calculado para un día (isodow) y hora concretos, según la config
  /// del estudio. El estudio NO elige este número: lo define Aura desde el
  /// backoffice (modo fijo o rango con grilla pico/valle).
  /// "🌙 08:30 · 12 cr": la hora con el precio que le toca en SU franja, con
  /// la misma regla que después aplica el trigger de la base. Sin precio
  /// configurado muestra solo la hora.
  String _etiquetaHorario(int dia, TimeOfDay t) {
    final p = _precioDe(dia, t);
    final hhmm = _hhmm(t);
    if (!p.configurado) return hhmm;
    final ico = switch (p.tipo) {
      TipoPrecio.valle => '🌙 ',
      TipoPrecio.pico => '⚡ ',
      _ => '',
    };
    return '$ico$hhmm · ${p.creditos} cr';
  }

  PricingResult _precioDe(int dia, TimeOfDay hora) =>
      PricingCalculator.calcular(
        estudio: _estudio,
        hora: _hhmm(hora),
        dia: dia,
      );

  /// Créditos finales a guardar.
  ///
  ///  - workshop: el controller trae PESOS que el estudio quiere recibir; los
  ///    créditos los deriva Aura. Ver [creditosDeWorkshop].
  ///  - clase normal: los fija la config del estudio según el horario. Si el
  ///    estudio todavía no tiene precio configurado caemos a lo que haya en el
  ///    controller (valor guardado o el default), para no dejar la clase en 0.
  ///
  /// La base vuelve a fijar el precio igual con `trg_clases_fija_precio`; esto
  /// es solo para que el payload viaje coherente y la UI no parpadee.
  int _creditosFinal(
    TextEditingController ctrl,
    String tipo, {
    required int dia,
    required TimeOfDay hora,
  }) {
    if (tipo == 'workshop') {
      return Liquidacion.creditosDeWorkshop(_montoWorkshop(ctrl), _estudio);
    }
    final calculado = _precioDe(dia, hora).creditos;
    if (calculado != null) return calculado;
    return int.tryParse(ctrl.text.trim()) ?? 10;
  }

  /// Pesos tipeados en el campo de workshop, tolerando puntos y comas de miles.
  int _montoWorkshop(TextEditingController ctrl) =>
      int.tryParse(ctrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  @override
  void initState() {
    super.initState();
    _cargarPreferenciasVista();
  }

  Future<void> _cargarPreferenciasVista() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final grid = prefs.getBool(_kPrefsClasesGridView) ?? false;
      final past = prefs.getBool(_kPrefsClasesShowPast) ?? false;
      if (mounted) {
        setState(() {
          _gridView = grid;
          _showPast = past;
        });
        // Si la preferencia guardada abre directo en el historial, hay que
        // pedirlo: la carga principal solo trae 30 días para atrás.
        if (past) _cargarHistorial(_mesHistorial);
      }
    } catch (_) {}
  }

  Future<void> _guardarPreferenciaGrid(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrefsClasesGridView, value);
    } catch (_) {}
  }

  Future<void> _guardarPreferenciaPasadas(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrefsClasesShowPast, value);
    } catch (_) {}
  }

  /// "Ahora" en hora Argentina como local-naive. Las fechas en DB estan
  /// guardadas como naive en hora AR, por eso comparamos contra esto.
  DateTime _ahoraAr() {
    final u = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second);
  }

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

  /// Catálogo para los selectores. Solo las ACTIVAS del backoffice: el
  /// estudio no crea categorías, solo asigna de esa lista. Se suman las que
  /// la clase ya tenía aunque hayan sido dadas de baja, para no borrárselas
  /// sin querer al editar.
  Future<List<String>> _loadCategoriasDisponibles([
    List<String> actuales = const [],
  ]) async {
    final categoriasAdmin = await _adminService.listStudyCategories();
    final categorias = <String>{
      ...categoriasAdmin.where((item) => item.trim().isNotEmpty),
      ...actuales.where((item) => item.trim().isNotEmpty),
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

  /// `_studio` dice "estoy en una ruta /estudio", NO "tengo permiso de
  /// editar". Como /estudio/clases es la única ruta que una profe puede
  /// abrir, gatear la escritura con `_studio` se la habilitaba entera:
  /// crear, editar, borrar y avisar. La escritura va contra esto.
  ///
  /// `_studio` se sigue usando para decidir qué datos cargar y cómo
  /// mostrarlos: la profe sí tiene que ver las clases del estudio.
  /// Acciones exclusivas de admin/dueña: borrar clases, workshops, grillas,
  /// avisos, datos bancarios, gestión de accesos, precio libre.
  bool get _puedeEditar => _studio && !_esProfe;

  /// Opción A: crear y editar clases individuales. Lo puede hacer cualquiera
  /// del panel del estudio, incluida la profe. El backend (RLS + trigger)
  /// impide igual que la profe borre o cree workshops.
  bool get _puedeGestionarClases => _studio;

  /// Configuración acotada para la profe: hoy solo expone "Salir del estudio".
  Future<void> _mostrarConfiguracionProfe() async {
    final estudioNombre = _estudioNombre ?? 'el estudio';
    final uid = Supabase.instance.client.auth.currentUser?.id;
    // Valor actual del toggle de notificaciones de reservas (F6).
    bool notifReservas = true;
    if (uid != null) {
      try {
        final row = await Supabase.instance.client
            .from('usuarios')
            .select('notifs_reservas_profe')
            .eq('id', uid)
            .maybeSingle();
        notifReservas = (row?['notifs_reservas_profe'] as bool?) ?? true;
      } catch (_) {}
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text(
                'Configuración',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.black,
                ),
              ),
            ),
            SwitchListTile(
              value: notifReservas,
              activeThumbColor: AppColors.primary,
              secondary: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.notifications_active_outlined,
                    color: AppColors.primary, size: 18),
              ),
              title: const Text(
                'Avisarme nuevas reservas',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Cuando alguien se anota en tus clases.',
                style: TextStyle(fontSize: 12, color: AppColors.grey),
              ),
              onChanged: (v) async {
                setSheet(() => notifReservas = v);
                if (uid != null) {
                  try {
                    await Supabase.instance.client
                        .from('usuarios')
                        .update({'notifs_reservas_profe': v}).eq('id', uid);
                  } catch (_) {}
                }
              },
            ),
            const Divider(height: 1, indent: 20, endIndent: 20),
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.logout_rounded,
                    color: AppColors.error, size: 18),
              ),
              title: Text(
                'Salir del estudio $estudioNombre',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.error,
                ),
              ),
              subtitle: const Text(
                'Perdés el acceso al panel del estudio.',
                style: TextStyle(fontSize: 12, color: AppColors.grey),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _salirDelEstudio();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      ),
    );
  }

  /// La profe abandona el estudio: elimina su vínculo en estudio_admins (el RPC
  /// además baja su rol de 'profe' a 'usuario' si no le quedan estudios) y
  /// vuelve a la home como usuaria normal.
  Future<void> _salirDelEstudio() async {
    final estudioNombre = _estudioNombre ?? 'el estudio';
    final userId = Supabase.instance.client.auth.currentUser?.id;
    var estudioId = (_estudio?['id'] as num?)?.toInt();
    estudioId ??= await _service.getCurrentStudioId();
    if (userId == null || estudioId == null) return;

    if (!mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salir del estudio'),
        content: Text(
          '¿Querés salir de $estudioNombre?\n'
          'Perdés el acceso al panel del estudio.',
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
            child: const Text('Sí, salir'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    final ok = await _service.removeEstudioAdminAccess(
      estudioId: estudioId,
      usuarioId: userId,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo salir del estudio.')),
      );
      return;
    }

    // Refrescar el rol en el provider antes de navegar para que el shell no
    // vuelva a tratarla como profe.
    await context.read<AppProvider>().refrescarUsuario();
    if (!mounted) return;
    context.go('/home');
  }

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
        puedeEditar: _puedeEditar,
        enEspera: _enEspera[claseId] ?? 0,
        onEdit: () async {
          Navigator.pop(context);
          await _editClaseDialog(clase);
        },
        onCancel: () async {
          Navigator.pop(context);
          await _confirmarCancelacion(clase);
        },
        onReactivar: () async {
          Navigator.pop(context);
          await _reactivarClase(clase);
        },
        onAvisar: _puedeEditar
            ? () async {
                Navigator.pop(context);
                await _mostrarAvisoSheet(clase);
              }
            : null,
      ),
    );
  }

  /// FIX 6 — Menú del "+": crear clase o mandar aviso.
  ///
  /// Antes "avisar" solo estaba en el submenú de cada clase, que es donde
  /// nadie lo buscaba. Ahora vive al lado de "nueva clase", que es el lugar
  /// al que el estudio va cuando quiere hacer algo.
  Future<void> _abrirMenuCrear() async {
    if (!_puedeGestionarClases) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFE0DBD6),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 14),
            _OpcionTile(
              icon: Icons.add_circle_outline,
              label: 'Nueva clase',
              onTap: () {
                Navigator.pop(ctx);
                _openForm();
              },
            ),
            // Workshops, grillas y avisos son solo de admin/dueña. La profe
            // (Opción A) solo carga clases individuales.
            if (_puedeEditar) ...[
              _OpcionTile(
                icon: Icons.celebration_outlined,
                label: 'Nuevo workshop / experiencia',
                onTap: () {
                  Navigator.pop(ctx);
                  _openForm(null, 'workshop');
                },
              ),
              _OpcionTile(
                icon: Icons.grid_view_rounded,
                label: 'Crear grilla',
                onTap: () {
                  Navigator.pop(ctx);
                  _openGridForm();
                },
              ),
              _OpcionTile(
                icon: Icons.campaign_outlined,
                label: 'Mandar aviso',
                onTap: () {
                  Navigator.pop(ctx);
                  _abrirFlujoAviso();
                },
              ),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  /// Abre el flujo de aviso ya apuntando a una clase concreta.
  Future<void> _mostrarAvisoSheet(Map<String, dynamic> clase) async {
    final claseId = (clase['id'] as num?)?.toInt();
    if (claseId == null) return;
    await _abrirFlujoAviso(preseleccionadas: {claseId});
  }

  /// FIX 6 — Flujo de aviso: elegir clase(s) -> escribir -> enviar.
  ///
  /// Vive en el menú "+" y no escondido en el submenú de cada clase, y
  /// permite mandar el mismo aviso a varias clases de una (tope 10). Quien
  /// esté anotada en más de una recibe uno solo: el dedup lo hace el RPC.
  Future<void> _abrirFlujoAviso({Set<int> preseleccionadas = const {}}) async {
    // Guarda de permiso: la profe no avisa. Va acá y no solo en la UI para
    // cubrir cualquier camino de navegación que no haya quedado gateado.
    if (!_puedeEditar) return;

    final estudioId = (_estudio?['id'] as num?)?.toInt();
    if (estudioId == null) return;

    // Solo clases futuras: avisar sobre una que ya pasó no tiene sentido.
    final ahora = _ahoraAr();
    final candidatas = _clases.where((c) {
      final f = DateTime.tryParse(c['fecha']?.toString() ?? '');
      return f != null && f.isAfter(ahora);
    }).toList()
      ..sort((a, b) {
        final fa = DateTime.tryParse(a['fecha']?.toString() ?? '');
        final fb = DateTime.tryParse(b['fecha']?.toString() ?? '');
        if (fa == null || fb == null) return 0;
        return fa.compareTo(fb);
      });

    if (candidatas.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No tenés clases próximas para avisar.'),
        ),
      );
      return;
    }

    final cupo = await _avisoService.cupoMensual(estudioId);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _AvisoSheet(
        clases: candidatas,
        preseleccionadas: preseleccionadas,
        estudioNombre: _estudioNombre ?? 'Aura',
        cupoInicial: cupo,
        contarAlumnos: _avisoService.contarAlumnosDeClases,
        onEnviar: (claseIds, mensaje, tipo) =>
            _avisoService.enviarAviso(
          claseIds: claseIds,
          mensaje: mensaje,
          tipo: tipo,
        ),
      ),
    );
  }

  Future<void> _editClaseDialog(Map<String, dynamic> clase) async {
    if (clase['cancelada'] == true) {
      _snack('Esta clase está cancelada. Reactivala primero si querés editarla.');
      return;
    }
    // Opción A: editar clase individual lo puede hacer la profe. El borrado y
    // los workshops quedan bloqueados por el backend.
    if (!_puedeGestionarClases) return;
    final claseId = (clase['id'] as num?)?.toInt();
    if (claseId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final categoriasDisponibles =
        await _loadCategoriasDisponibles(_parseCategorias(clase));
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
    final tipoClase = clase['tipo']?.toString() ?? 'clase';
    if (tipoClase == 'workshop') {
      // El campo de workshop se edita en PESOS, no en créditos: convertimos
      // el precio guardado de vuelta al monto que recibe el estudio.
      cred.text =
          Liquidacion.montoEstudioDeWorkshop(
              (clase['creditos'] as num?)?.toInt() ?? 0, _estudio)
              .toString();
    }
    // Las clases normales ya no precargan el campo: el precio lo calcula
    // _PrecioCalculadoField a partir de la fecha/hora elegida.
    // null = hereda el default del estudio (no forzamos 0).
    int? cierreReserva = (clase['reserva_cierre_minutos'] as num?)?.toInt();
    // Una clase puede tener varias categorías (máx 5). Son etiquetas
    // descriptivas para que el usuario filtre: NO afectan el precio.
    final cats = _parseCategorias(clase);
    final fechaOrig = DateTime.tryParse(clase['fecha']?.toString() ?? '');
    DateTime fechaSel = fechaOrig ?? DateTime.now();
    TimeOfDay horaSel = TimeOfDay(hour: fechaSel.hour, minute: fechaSel.minute);
    if (!mounted) return;
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
                              _InstructorField(
                                controller: ins,
                                profes: _profeNombres,
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
                                  final t = await _pickHora24(ctx, horaSel);
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
                              _AuraDropdown<int?>(
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
                                    setD(() => cierreReserva = v),
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
                                    'Todavía no hay categorías disponibles. Escribinos y las '
                                    'configuramos para tu estudio.',
                                    style: TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 13),
                                  ),
                                )
                              else
                                CategoriasChecklist(
                                  label: 'Categorías (máx '
                                      '$kMaxCategoriasClase)',
                                  disponibles: categoriasDisponibles,
                                  seleccionadas: cats,
                                  onToggle: (c, marcada) => setD(() {
                                    if (marcada) {
                                      if (cats.length >=
                                          kMaxCategoriasClase) {
                                        return;
                                      }
                                      if (!cats.contains(c)) cats.add(c);
                                    } else {
                                      cats.remove(c);
                                    }
                                  }),
                                ),
                              const SizedBox(height: 12),
                              if (tipoClase == 'workshop')
                                _WorkshopPrecioField(
                                  controller: cred,
                                  estudio: _estudio,
                                  onChanged: () => setD(() {}),
                                )
                              else
                                _PrecioCalculadoField(
                                  estudio: _estudio,
                                  dia: fechaSel.weekday,
                                  hora: horaSel,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Card 5: Detalles adicionales (colapsable)
                          _SectionCard(
                            title: 'Descripción, sala y fotos',
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
                                label: 'Descripción de la clase',
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
        'creditos': _creditosFinal(cred, tipoClase,
            dia: fechaSel.weekday, hora: horaSel),
        // Solo incluir categoria si tiene valor — evita pisar con null si la
        // columna tiene constraint NOT NULL o si el dropdown quedo vacio.
        'categorias': cats,
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

  /// Vuelve reservable una clase cancelada. Las reservas que ya se devolvieron
  /// quedan como estaban (cancelada_por_estudio): las alumnas se anotan de nuevo.
  Future<void> _reactivarClase(Map<String, dynamic> clase) async {
    if (!_puedeEditar) return;
    final claseId = (clase['id'] as num?)?.toInt();
    if (claseId == null || clase['cancelada'] != true) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Reactivar esta clase?'),
        content: const Text('Vuelve a aparecer para las alumnas y se puede reservar. Las que ya recibieron sus créditos tienen que anotarse de nuevo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF43A047), foregroundColor: Colors.white),
            child: const Text('Reactivar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.reactivarClase(claseId);
      await _loadStudio();
      _snack('Clase reactivada: ya se puede reservar.');
    } catch (e) {
      debugPrint('[reactivarClase] $e');
      _snack('No se pudo reactivar la clase. Escribinos a aura.hola.app@gmail.com');
    }
  }

  Future<void> _confirmarCancelacion(Map<String, dynamic> clase) async {
    // Guarda de permiso: la profe no crea, edita, borra ni avisa.
    // Va acá y no solo en la UI para cubrir cualquier camino de
    // navegación que no haya quedado gateado.
    if (!_puedeEditar) return;
    final claseId = (clase['id'] as num?)?.toInt();
    if (claseId == null) return;
    if (clase['cancelada'] == true) {
      _snack('Esta clase ya está cancelada.');
      return;
    }
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

  /// Cuánta gente espera lugar en cada clase futura, por `clase_id`. Vacío
  /// mientras no haya nadie anotada (que es el caso hoy en todos los estudios).
  Map<int, int> _enEspera = const {};

  Future<void> _loadStudio() async {
    try {
      // Auto-mantener 3 meses (13 semanas) de clases concretas a partir de
      // los horarios fijos activos. La funcion es idempotente: salta las que
      // ya existen. Asi el "horario fijo activo" siempre coincide con clases
      // visibles para los usuarios, sin que el estudio tenga que apretar
      // "Generar 3 meses" manualmente.
      await _service.generarProximasSemanasDesdeHorarios(weeks: kGrillaSemanas);
    } catch (e) {
      if (mounted) {
        debugPrint('[generarProximasSemanas] $e');
        setState(() {
          _tablaOk = false;
          _error = kMsgErrorCarga;
        });
      }
    }

    try {
      final now = DateTime.now().toUtc().subtract(const Duration(hours: 3));
      final results = await Future.wait([
        // La grilla genera kGrillaSemanas semanas hacia adelante. Antes acá
        // pedíamos 14 días con tope de 200 filas, así que ~7 semanas de clases
        // existían pero eran invisibles en el panel. Traemos el rango completo
        // (+1 semana de margen) y 30 días para atrás para la solapa "Pasadas".
        _service.getClasesDeEstudio(
          from: now.subtract(const Duration(days: 30)),
          to: now.add(const Duration(days: (kGrillaSemanas + 1) * 7)),
          limit: 3000,
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
      // F5: profes del estudio (para el filtro y el dropdown de instructor).
      // La RPC devuelve [] si el caller no es admin real (ej. una profe).
      final estudioIdProfes = (estudio?['id'] as num?)?.toInt();
      final profes = estudioIdProfes != null
          ? await _service.listProfes(estudioIdProfes)
          : <Map<String, dynamic>>[];
      final enEspera = estudioIdProfes != null
          ? await _service.getListaEsperaDelEstudio(estudioIdProfes)
          : const <int, int>{};
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
        _profesEstudio = profes;
        _enEspera = enEspera;
        // Si el filtro apuntaba a una profe que ya no está, lo reseteamos.
        if (_filtroProfe != null && !_profeNombres.contains(_filtroProfe)) {
          _filtroProfe = null;
        }
        _loading = false;
        _tablaOk = true;
        _error = null;
      });
      // El historial vive en su propia lista (se pide por mes), así que un
      // refresco general no lo actualiza solo. Si el estudio está parado ahí
      // —por ejemplo, después de borrar clases— lo volvemos a pedir.
      if (_showPast) await _cargarHistorial(_mesHistorial);
    } catch (e) {
      debugPrint('[_loadStudio] $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _tablaOk = false;
        _error = kMsgErrorCarga;
      });
    }
  }


  Future<void> _openForm(
      [Map<String, dynamic>? item, String? initialTipo]) async {
    // Opción A: crear/editar clase individual lo puede hacer la profe también.
    // Borrar / workshops los frena el backend (RLS + trigger).
    if (!_puedeGestionarClases) return;
    final edit = item != null;
    final messenger = ScaffoldMessenger.of(context);
    List<String> categoriasDisponibles;
    try {
      categoriasDisponibles = await _loadCategoriasDisponibles(
        item == null ? const [] : _parseCategorias(item),
      );
    } catch (e) {
      debugPrint('[_openForm categorias] $e');
      _snack(kMsgErrorCarga);
      return;
    }
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
    // Campos exclusivos de workshops/eventos (FIX 8).
    final descCtrl = TextEditingController(
      text: item?['descripcion']?.toString() ?? '',
    );
    final dirCtrl = TextEditingController(
      text: item?['direccion']?.toString() ?? '',
    );
    final c = TextEditingController(text: ((item?['lugares_total'] as num?)?.toInt() ?? 12).toString());
    final cr = TextEditingController(text: ((item?['creditos'] as num?)?.toInt() ?? 10).toString());
    // null = hereda el default del estudio (no forzamos 0).
    int? cierreReserva = (item?['reserva_cierre_minutos'] as num?)?.toInt();
    int d = (item?['dia_semana'] as num?)?.toInt() ?? 1;
    // Clase individual (solo al crear): fecha concreta del evento único.
    final nowLocal = DateTime.now();
    DateTime fecha = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final hh = (item?['hora_inicio']?.toString() ?? '08:00').split(':');
    TimeOfDay t = TimeOfDay(hour: int.tryParse(hh.first) ?? 8, minute: int.tryParse(hh.length > 1 ? hh[1] : '0') ?? 0);
    int dur = (item?['duracion_min'] as num?)?.toInt() ?? 60;
    final cats = item == null
        ? <String>[]
        : _parseCategorias(item);
    // Tipo de clase: 'clase' normal o 'workshop' (evento). Solo elegible al
    // crear una clase individual (no en horarios fijos ni edición).
    String tipo = item?['tipo']?.toString() ?? initialTipo ?? 'clase';
    if (tipo == 'workshop') {
      cr.text =
          Liquidacion.montoEstudioDeWorkshop(
              (item?['creditos'] as num?)?.toInt() ?? 0, _estudio)
              .toString();
    }
    // Las clases normales no precargan el campo: el precio lo calcula
    // _PrecioCalculadoField según el día y la hora elegidos.
    //
    // Editando un horario fijo el día es `d`; creando una clase individual
    // sale de la fecha concreta del evento.
    int diaPrecio() => edit ? d : fecha.weekday;
    // Organizadores del workshop: filas de {nombre, instagram}.
    final orgNombreCtrls = <TextEditingController>[];
    final orgInstaCtrls = <TextEditingController>[];
    for (final o in (item?['organizadores'] as List?) ?? const []) {
      final m = o as Map?;
      orgNombreCtrls
          .add(TextEditingController(text: m?['nombre']?.toString() ?? ''));
      orgInstaCtrls
          .add(TextEditingController(text: m?['instagram']?.toString() ?? ''));
    }
    if (orgNombreCtrls.isEmpty) {
      orgNombreCtrls.add(TextEditingController());
      orgInstaCtrls.add(TextEditingController());
    }
    void disposeAll() {
      n.dispose(); i.dispose(); iDesc.dispose(); incluye.dispose();
      imagenUrl.dispose(); galeria.dispose(); s.dispose(); c.dispose();
      cr.dispose(); descCtrl.dispose(); dirCtrl.dispose();
      for (final x in orgNombreCtrls) { x.dispose(); }
      for (final x in orgInstaCtrls) { x.dispose(); }
    }
    if (!mounted) return;
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
                            _SectionCard(
                              title: 'Tipo',
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _TipoOption(
                                        label: 'Clase',
                                        icon: Icons.fitness_center_rounded,
                                        selected: tipo == 'clase',
                                        onTap: () =>
                                            setD(() => tipo = 'clase'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _TipoOption(
                                        label: 'Workshop / Experiencia',
                                        icon: Icons.celebration_rounded,
                                        selected: tipo == 'workshop',
                                        onTap: () => setD(() {
                                          tipo = 'workshop';
                                          // El campo pasa de créditos a
                                          // pesos: lo vaciamos para que no
                                          // se lea "10" como $10.
                                          cr.clear();
                                          // duración por defecto para eventos
                                          if (![60, 90, 120, 150, 180, 240]
                                              .contains(dur)) {
                                            dur = 120;
                                          }
                                        }),
                                      ),
                                    ),
                                  ],
                                ),
                                if (tipo == 'workshop') ...[
                                  const SizedBox(height: 10),
                                  // A propósito no se menciona ningún % de
                                  // comisión: la maneja Aura desde el
                                  // backoffice y el estudio solo carga precio.
                                  const Text(
                                    'Ponés en pesos cuánto querés recibir por el '
                                    'workshop, sin restricción. Va a aparecer en '
                                    'la sección Experiencias, no entre las clases.',
                                    style: TextStyle(
                                      color: AppColors.grey,
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ],
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
                              _InstructorField(
                                controller: i,
                                profes: _profeNombres,
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
                                  final p = await _pickHora24(ctx, t);
                                  if (p != null) setD(() => t = p);
                                },
                              ),
                              const SizedBox(height: 12),
                              _AuraDropdown<int>(
                                label: 'Duración',
                                value: dur,
                                items: (tipo == 'workshop'
                                        ? const [60, 90, 120, 150, 180, 240]
                                        : const [45, 60, 75, 90])
                                    .map((m) => DropdownMenuItem(
                                          value: m,
                                          child: Text(_durLabel(m)),
                                        ))
                                    .toList(),
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
                              _AuraDropdown<int?>(
                                label: 'Cierre de reservas',
                                value: cierreReserva,
                                items: _bookingCutoffOptions
                                    .map((v) => DropdownMenuItem(
                                          value: v,
                                          child: Text(_bookingCutoffLabel(v)),
                                        ))
                                    .toList(),
                                onChanged: (v) =>
                                    setD(() => cierreReserva = v),
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
                                    'Todavía no hay categorías disponibles. Escribinos y las '
                                    'configuramos para tu estudio.',
                                    style: TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 13),
                                  ),
                                )
                              else
                                CategoriasChecklist(
                                  label: 'Categorías (máx '
                                      '$kMaxCategoriasClase)',
                                  disponibles: categoriasDisponibles,
                                  seleccionadas: cats,
                                  onToggle: (c, marcada) => setD(() {
                                    if (marcada) {
                                      if (cats.length >=
                                          kMaxCategoriasClase) {
                                        return;
                                      }
                                      if (!cats.contains(c)) cats.add(c);
                                    } else {
                                      cats.remove(c);
                                    }
                                  }),
                                ),
                              const SizedBox(height: 12),
                              if (tipo == 'workshop')
                                _WorkshopPrecioField(
                                  controller: cr,
                                  estudio: _estudio,
                                  onChanged: () => setD(() {}),
                                )
                              else
                                _PrecioCalculadoField(
                                  estudio: _estudio,
                                  dia: diaPrecio(),
                                  hora: t,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (tipo == 'workshop') ...[
                            _SectionCard(
                              title: 'Organizadores',
                              children: [
                                const Text(
                                  'Nombre + Instagram de cada organizador/a. '
                                  'Los @ se muestran clickeables en la app.',
                                  style: TextStyle(
                                    color: AppColors.grey,
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                for (int idx = 0;
                                    idx < orgNombreCtrls.length;
                                    idx++) ...[
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: _AuraTextField(
                                          controller: orgNombreCtrls[idx],
                                          label: 'Nombre',
                                          hint: 'Citra Barre',
                                        ),
                                      ),
                                      if (orgNombreCtrls.length > 1)
                                        IconButton(
                                          onPressed: () => setD(() {
                                            orgNombreCtrls
                                                .removeAt(idx)
                                                .dispose();
                                            orgInstaCtrls
                                                .removeAt(idx)
                                                .dispose();
                                          }),
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                            color: AppColors.error,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _AuraTextField(
                                    controller: orgInstaCtrls[idx],
                                    label: 'Instagram',
                                    hint: '@citrabarre',
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () => setD(() {
                                      orgNombreCtrls
                                          .add(TextEditingController());
                                      orgInstaCtrls
                                          .add(TextEditingController());
                                    }),
                                    icon: const Icon(Icons.add_rounded,
                                        color: AppColors.primary),
                                    label: const Text(
                                      'Agregar organizador/a',
                                      style:
                                          TextStyle(color: AppColors.primary),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Detalles del evento (workshop): descripción larga,
                            // foto con preview, dirección propia y qué incluye.
                            _SectionCard(
                              title: 'Detalles del evento',
                              children: [
                                _AuraTextField(
                                  controller: descCtrl,
                                  label: 'Descripción del evento',
                                  hint:
                                      'Contá de qué se trata, para quién es, qué van a vivir…',
                                  maxLines: 4,
                                ),
                                const SizedBox(height: 12),
                                _AuraTextField(
                                  controller: dirCtrl,
                                  label: 'Dirección del evento',
                                  hint: 'Puede ser distinta a la del estudio',
                                ),
                                const SizedBox(height: 12),
                                _AuraTextField(
                                  controller: incluye,
                                  label: 'Qué incluye',
                                  hint: 'Materiales, bebida, sorpresas…',
                                  maxLines: 2,
                                ),
                                const SizedBox(height: 12),
                                _AuraTextField(
                                  controller: imagenUrl,
                                  label: 'Foto del evento (URL)',
                                  hint: 'https://...',
                                  onChanged: (_) => setD(() {}),
                                ),
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: imagenUrl.text.trim().isEmpty
                                      ? Container(
                                          height: 140,
                                          width: double.infinity,
                                          color: const Color(0xFFEDE7E1),
                                          child: const Icon(
                                            Icons.image_outlined,
                                            color: AppColors.grey,
                                            size: 44,
                                          ),
                                        )
                                      : Image.network(
                                          imagenUrl.text.trim(),
                                          height: 140,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                            height: 140,
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
                                      final uploaded =
                                          await _subirImagenClase();
                                      if (uploaded != null) {
                                        imagenUrl.text = uploaded;
                                        setD(() {});
                                      }
                                    },
                                    icon: const Icon(Icons.image_outlined),
                                    label: const Text('Subir foto del evento'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                          // Card 5: Detalles adicionales (colapsable)
                          _SectionCard(
                            title: 'Descripción, sala y fotos',
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
                                label: 'Descripción de la clase',
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
      disposeAll(); return;
    }
    if (n.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Completá al menos el nombre de la clase')));
      disposeAll(); return;
    }
    // Organizadores (solo workshops): filas con nombre y/o instagram cargados.
    final organizadores = <Map<String, String>>[];
    if (tipo == 'workshop') {
      for (var k = 0; k < orgNombreCtrls.length; k++) {
        final nm = orgNombreCtrls[k].text.trim();
        final ig = orgInstaCtrls[k].text.trim().replaceFirst('@', '');
        if (nm.isEmpty && ig.isEmpty) continue;
        organizadores.add({'nombre': nm, 'instagram': ig});
      }
    }
    final payload = {
      'nombre': n.text.trim(),
      'dia_semana': d,
      'hora_inicio': '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
      'duracion_min': dur,
      'lugares_total': int.tryParse(c.text.trim()) ?? 12,
      'creditos': _creditosFinal(cr, tipo, dia: diaPrecio(), hora: t),
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
      'tipo': tipo,
      if (tipo == 'workshop') 'organizadores': organizadores,
      // Campos exclusivos de workshops (columnas descripcion/direccion en
      // `clases`). No se mandan en clases normales / horarios fijos.
      if (tipo == 'workshop')
        'descripcion': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
      if (tipo == 'workshop')
        'direccion': dirCtrl.text.trim().isEmpty ? null : dirCtrl.text.trim(),
      'categorias': cats,
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
      // El cartel muestra algo accionable, no el PostgrestException crudo. El
      // detalle tecnico va a debugPrint para poder diagnosticar sin que el
      // estudio lea "Could not find the 'tipo' column of 'horarios_fijos'".
      debugPrint('Error guardando ${edit ? 'horario fijo' : 'clase individual'}: $e');
      messenger.showSnackBar(
        SnackBar(
          content: Text(edit
              ? 'No se pudo guardar el horario. Intentá de nuevo.'
              : 'No se pudo crear la clase. Intentá de nuevo.'),
        ),
      );
      // Ojo: no tocamos `_tablaOk`. Que falle un guardado no significa que la
      // tabla no se pueda leer, y ponerlo en false reemplazaba toda la lista
      // por el panel "No se pudieron cargar los horarios fijos" con el texto
      // crudo del error adentro.
    } finally {
      disposeAll();
    }
  }

  String _durLabel(int min) {
    if (min % 60 == 0) return '${min ~/ 60} h';
    if (min > 60) return '${min ~/ 60} h ${min % 60} min';
    return '$min min';
  }

  Future<void> _openGridForm() async {
    // Guarda de permiso: la profe no crea, edita, borra ni avisa.
    // Va acá y no solo en la UI para cubrir cualquier camino de
    // navegación que no haya quedado gateado.
    if (!_puedeEditar) return;
    final messenger = ScaffoldMessenger.of(context);
    List<String> categoriasDisponibles;
    try {
      categoriasDisponibles = await _loadCategoriasDisponibles();
    } catch (e) {
      debugPrint('[_openGridForm categorias] $e');
      _snack(kMsgErrorCarga);
      return;
    }
    final n = TextEditingController();
    final i = TextEditingController();
    final iDesc = TextEditingController();
    final incluye = TextEditingController();
    final imagenUrl = TextEditingController();
    final galeria = TextEditingController();
    final s = TextEditingController();
    final c = TextEditingController(text: '12');
    final cr = TextEditingController(text: '10');
    int? cierreReserva; // null = hereda el default del estudio.
    int dur = 60;
    final cats = <String>[];
    final diasSeleccionados = <int>{1, 2, 3, 4, 5};
    // La lista de horarios POR DÍA es la fuente de verdad y la vista previa a
    // la vez: lo que se ve acá es exactamente lo que se crea. El rango
    // (Desde/Hasta/cada) y "copiar a…" son atajos que la RELLENAN.
    // Antes el formulario ERA un rango, y "Desde 08:30 / Hasta 21:30" se leía
    // como horario de apertura: Tiwar cargó 13 clases por día creyendo que
    // cargaba 2 (25/8).
    final horariosPorDia = <int, List<TimeOfDay>>{};

    if (!mounted) return;
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
                              'Armá la grilla semanal: marcá los días y agregá los horarios de cada uno. Lo que ves en la lista es exactamente lo que se va a crear. Las clases se publican para las próximas $kGrillaSemanas semanas y se renuevan solas; después podés editar cada horario por separado.',
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
                              _InstructorField(
                                controller: i,
                                profes: _profeNombres,
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
                                    onSelected: (value) async {
                                      if (value) {
                                        setD(() => diasSeleccionados.add(dia));
                                        return;
                                      }
                                      final cargados =
                                          horariosPorDia[dia]?.length ?? 0;
                                      if (cargados > 0) {
                                        final seguro = await showDialog<bool>(
                                          context: ctx,
                                          builder: (dctx) => AlertDialog(
                                            title: Text(
                                                'Sacar ${_dayName(dia)}'),
                                            content: Text(
                                                'Se descartan los $cargados horario${cargados != 1 ? 's' : ''} que cargaste para ese día.'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(dctx, false),
                                                child: const Text('Volver'),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(dctx, true),
                                                child: const Text('Descartar'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (seguro != true) return;
                                      }
                                      setD(() {
                                        diasSeleccionados.remove(dia);
                                        horariosPorDia.remove(dia);
                                      });
                                    },
                                  );
                                }),
                              ),
                              const SizedBox(height: 14),
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
                              const SizedBox(height: 14),
                              _HorariosPorDiaEditor(
                                dias: (diasSeleccionados.toList()..sort()),
                                horarios: horariosPorDia,
                                duracionMin: dur,
                                onChanged: () => setD(() {}),
                                etiqueta: _etiquetaHorario,
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
                              _AuraDropdown<int?>(
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
                                    setD(() => cierreReserva = v),
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
                                    'Todavía no hay categorías disponibles. Escribinos y las '
                                    'configuramos para tu estudio.',
                                    style: TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 13),
                                  ),
                                )
                              else
                                CategoriasChecklist(
                                  label: 'Categorías (máx '
                                      '$kMaxCategoriasClase)',
                                  disponibles: categoriasDisponibles,
                                  seleccionadas: cats,
                                  onToggle: (c, marcada) => setD(() {
                                    if (marcada) {
                                      if (cats.length >=
                                          kMaxCategoriasClase) {
                                        return;
                                      }
                                      if (!cats.contains(c)) cats.add(c);
                                    } else {
                                      cats.remove(c);
                                    }
                                  }),
                                ),
                              const SizedBox(height: 12),
                              // La grilla genera clases en varios días y
                              // horarios: en modo rango cada una toma el precio
                              // de su propia franja, así que mostramos la regla
                              // en vez de un número único.
                              _PrecioCalculadoField(
                                estudio: _estudio,
                                dia: diasSeleccionados.isEmpty
                                    ? 1
                                    : (diasSeleccionados.toList()..sort()).first,
                                hora: _primeraHora(
                                    diasSeleccionados, horariosPorDia),
                                porHorario: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Card 5: Detalles adicionales (colapsable)
                          _SectionCard(
                            title: 'Descripción, sala y fotos',
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
                                label: 'Descripción de la clase',
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
                      child: Builder(builder: (_) {
                        final total = _totalHorarios(
                            diasSeleccionados, horariosPorDia);
                        final listo = diasSeleccionados.isNotEmpty &&
                            diasSeleccionados.every((d) =>
                                (horariosPorDia[d] ?? const []).isNotEmpty);
                        return ElevatedButton(
                          onPressed:
                              listo ? () => Navigator.pop(ctx, true) : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFE5E0DA),
                            disabledForegroundColor: const Color(0xFF9A928B),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: Text(listo
                              ? 'Crear $total horario${total != 1 ? 's' : ''}'
                              : diasSeleccionados.isEmpty
                                  ? 'Elegí al menos un día'
                                  : 'Faltan horarios en algún día'),
                        );
                      }),
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
      // Valor de arranque nomás: cada horario fijo que genera la grilla cae en
      // un día y una franja distintos, y el trigger trg_horarios_fijos_fija_precio
      // le pone a cada uno el precio que le corresponde.
      'creditos': _creditosFinal(
        cr,
        'clase',
        dia: diasSeleccionados.isEmpty
            ? 1
            : (diasSeleccionados.toList()..sort()).first,
        hora: _primeraHora(diasSeleccionados, horariosPorDia),
      ),
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
      'categorias': cats,
    };

    // Resumen ANTES de crear nada. Una grilla de 5 días x 6 franjas publica
    // 270 clases de una: el estudio tiene que ver el número antes, no
    // enterarse después por el snackbar.
    final porDia = <int, List<TimeOfDay>>{
      for (final d in diasSeleccionados.toList()..sort())
        d: List<TimeOfDay>.of(horariosPorDia[d] ?? const []),
    };
    final confirmado = await _confirmarGeneracionGrilla(
      horariosPorDia: porDia,
      duracionMin: dur,
      sala: s.text.trim(),
    );
    if (confirmado != true || !mounted) {
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

    try {
      // `creados` es lo que confirmó el servidor, no el largo del lote.
      final creados = await _service.crearHorariosFijosEnGrilla(
        horariosPorDia: porDia,
        duracionMin: dur,
        payloadBase: payloadBase,
      );
      await _loadStudio();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Grilla creada: $creados horario${creados != 1 ? 's' : ''} fijo${creados != 1 ? 's' : ''}. Publicando las próximas $kGrillaSemanas semanas…')),
      );
      try {
        final result = await _service.generarProximasSemanasDesdeHorarios(weeks: kGrillaSemanas);
        await _loadStudio();
        if (!mounted) return;
        final creadas = result['creadas'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Clases publicadas para $kGrillaSemanas semanas ($creadas nuevas).')),
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

  /// Resumen previo a crear una grilla, DÍA POR DÍA: exactamente los
  /// horarios que se van a crear, cuántos horarios fijos son y cuántas clases
  /// publica en las próximas [kGrillaSemanas] semanas.
  ///
  /// El número de clases es un techo: la generación saltea las que ya existen.
  Future<bool?> _confirmarGeneracionGrilla({
    required Map<int, List<TimeOfDay>> horariosPorDia,
    required int duracionMin,
    String sala = '',
  }) async {
    final dias = horariosPorDia.keys.where((d) => d >= 1 && d <= 7).toList()
      ..sort();
    if (dias.isEmpty) {
      _snack('Elegí al menos un día.');
      return false;
    }
    if (duracionMin <= 0) {
      _snack('La duración tiene que ser mayor a 0.');
      return false;
    }
    final vacios = dias.where((d) => (horariosPorDia[d] ?? const []).isEmpty);
    if (vacios.isNotEmpty) {
      _snack('Faltan horarios en ${vacios.map(_dayName).join(', ')}.');
      return false;
    }

    final horarios = _totalHorarios(dias.toSet(), horariosPorDia);
    final totalClases = horarios * kGrillaSemanas;

    final desde = _ahoraAr();
    final hasta = desde.add(const Duration(days: kGrillaSemanas * 7));
    final f = DateFormat("d 'de' MMMM", 'es');

    if (!mounted) return false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revisá antes de crear'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final d in dias)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text(
                          _kDiaCorto[d] ?? '',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          (List<TimeOfDay>.of(horariosPorDia[d]!)
                                ..sort((a, b) =>
                                    (a.hour * 60 + a.minute)
                                        .compareTo(b.hour * 60 + b.minute)))
                              .map((t) => _etiquetaHorario(d, t))
                              .join('   '),
                          style: const TextStyle(
                              color: AppColors.black,
                              fontSize: 13,
                              height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 18),
              Text(
                '$horarios horario${horarios != 1 ? 's' : ''} fijo${horarios != 1 ? 's' : ''} de ${_durLabel(duracionMin)} · '
                '$totalClases clase${totalClases != 1 ? 's' : ''} en las próximas $kGrillaSemanas semanas',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.black,
                ),
              ),
              const SizedBox(height: 8),
              _FilaResumenGrilla(
                icono: Icons.calendar_today_outlined,
                texto: 'Desde el ${f.format(desde)} hasta el ${f.format(hasta)}',
              ),
              // La sala forma parte de la clave: dos salones pueden dictar al
              // mismo minuto, el mismo salón (o ninguno) dos veces, no. Se
              // avisa ANTES de crear, que es cuando se puede corregir.
              _FilaResumenGrilla(
                icono: Icons.meeting_room_outlined,
                texto: sala.isEmpty
                    ? 'Sin sala. Si otro salón ya dicta a alguna de estas horas, '
                        'volvé y cargá el nombre de la sala para que no choquen.'
                    : 'Sala: $sala',
              ),
              const Text(
                'Si ya había clases en esos horarios no se duplican, así que el '
                'número final puede ser menor.',
                style: TextStyle(
                    color: AppColors.grey, fontSize: 12, height: 1.35),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.grey),
            child: const Text('Volver'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
            ),
            child: Text('Crear $horarios horario${horarios != 1 ? 's' : ''}'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _sortFixed() {
    _horarios.sort((a, b) {
      final da = (a['dia_semana'] as num?)?.toInt() ?? 1;
      final db = (b['dia_semana'] as num?)?.toInt() ?? 1;
      if (da != db) return da.compareTo(db);
      return (a['hora_inicio']?.toString() ?? '').compareTo(b['hora_inicio']?.toString() ?? '');
    });
  }

  /// Borra un horario fijo Y las clases que generó.
  ///
  /// Antes esto solo borraba la fila de `horarios_fijos`: las clases ya
  /// publicadas quedaban dando vueltas sin horario padre, imposibles de sacar
  /// salvo una por una. Ahora se limpian juntas, devolviendo créditos.
  /// Cancela (con devolución) y borra cada clase. Devuelve las que NO se
  /// pudieron borrar, con el motivo legible. Nunca se traga un error.
  Future<List<String>> _borrarClasesDeHorario(
    List<Map<String, dynamic>> clases,
    void Function(int devueltos) onDevueltos,
  ) async {
    final fallidas = <String>[];
    final f = DateFormat("EEE d/M HH:mm", 'es');
    for (final c in clases) {
      final cid = (c['id'] as num?)?.toInt();
      if (cid == null) continue;
      final nom = c['nombre']?.toString() ?? 'la clase';
      final dt = DateTime.tryParse(c['fecha']?.toString() ?? '');
      final etiqueta = dt == null ? nom : '$nom · ${f.format(dt)}';
      try {
        onDevueltos(await _reservasService.cancelarClaseConDevolucion(cid, nom));
      } catch (e) {
        debugPrint('[borrarClasesDeHorario cancelar $cid] $e');
        fallidas.add('$etiqueta — ${_mensajeDeError(e)}');
        continue;
      }
      try {
        await _service.eliminarClaseRow(cid);
      } catch (e) {
        debugPrint('[borrarClasesDeHorario borrar $cid] $e');
        fallidas.add('$etiqueta — ${_mensajeDeError(e)}');
      }
    }
    return fallidas;
  }

  Future<void> _avisarClasesNoBorradas(List<String> fallidas) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No se eliminó el horario'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${fallidas.length} clase${fallidas.length != 1 ? 's' : ''} no se '
                'pud${fallidas.length != 1 ? 'ieron' : 'o'} borrar. El horario queda '
                'como estaba; las demás clases sí se borraron.',
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 10),
              for (final t in fallidas)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• $t',
                      style: const TextStyle(fontSize: 12, height: 1.3)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
        ],
      ),
    );
  }

  Future<void> _deleteFixed(int id) async {
    final messenger = ScaffoldMessenger.of(context);

    List<Map<String, dynamic>> futuras = const [];
    try {
      futuras = await _service.listarClasesFuturasDeHorario(id);
    } catch (_) {}
    if (!mounted) return;

    final ids = futuras
        .map((c) => (c['id'] as num?)?.toInt())
        .whereType<int>()
        .toList();
    final alumnos = ids.isEmpty
        ? 0
        : await _avisoService.contarAlumnosDeClases(ids);
    if (!mounted) return;

    final ok = await _confirmDialog(
      titulo: '¿Eliminar este horario?',
      mensaje: [
        if (ids.isEmpty)
          'No tiene clases futuras publicadas.'
        else
          'Se eliminan también sus ${ids.length} clase'
              '${ids.length != 1 ? 's' : ''} futura'
              '${ids.length != 1 ? 's' : ''}.',
        if (alumnos > 0)
          'Ojo: hay $alumnos alumno${alumnos != 1 ? 's' : ''} con reserva. '
              'Se les devuelven los créditos automáticamente, pero se quedan '
              'sin la clase.',
      ].join('\n\n'),
      confirmar: 'Sí, eliminar',
    );
    if (ok != true || !mounted) return;

    int devueltos = 0;
    try {
      // 2026-08-25: antes cada paso iba en try{}catch(_){} y la grilla se
      // borraba PASE LO QUE PASE. Si el candado (reserva presente/completada)
      // u otro error frenaba una clase, quedaba HUÉRFANA (horario_fijo_id
      // null por el SET NULL), publicada e invisible en "Horarios fijos": el
      // estudio creía que la había borrado. Ahora: si alguna falla, se
      // informa cuál y por qué, y el horario NO se toca.
      final fallidas = await _borrarClasesDeHorario(futuras, (n) => devueltos += n);
      if (fallidas.isNotEmpty) {
        await _loadStudio();
        if (!mounted) return;
        await _avisarClasesNoBorradas(fallidas);
        return;
      }
      await _service.eliminarHorarioFijo(id);
      await _loadStudio();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Horario eliminado'
            '${ids.isNotEmpty ? ' junto con ${ids.length} clase${ids.length != 1 ? 's' : ''}' : ''}'
            '${devueltos > 0 ? '. Devolvimos créditos a $devueltos alumno${devueltos != 1 ? 's' : ''}' : ''}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo eliminar el horario: ${_mensajeDeError(e)}')),
      );
    }
  }

  Future<void> _generateWeek() async {
    setState(() => _publishingWeek = true);
    try {
      final result = await _service.generarProximasSemanasDesdeHorarios(weeks: kGrillaSemanas);
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
            if (_puedeGestionarClases) ...[
              if (_puedeEditar)
                IconButton(
                  onPressed: _openGridForm,
                  icon: const Icon(Icons.grid_view_rounded),
                  color: AppColors.primary,
                  tooltip: 'Crear grilla',
                ),
              IconButton(
                onPressed: _abrirMenuCrear,
                icon: const Icon(Icons.add),
                color: AppColors.primary,
                tooltip: 'Nueva clase',
              ),
            ],
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
                          'Sin clases para esta semana. Las clases se publican solas desde los horarios fijos; si todavía no cargaste ninguno, creá la grilla.',
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
                            final status = c['cancelada'] == true
                                ? 'Cancelada'
                                : dt2 == null
                                    ? 'Programada'
                                    : (dt2.isBefore(now2) && now2.difference(dt2).inMinutes < 90)
                                        ? 'En curso'
                                        : dt2.difference(now2).inHours < 8
                                            ? 'Confirmada'
                                            : 'Programada';
                            final statusColor = status == 'Cancelada'
                                ? const Color(0xFFF1F1F1)
                                : status == 'Confirmada'
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
                                          // La lista de espera del estudio no
                                          // se veía en ningún lado. Sólo
                                          // aparece si hay alguien esperando.
                                          if ((_enEspera[(c['id'] as num?)?.toInt()] ?? 0) > 0) ...[
                                            const SizedBox(height: 3),
                                            Text(
                                              '${_enEspera[(c['id'] as num?)?.toInt()]} esperando',
                                              style: const TextStyle(color: Color(0xFFE8763A), fontSize: 10, fontWeight: FontWeight.w700),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
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
    // F5: datos del profe logueado (para el badge "Tu clase" y el gating).
    final app = context.watch<AppProvider>();
    _esProfe = app.esProfe;
    _miNombre = app.usuario?.nombre ?? '';
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
      bottomNavigationBar:
          (_seleccionMultiple && _seleccionadas.isNotEmpty && !_showFixed)
              ? _buildBarraCancelacion()
              : null,
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
                      const Expanded(
                        child: Text(
                          'Mis clases',
                          // En modo selección la fila suma tres controles;
                          // sin esto el título desbordaba en pantallas chicas.
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.black,
                              fontSize: 22,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      // La profe tiene un panel acotado (Clases + Asistencia) sin
                      // solapa de Perfil, así que su única puerta a "Salir del
                      // estudio" es este engranaje de configuración.
                      if (context.watch<AppProvider>().esProfe)
                        IconButton(
                          onPressed: _mostrarConfiguracionProfe,
                          icon: const Icon(Icons.settings_outlined),
                          color: AppColors.grey,
                          tooltip: 'Configuración',
                        ),
                      if (_puedeGestionarClases) ...[
                        if (_puedeEditar && !_showFixed && _seleccionMultiple) ...[
                          IconButton(
                            onPressed: _seleccionarPorHorario,
                            icon: const Icon(Icons.event_repeat_rounded),
                            color: AppColors.primary,
                            tooltip: 'Seleccionar por horario',
                          ),
                          TextButton(
                            onPressed: _toggleSeleccionarTodas,
                            child: Text(
                              _todasSeleccionadas ? 'Ninguna' : 'Todas',
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _seleccionMultiple = false;
                              _seleccionadas.clear();
                            }),
                            child: const Text('Cancelar',
                                style: TextStyle(color: AppColors.grey)),
                          ),
                        ]
                        else ...[
                          // Selección múltiple y grilla: solo admin/dueña.
                          if (_puedeEditar && !_showFixed)
                            IconButton(
                              onPressed: () =>
                                  setState(() => _seleccionMultiple = true),
                              icon: const Icon(Icons.checklist_rounded),
                              color: AppColors.primary,
                              tooltip: 'Seleccionar',
                            ),
                          if (_puedeEditar)
                            IconButton(
                              onPressed: _openGridForm,
                              icon: const Icon(Icons.grid_view_rounded),
                              color: AppColors.primary,
                              tooltip: 'Crear grilla',
                            ),
                          // Nueva clase: admin y profe (Opción A).
                          IconButton(
                            onPressed: _abrirMenuCrear,
                            icon: const Icon(Icons.add),
                            color: AppColors.primary,
                            tooltip: 'Nueva clase',
                          ),
                        ],
                      ]
                      // Solo el usuario final ve el atajo a Explorar. Una
                      // profe no cae acá: no ve ni los botones de escritura
                      // ni este botón, que es del lado usuario.
                      else if (!_studio)
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
                    // El toggle "Horarios fijos" es configuración de la
                    // grilla: la profe ve directo sus clases cargadas.
                    if (_puedeEditar) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16)),
                        child: Row(children: [
                          Expanded(child: _SegmentButton(label: 'Horarios fijos', selected: _showFixed, onTap: () => setState(() { _showFixed = true; _seleccionMultiple = false; _seleccionadas.clear(); }))),
                          Expanded(child: _SegmentButton(label: 'Clases cargadas', selected: !_showFixed, onTap: () => setState(() => _showFixed = false))),
                        ]),
                      ),
                      // La pestaña decide el alcance de editar/borrar: la serie
                      // entera o una sola fecha. Sin este renglón el estudio no
                      // tiene forma de saberlo (pedido en la revisión del 25/8).
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                size: 14, color: Color(0xFF9A928B)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _showFixed
                                    ? 'Acá editás o borrás el horario semanal: cambia todas sus clases futuras. Las que ya pasaron no se tocan.'
                                    : 'Acá editás o cancelás una clase puntual: sólo esa fecha, sin tocar el resto de la semana.',
                                style: const TextStyle(
                                    color: Color(0xFF6E6761),
                                    fontSize: 12,
                                    height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // F5 — filtro "Ver por profe" (solo para el estudio admin,
                    // cuando hay profes cargadas).
                    if (_studio && !_esProfe && _profeNombres.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person_search_rounded,
                                color: AppColors.primary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String?>(
                                  isExpanded: true,
                                  value: _filtroProfe,
                                  hint: const Text('Ver por profe'),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('Todas las profes'),
                                    ),
                                    ..._profeNombres.map(
                                      (n) => DropdownMenuItem<String?>(
                                        value: n,
                                        child: Text(n),
                                      ),
                                    ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _filtroProfe = v),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // `_puedeEditar` y no `_studio`: _buildFixed() renderiza
                    // filas con editar/eliminar del horario fijo.
                    if (_puedeEditar && _showFixed) ..._buildFixed()
                    else if (_studio) ..._buildClasesLoadedSection()
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
                            onAvisar:
                                _puedeEditar ? () => _mostrarAvisoSheet(c) : null,
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
    final horariosVisibles = _horarios
        .where((h) => _matchInstructor(h['instructor'], _filtroProfe))
        .toList();
    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final h in horariosVisibles) {
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
                      esMiClase: _esMiClase(h['instructor']),
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

  // ── M1 + M3: vista nueva de "Clases cargadas" con filtro Próximas /
  // Pasadas y toggle Lista / Grilla. Reemplaza la vista de calendario
  // semanal cuando estamos en _showFixed = false.

  /// Próximas SIN aplicar la ventana de [_rangoDias]. Es el universo real de
  /// clases futuras cargadas: lo usamos para el contador "X de Y".
  List<Map<String, dynamic>> _clasesProximasTodas() {
    final ahora = _ahoraAr();
    return _clases.where((c) {
      final dt = DateTime.tryParse(c['fecha']?.toString() ?? '');
      if (dt == null) return false;
      return !dt.isBefore(ahora) &&
          _matchInstructor(c['instructor'], _filtroProfe);
    }).toList()
      ..sort((a, b) => (a['fecha']?.toString() ?? '')
          .compareTo(b['fecha']?.toString() ?? ''));
  }

  List<Map<String, dynamic>> _clasesProximas() {
    final todas = _clasesProximasTodas();
    final dias = _rangoDias;
    if (dias == null) return todas;
    final limite = _ahoraAr().add(Duration(days: dias));
    return todas.where((c) {
      final dt = DateTime.tryParse(c['fecha']?.toString() ?? '');
      return dt != null && !dt.isAfter(limite);
    }).toList();
  }

  /// Clases ya dictadas del mes que se está mirando en el historial.
  /// Nunca se borran: solo salen de la vista activa.
  List<Map<String, dynamic>> _clasesPasadas() {
    final ahora = _ahoraAr();
    return _clasesHistorial.where((c) {
      final dt = DateTime.tryParse(c['fecha']?.toString() ?? '');
      if (dt == null) return false;
      return dt.isBefore(ahora) &&
          _matchInstructor(c['instructor'], _filtroProfe);
    }).toList()
      // Mas reciente primero — al estudio le interesa lo recien pasado.
      ..sort((a, b) => (b['fecha']?.toString() ?? '')
          .compareTo(a['fecha']?.toString() ?? ''));
  }

  /// Trae del servidor las clases del mes [mes]. Se llama al abrir "Pasadas" y
  /// al navegar entre meses.
  Future<void> _cargarHistorial(DateTime mes) async {
    if (!mounted) return;
    setState(() {
      _mesHistorial = DateTime(mes.year, mes.month);
      _cargandoHistorial = true;
    });
    try {
      final desde = DateTime(mes.year, mes.month);
      // Día 0 del mes siguiente = último día de este mes.
      final hasta = DateTime(mes.year, mes.month + 1, 0, 23, 59, 59);
      final data = await _service.getClasesDeEstudio(
        from: desde,
        to: hasta,
        limit: 3000,
      );
      if (!mounted) return;
      setState(() {
        _clasesHistorial = data;
        _cargandoHistorial = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _clasesHistorial = [];
        _cargandoHistorial = false;
      });
    }
  }

  void _irAMesHistorial(int delta) {
    final destino =
        DateTime(_mesHistorial.year, _mesHistorial.month + delta);
    // No dejamos navegar al futuro: para eso está la solapa "Próximas".
    final ahora = _ahoraAr();
    if (destino.isAfter(DateTime(ahora.year, ahora.month))) return;
    _cargarHistorial(destino);
  }

  List<Widget> _buildClasesLoadedSection() {
    final clases =
        _showPast ? _clasesPasadas() : _clasesProximas();

    return [
      // Tabs Próximas / Pasadas + toggle Lista/Grilla a la derecha.
      Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                Expanded(
                  child: _SegmentButton(
                    label: 'Próximas',
                    selected: !_showPast,
                    onTap: () {
                      setState(() => _showPast = false);
                      _guardarPreferenciaPasadas(false);
                    },
                  ),
                ),
                Expanded(
                  child: _SegmentButton(
                    label: 'Historial',
                    selected: _showPast,
                    onTap: () {
                      setState(() {
                        _showPast = true;
                        _seleccionMultiple = false;
                        _seleccionadas.clear();
                      });
                      _guardarPreferenciaPasadas(true);
                      // El historial se pide bajo demanda: la carga principal
                      // solo trae 30 días para atrás.
                      _cargarHistorial(_mesHistorial);
                    },
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          _ViewToggle(
            gridView: _gridView,
            onChanged: (v) {
              setState(() => _gridView = v);
              _guardarPreferenciaGrid(v);
            },
          ),
        ],
      ),
      // Ventana de fechas: sin esto el estudio solo veía las clases de los
      // próximos días aunque la grilla hubiera publicado 3 meses.
      if (!_showPast) ...[
        const SizedBox(height: 12),
        _buildSelectorRango(),
      ] else ...[
        const SizedBox(height: 12),
        _buildNavegadorMes(),
      ],
      const SizedBox(height: 14),
      if (_showPast && _cargandoHistorial)
        const Padding(
          padding: EdgeInsets.only(top: 40),
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        )
      else if (clases.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Center(
            child: Text(
              _showPast
                  ? 'No hubo clases en este mes.'
                  : 'No hay clases próximas cargadas. Generá la grilla desde los horarios fijos.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF8F877F)),
            ),
          ),
        )
      else if (_gridView)
        _buildClasesGrid(clases)
      else
        _buildClasesList(clases),
    ];
  }

  /// Navegador de meses del historial, con un resumen de lo que dio ese mes.
  /// Las clases pasadas quedan guardadas para siempre: esto es la puerta de
  /// entrada a esa información.
  Widget _buildNavegadorMes() {
    final ahora = _ahoraAr();
    final esMesActual = _mesHistorial.year == ahora.year &&
        _mesHistorial.month == ahora.month;
    final clases = _clasesPasadas();
    final asistentes = clases.fold<int>(
      0,
      (s, c) => s + ((c['lugares_total'] as num?)?.toInt() ?? 0) -
          ((c['lugares_disponibles'] as num?)?.toInt() ?? 0),
    );

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => _irAMesHistorial(-1),
                icon: const Icon(Icons.chevron_left_rounded),
                color: AppColors.primary,
                tooltip: 'Mes anterior',
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy', 'es').format(_mesHistorial),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              IconButton(
                // Al futuro no se navega: para eso está "Próximas".
                onPressed: esMesActual ? null : () => _irAMesHistorial(1),
                icon: const Icon(Icons.chevron_right_rounded),
                color: esMesActual ? const Color(0xFFD1CAC3) : AppColors.primary,
                tooltip: 'Mes siguiente',
              ),
            ],
          ),
        ),
        if (!_cargandoHistorial && clases.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.insights_outlined,
                  size: 15, color: AppColors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${clases.length} clase${clases.length != 1 ? 's' : ''} '
                  'dictada${clases.length != 1 ? 's' : ''}'
                  '${asistentes > 0 ? ' · $asistentes lugar${asistentes != 1 ? 'es' : ''} ocupado${asistentes != 1 ? 's' : ''}' : ''}',
                  style: const TextStyle(color: AppColors.grey, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Chips de rango + contador. El contador es lo que evita que una clase
  /// exista pero parezca no existir: si el filtro esconde algo, se dice.
  Widget _buildSelectorRango() {
    final todas = _clasesProximasTodas();
    final visibles = _clasesProximas();
    final ocultas = todas.length - visibles.length;

    Widget chip(String label, int? dias) {
      final sel = _rangoDias == dias;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => setState(() => _rangoDias = dias),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? AppColors.primary : AppColors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: sel ? AppColors.primary : const Color(0xFFEDE7E1),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: sel ? AppColors.white : AppColors.black,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    String rangoTexto() {
      if (visibles.isEmpty) return 'No hay clases en este rango.';
      final primera = DateTime.tryParse(visibles.first['fecha']?.toString() ?? '');
      final ultima = DateTime.tryParse(visibles.last['fecha']?.toString() ?? '');
      if (primera == null || ultima == null) return '';
      final f = DateFormat('d MMM', 'es');
      return '${visibles.length} clase${visibles.length != 1 ? 's' : ''} · '
          '${f.format(primera)} a ${f.format(ultima)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              chip('7 días', 7),
              chip('30 días', 30),
              chip('90 días', 90),
              chip('Todas', null),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.event_note_outlined,
                size: 15, color: AppColors.grey),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                rangoTexto(),
                style: const TextStyle(color: AppColors.grey, fontSize: 12),
              ),
            ),
            if (ocultas > 0)
              GestureDetector(
                onTap: () => setState(() => _rangoDias = null),
                child: Text(
                  '+$ocultas más',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Ids visibles ahora mismo en la lista (respeta rango y filtro de profe).
  List<int> _idsVisibles() =>
      (_showPast ? _clasesPasadas() : _clasesProximas())
          .map((c) => (c['id'] as num?)?.toInt())
          .whereType<int>()
          .toList();

  bool get _todasSeleccionadas {
    final visibles = _idsVisibles();
    return visibles.isNotEmpty && _seleccionadas.containsAll(visibles);
  }

  void _toggleSeleccionarTodas() {
    final visibles = _idsVisibles();
    setState(() {
      if (_seleccionadas.containsAll(visibles)) {
        _seleccionadas.removeAll(visibles);
      } else {
        _seleccionadas.addAll(visibles);
      }
    });
  }

  /// Selecciona de una todas las clases de un horario recurrente
  /// ("todos los lunes 8:00"), que es el caso real: el estudio cargó una
  /// grilla y quiere sacar una franja entera sin tildar 30 tarjetas.
  Future<void> _seleccionarPorHorario() async {
    final visibles = _showPast ? _clasesPasadas() : _clasesProximas();
    if (visibles.isEmpty) return;

    // Agrupamos por (día de semana, hora de inicio).
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final c in visibles) {
      final dt = DateTime.tryParse(c['fecha']?.toString() ?? '');
      if (dt == null) continue;
      final key = '${dt.weekday}|'
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
      grupos.putIfAbsent(key, () => []).add(c);
    }
    if (grupos.isEmpty) return;

    final claves = grupos.keys.toList()
      ..sort((a, b) {
        final pa = a.split('|');
        final pb = b.split('|');
        final da = int.tryParse(pa.first) ?? 0;
        final db = int.tryParse(pb.first) ?? 0;
        if (da != db) return da.compareTo(db);
        return pa.last.compareTo(pb.last);
      });

    final elegido = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 6),
              child: Text(
                'Seleccionar por horario',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.black),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Elegí una franja y se marcan todas sus clases del rango que '
                'estás viendo.',
                style: TextStyle(color: AppColors.grey, fontSize: 13),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: claves.map((k) {
                  final partes = k.split('|');
                  final dia = int.tryParse(partes.first) ?? 1;
                  final hora = partes.last;
                  final cant = grupos[k]!.length;
                  return ListTile(
                    leading: const Icon(Icons.event_repeat_rounded,
                        color: AppColors.primary),
                    title: Text('${_dayName(dia)} $hora'),
                    subtitle: Text(
                        '$cant clase${cant != 1 ? 's' : ''} en este rango'),
                    onTap: () => Navigator.pop(ctx, k),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (elegido == null || !mounted) return;
    final ids = grupos[elegido]!
        .map((c) => (c['id'] as num?)?.toInt())
        .whereType<int>();
    setState(() => _seleccionadas.addAll(ids));
  }

  void _toggleSeleccion(int? id) {
    if (id == null) return;
    setState(() {
      if (_seleccionadas.contains(id)) {
        _seleccionadas.remove(id);
      } else {
        _seleccionadas.add(id);
      }
    });
  }

  Widget _buildClasesList(List<Map<String, dynamic>> clases) {
    return Column(
      children: [
        for (final c in clases)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _seleccionMultiple
                ? Builder(builder: (_) {
                    final id = (c['id'] as num?)?.toInt();
                    final selected =
                        id != null && _seleccionadas.contains(id);
                    return GestureDetector(
                      onTap: () => _toggleSeleccion(id),
                      child: Row(
                        children: [
                          Checkbox(
                            value: selected,
                            activeColor: AppColors.primary,
                            onChanged: (_) => _toggleSeleccion(id),
                          ),
                          Expanded(
                            child: AbsorbPointer(
                              child: _StudioClassCard(
                                clase: c,
                                studioMode: true,
                                esMiClase: _esMiClase(c['instructor']),
                                onAvisar: () {},
                                onMore: () {},
                                onEdit: () {},
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  })
                : GestureDetector(
                    // La profe ve la card en modo lectura: sin menú de
                    // acciones, sin editar y sin avisar.
                    onLongPress:
                        _puedeEditar ? () => _mostrarMenuClase(c) : null,
                    child: _StudioClassCard(
                      clase: c,
                      studioMode: true,
                      esMiClase: _esMiClase(c['instructor']),
                      onAvisar:
                          _puedeEditar ? () => _mostrarAvisoSheet(c) : null,
                      onMore:
                          _puedeEditar ? () => _mostrarMenuClase(c) : null,
                      onEdit:
                          _puedeGestionarClases ? () => _editClaseDialog(c) : null,
                    ),
                  ),
          ),
      ],
    );
  }

  Widget _buildClasesGrid(List<Map<String, dynamic>> clases) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.05,
      ),
      itemCount: clases.length,
      itemBuilder: (context, index) {
        final c = clases[index];
        if (_seleccionMultiple) {
          final id = (c['id'] as num?)?.toInt();
          final selected = id != null && _seleccionadas.contains(id);
          return GestureDetector(
            onTap: () => _toggleSeleccion(id),
            child: Stack(
              children: [
                AbsorbPointer(
                    child: _ClaseGridCard(
                        clase: c, esMiClase: _esMiClase(c['instructor']))),
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? AppColors.primary : AppColors.grey,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      selected ? Icons.check : Icons.circle_outlined,
                      size: 18,
                      color: selected ? Colors.white : Colors.transparent,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return GestureDetector(
          onTap: () => _mostrarMenuClase(c),
          onLongPress: () => _mostrarMenuClase(c),
          child: _ClaseGridCard(clase: c, esMiClase: _esMiClase(c['instructor'])),
        );
      },
    );
  }

  /// Bottom sheet de opciones cuando el estudio hace long-press o tap
  /// en los 3 puntitos de una card de clase.
  Future<void> _mostrarMenuClase(Map<String, dynamic> clase) async {
    // La profe no tiene el menú admin (eliminar clase/grilla), pero sí puede
    // ver el detalle y editar: caemos a la hoja de detalle, que ya muestra solo
    // lo que le corresponde (Editar, sin Cancelar ni Avisar).
    if (!_puedeEditar) {
      await _showClaseSheet(clase);
      return;
    }
    final horarioFijoId = (clase['horario_fijo_id'] as num?)?.toInt();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8E5E0),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              _OpcionTile(
                icon: Icons.edit_outlined,
                label: 'Editar',
                onTap: () async {
                  Navigator.pop(ctx);
                  await _editClaseDialog(clase);
                },
              ),
              _OpcionTile(
                icon: Icons.delete_outline,
                label: 'Eliminar esta clase',
                danger: true,
                onTap: () async {
                  Navigator.pop(ctx);
                  await _eliminarClase(clase);
                },
              ),
              if (horarioFijoId != null)
                _OpcionTile(
                  icon: Icons.delete_sweep_outlined,
                  label: 'Eliminar todas las clases de esta grilla',
                  danger: true,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _eliminarGrillaCompleta(clase);
                  },
                ),
              const SizedBox(height: 4),
              _OpcionTile(
                icon: Icons.close_rounded,
                label: 'Cancelar',
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _eliminarClase(Map<String, dynamic> clase) async {
    // Guarda de permiso: la profe no crea, edita, borra ni avisa.
    // Va acá y no solo en la UI para cubrir cualquier camino de
    // navegación que no haya quedado gateado.
    if (!_puedeEditar) return;
    final claseId = (clase['id'] as num?)?.toInt();
    if (claseId == null) return;
    final nombre = clase['nombre']?.toString() ?? 'esta clase';

    final ok = await _confirmDialog(
      titulo: '¿Eliminar esta clase?',
      mensaje:
          'Los alumnos que reservaron reciben sus créditos de vuelta.',
      confirmar: 'Sí, eliminar',
    );
    if (ok != true || !mounted) return;

    try {
      // Devuelve créditos + marca reservas y clase como canceladas.
      final devueltos =
          await _reservasService.cancelarClaseConDevolucion(claseId, nombre);
      // cancelarClaseConDevolucion solo marca la clase como cancelada en DB.
      // La quitamos del todo asi no aparece ni en "pasadas".
      await _service.eliminarClaseRow(claseId);
      await _loadStudio();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            devueltos > 0
                ? 'Clase eliminada. Devolvimos créditos a $devueltos alumno${devueltos != 1 ? 's' : ''}.'
                : 'Clase eliminada.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar: $e')),
      );
    }
  }

  Future<void> _eliminarGrillaCompleta(Map<String, dynamic> clase) async {
    final horarioFijoId = (clase['horario_fijo_id'] as num?)?.toInt();
    if (horarioFijoId == null) return;

    // Contamos primero para que la confirmación diga cuántas clases y cuántos
    // alumnos se ven afectados, en vez de un aviso genérico.
    List<Map<String, dynamic>> futuras = const [];
    try {
      futuras = await _service.listarClasesFuturasDeHorario(horarioFijoId);
    } catch (_) {}
    if (!mounted) return;

    final idsFuturas = futuras
        .map((c) => (c['id'] as num?)?.toInt())
        .whereType<int>()
        .toList();
    final alumnos = idsFuturas.isEmpty
        ? 0
        : await _avisoService.contarAlumnosDeClases(idsFuturas);
    if (!mounted) return;

    final ok = await _confirmDialog(
      titulo: '¿Eliminar todo este horario?',
      mensaje: [
        'Se eliminan ${idsFuturas.length} clase'
            '${idsFuturas.length != 1 ? 's' : ''} futura'
            '${idsFuturas.length != 1 ? 's' : ''} de este horario.',
        if (alumnos > 0)
          'Ojo: hay $alumnos alumno${alumnos != 1 ? 's' : ''} con reserva. '
              'Se les devuelven los créditos automáticamente, pero se quedan '
              'sin la clase.'
        else
          'Ninguna tiene reservas, así que no afecta a ningún alumno.',
      ].join('\n\n'),
      confirmar: 'Sí, eliminar',
    );
    if (ok != true || !mounted) return;

    try {

      // 2) Para cada una: devolver creditos + eliminar la fila.
      int totalDevueltos = 0;
      // Mismo criterio que _deleteFixed: si una clase no se pudo borrar, el
      // horario no se toca y se informa cuál.
      final fallidas =
          await _borrarClasesDeHorario(futuras, (n) => totalDevueltos += n);
      if (fallidas.isNotEmpty) {
        await _loadStudio();
        if (!mounted) return;
        await _avisarClasesNoBorradas(fallidas);
        return;
      }

      // 3) Eliminar el horario fijo mismo.
      await _service.eliminarHorarioFijo(horarioFijoId);

      await _loadStudio();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Horario fijo eliminado. ${futuras.length} clase${futuras.length != 1 ? 's' : ''} '
            'futura${futuras.length != 1 ? 's' : ''} borrada${futuras.length != 1 ? 's' : ''}'
            '${totalDevueltos > 0 ? ', $totalDevueltos alumno${totalDevueltos != 1 ? 's' : ''} con créditos devueltos' : ''}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar la grilla: ${_mensajeDeError(e)}')),
      );
    }
  }

  // ── Cancelación múltiple ──────────────────────────────────────────────────

  Widget _buildBarraCancelacion() {
    final n = _seleccionadas.length;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: AppColors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SizedBox(
          height: 50,
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _cancelandoLote ? null : _cancelarSeleccionadas,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _cancelandoLote
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.delete_outline_rounded),
            label: Text(
              _cancelandoLote
                  ? 'Eliminando…'
                  : 'Eliminar seleccionadas ($n)',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cancelarSeleccionadas() async {
    final ids = _seleccionadas.toList();
    if (ids.isEmpty) return;
    final n = ids.length;

    // Antes de borrar, cuántos alumnos reales tienen reserva activa. Si hay
    // gente anotada el estudio tiene que enterarse ANTES, no por el snackbar
    // de después.
    final alumnos = await _avisoService.contarAlumnosDeClases(ids);
    if (!mounted) return;

    final ok = await _confirmDialog(
      titulo: '¿Eliminar $n clase${n != 1 ? 's' : ''}?',
      mensaje: alumnos > 0
          ? 'Ojo: hay $alumnos alumno${alumnos != 1 ? 's' : ''} con reserva '
              'en estas clases. Se les devuelven los créditos '
              'automáticamente, pero se quedan sin la clase.'
          : 'Ninguna tiene reservas, así que no afecta a ningún alumno.',
      confirmar: 'Sí, eliminar',
    );
    if (ok != true || !mounted) return;

    setState(() => _cancelandoLote = true);

    int totalDevueltos = 0;
    int canceladas = 0;
    for (final id in ids) {
      final clase = _clases.firstWhere(
        (c) => (c['id'] as num?)?.toInt() == id,
        orElse: () => <String, dynamic>{},
      );
      final nom = clase['nombre']?.toString() ?? 'la clase';
      try {
        totalDevueltos +=
            await _reservasService.cancelarClaseConDevolucion(id, nom);
        canceladas++;
      } catch (_) {}
      // Borrado extra "por las dudas" (cancelarClaseConDevolucion ya borra la
      // fila, pero replicamos el patrón de _eliminarClase para robustez).
      try {
        await _service.eliminarClaseRow(id);
      } catch (_) {}
    }

    await _loadStudio();
    if (!mounted) return;
    setState(() {
      _cancelandoLote = false;
      _seleccionMultiple = false;
      _seleccionadas.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$canceladas clase${canceladas != 1 ? 's' : ''} '
          'eliminada${canceladas != 1 ? 's' : ''}'
          '${totalDevueltos > 0 ? ', $totalDevueltos alumno${totalDevueltos != 1 ? 's' : ''} con créditos devueltos' : ''}.',
        ),
      ),
    );
  }

  Future<bool?> _confirmDialog({
    required String titulo,
    required String mensaje,
    required String confirmar,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          titulo,
          style: const TextStyle(
            color: AppColors.black,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          mensaje,
          style: const TextStyle(
            color: AppColors.black,
            fontSize: 14,
            height: 1.4,
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
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
            ),
            child: Text(
              confirmar,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
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
  /// `null` = sin override, la clase hereda el default del estudio. Es el
  /// primer item a propósito: guardar 0 significaba "sin ventana" y pisaba
  /// la configuración del estudio.
  static const List<int?> _bookingCutoffOptions = [
    null, 0, 30, 60, 120, 180, 360, 720, 1440,
  ];
  String _bookingCutoffLabel(int? minutes) {
    if (minutes == null) return 'Usar el default del estudio';
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
  final bool esMiClase;
  final VoidCallback? onAvisar;
  final VoidCallback? onMore;
  final VoidCallback? onEdit;
  const _StudioClassCard({
    required this.clase,
    required this.studioMode,
    this.esMiClase = false,
    this.onAvisar,
    this.onMore,
    this.onEdit,
  });
  @override
  Widget build(BuildContext context) {
    final dt = DateTime.tryParse(clase['fecha']?.toString() ?? '');
    // 24 h a proposito: en 12 h una clase de las 13:30 se leia "1:30" y ya
    // confundio a un estudio (Tiwar, 25/8). Item 20 de la Tanda C.
    final time = dt != null ? DateFormat('HH:mm').format(dt) : '07:00';
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
          if (esMiClase) ...[
            const SizedBox(width: 6),
            const _TuClaseBadge(),
          ],
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(999)),
            child: Text(status, style: const TextStyle(color: Color(0xFF5F5953), fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          if (studioMode && onMore != null) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: onMore,
              icon: const Icon(Icons.more_vert_rounded,
                  color: Color(0xFF8F877F), size: 22),
              padding: EdgeInsets.zero,
              // 44x44 = tap target estandar Apple HIG (importante para iPad).
              constraints: const BoxConstraints(
                  minWidth: 44, minHeight: 44),
              tooltip: 'Más opciones',
            ),
          ],
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
            _ActionButton(label: 'Editar', background: const Color(0xFFF1F1F1), foreground: const Color(0xFF6A635D), onTap: onEdit ?? () {}),
            const SizedBox(width: 8),
            _ActionButton(label: 'Avisar', background: const Color(0xFFF1F1F1), foreground: const Color(0xFF6A635D), onTap: onAvisar ?? () {}),
          ]),
      ]),
    );
  }

  String _status(Map<String, dynamic> c) {
    // 2026-08-25: la clase cancelada por el estudio se ve como tal.
    if (c['cancelada'] == true) return 'Cancelada';
    final dt = DateTime.tryParse(c['fecha']?.toString() ?? '');
    if (dt == null) return 'Programada';
    final now = DateTime.now();
    if (dt.isBefore(now) && now.difference(dt).inMinutes < 90) return 'En curso';
    if (dt.difference(now).inHours < 8) return 'Confirmada';
    return 'Programada';
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'Cancelada':
        return const Color(0xFFF1F1F1);
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

/// Bottom sheet de "Mandar aviso": elegir clase(s), escribir y enviar.
///
/// El envío entero lo resuelve el RPC `enviar_aviso_estudio`: valida
/// permisos, aplica el tope mensual de generales, deduplica destinatarios y
/// decide a quién le corresponde canal externo. Acá solo se arma el pedido y
/// se muestra el resultado.
class _AvisoSheet extends StatefulWidget {
  final List<Map<String, dynamic>> clases;
  final Set<int> preseleccionadas;
  final String estudioNombre;

  /// `{max, usados, restantes, reinicia}` del mes en curso.
  final Map<String, dynamic>? cupoInicial;

  final Future<int> Function(List<int>) contarAlumnos;
  final Future<ResultadoAviso> Function(List<int>, String, String) onEnviar;

  const _AvisoSheet({
    required this.clases,
    required this.preseleccionadas,
    required this.estudioNombre,
    required this.cupoInicial,
    required this.contarAlumnos,
    required this.onEnviar,
  });

  @override
  State<_AvisoSheet> createState() => _AvisoSheetState();
}

class _AvisoSheetState extends State<_AvisoSheet> {
  final _ctrl = TextEditingController();
  late Set<int> _seleccionadas;
  bool _urgente = false;
  bool _enviando = false;
  int _alumnos = 0;
  Map<String, dynamic>? _cupo;

  /// Plantillas para los casos que el estudio manda una y otra vez. Los
  /// `[corchetes]` son huecos a completar: al tocar la plantilla se
  /// selecciona el primero para que escribir encima lo reemplace.
  static const _rapidosUrgentes = [
    'La clase de hoy se cancela. Sus créditos serán devueltos.',
    'La clase se reprograma para [fecha]. Confirmen si pueden asistir.',
    'La profe de hoy no puede dar la clase. Se cancela y se devuelven '
        'los créditos.',
  ];

  static const _rapidosGenerales = [
    'Recordatorio: clase hoy a las [hora]. ¡Las esperamos!',
    'Traigan mat y ropa cómoda.',
    'La clase de hoy es en [lugar].',
    'Hay lugar disponible en la clase de hoy. ¡Pueden traer una amiga!',
    '¡Quedan pocos lugares para la clase de mañana! Reserven ya.',
    'Nueva clase disponible esta semana. ¡Mirá los horarios en la app!',
    'Gracias por venir hoy. ¡Las esperamos la próxima!',
    'Este mes tenemos novedades. ¡Entrá a la app para ver!',
    '¿Traés una amiga? Compartí Aura y sumamos más clases juntas.',
    'Recordá cancelar con tiempo para no perder tus créditos.',
    'Nuevo horario disponible. Reservá tu lugar antes de que se llene.',
  ];

  @override
  void initState() {
    super.initState();
    _cupo = widget.cupoInicial;
    _seleccionadas = {...widget.preseleccionadas};
    if (_seleccionadas.isEmpty && widget.clases.isNotEmpty) {
      _seleccionadas.add((widget.clases.first['id'] as num).toInt());
    }
    _refrescarAlumnos();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _refrescarAlumnos() async {
    final n = await widget.contarAlumnos(_seleccionadas.toList());
    if (mounted) setState(() => _alumnos = n);
  }

  int get _restantes =>
      (_cupo?['restantes'] as num?)?.toInt() ?? AvisoAlumnosService.maxClasesPorEnvio;

  /// Un general más no entra si ya se usaron los del mes. Los urgentes
  /// nunca se bloquean: son operativos.
  bool get _bloqueadoPorCupo => !_urgente && _restantes <= 0;

  void _usarPlantilla(String texto, {required bool urgente}) {
    final hueco = RegExp(r'\[[^\]]+\]').firstMatch(texto);
    setState(() {
      _urgente = urgente;
      _ctrl.text = texto;
      _ctrl.selection = hueco != null
          ? TextSelection(baseOffset: hueco.start, extentOffset: hueco.end)
          : TextSelection.collapsed(offset: texto.length);
    });
  }

  void _toggleClase(int id) {
    setState(() {
      if (_seleccionadas.contains(id)) {
        if (_seleccionadas.length > 1) _seleccionadas.remove(id);
      } else if (_seleccionadas.length <
          AvisoAlumnosService.maxClasesPorEnvio) {
        _seleccionadas.add(id);
      }
    });
    _refrescarAlumnos();
  }

  Future<void> _enviar() async {
    if (_ctrl.text.trim().isEmpty || _seleccionadas.isEmpty) return;
    setState(() => _enviando = true);
    try {
      final res = await widget.onEnviar(
        _seleccionadas.toList(),
        _ctrl.text.trim(),
        _urgente ? 'urgente' : 'aviso_general',
      );
      if (!mounted) return;

      if (res.limiteMensual) {
        setState(() => _cupo = res.cupo ?? _cupo);
        await _mostrarLimite();
        return;
      }

      if (!res.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.error ?? 'No se pudo enviar el aviso.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      Navigator.of(context).pop();
      final detalle = res.emailsEnviados > 0
          ? ' · ${res.emailsEnviados} por email'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✓ Aviso enviado a ${res.destinatarios} alumna'
            '${res.destinatarios == 1 ? '' : 's'}$detalle',
          ),
          backgroundColor: const Color(0xFF1A1A1A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _mostrarLimite() async {
    final reinicia = _cupo?['reinicia']?.toString() ?? 'el mes que viene';
    final max = (_cupo?['max'] as num?)?.toInt() ?? 3;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Llegaste al límite del mes'),
        content: Text(
          'Ya enviaste los $max avisos generales de este mes. Este límite '
          'cuida a tus alumnas de recibir demasiadas notificaciones. '
          'Los avisos urgentes (cancelaciones o cambios de horario) no '
          'tienen límite. Vas a poder enviar avisos generales de nuevo '
          'el $reinicia.',
          style: const TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mensaje = _ctrl.text.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20, 12, 20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const Text(
              'Mandar aviso',
              style: TextStyle(
                color: AppColors.black,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$_alumnos alumna${_alumnos == 1 ? '' : 's'} con reserva '
              'confirmada',
              style: const TextStyle(color: Color(0xFF8F877F), fontSize: 13),
            ),
            const SizedBox(height: 16),

            // ── Selección de clases ────────────────────────────────────
            Text(
              'CLASES (${_seleccionadas.length}/'
              '${AvisoAlumnosService.maxClasesPorEnvio})',
              style: const TextStyle(
                color: Color(0xFF8F877F),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 148),
              child: SingleChildScrollView(
                child: Column(
                  children: widget.clases.map((c) {
                    final id = (c['id'] as num).toInt();
                    final sel = _seleccionadas.contains(id);
                    final f =
                        DateTime.tryParse(c['fecha']?.toString() ?? '');
                    final cuando = f == null
                        ? ''
                        : DateFormat("EEE d/M · HH:mm", 'es').format(f);
                    return CheckboxListTile(
                      value: sel,
                      onChanged: (_) => _toggleClase(id),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.primary,
                      title: Text(
                        c['nombre']?.toString() ?? 'Clase',
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        cuando,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8F877F),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Mensajes rápidos ───────────────────────────────────────
            const Text(
              'MENSAJES RÁPIDOS',
              style: TextStyle(
                color: Color(0xFF8F877F),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            _PlantillaFila(
              etiqueta: '🚨  Urgentes',
              plantillas: _rapidosUrgentes,
              urgente: true,
              seleccionada: mensaje,
              onTap: (t) => _usarPlantilla(t, urgente: true),
            ),
            const SizedBox(height: 8),
            _PlantillaFila(
              etiqueta: '📢  Generales',
              plantillas: _rapidosGenerales,
              urgente: false,
              seleccionada: mensaje,
              onTap: (t) => _usarPlantilla(t, urgente: false),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _ctrl,
              maxLines: 4,
              minLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText:
                    'Ej: La clase de hoy se traslada al salón 2. ¡Los esperamos!',
                hintStyle:
                    const TextStyle(color: Color(0xFFB0A8A0), fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFF7F5F2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 14),

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
            const SizedBox(height: 10),

            // Cupo: solo importa para los generales.
            if (!_urgente && _cupo != null)
              Text(
                _restantes > 0
                    ? 'Te quedan $_restantes aviso'
                    '${_restantes == 1 ? '' : 's'} general'
                    '${_restantes == 1 ? '' : 'es'} este mes.'
                    : 'Ya usaste los avisos generales del mes. '
                        'Los urgentes no tienen límite.',
                style: TextStyle(
                  color: _restantes > 0
                      ? const Color(0xFF8F877F)
                      : AppColors.error,
                  fontSize: 12,
                ),
              ),

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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'URGENTE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      mensaje,
                      style: const TextStyle(
                        color: Color(0xFFF7F5F2),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: (_enviando ||
                        mensaje.isEmpty ||
                        _seleccionadas.isEmpty ||
                        _bloqueadoPorCupo)
                    ? null
                    : _enviar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: _enviando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        _bloqueadoPorCupo
                            ? 'Sin avisos generales este mes'
                            : 'Enviar a $_alumnos alumna'
                                '${_alumnos == 1 ? '' : 's'}',
                      ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _enviando ? null : () => Navigator.of(context).pop(),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Color(0xFF8F877F)),
                ),
              ),
            ),
          ],
        ),
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

/// Badge naranja "Tu clase" para las clases donde la profe logueada es la
/// instructora (F5).
class _TuClaseBadge extends StatelessWidget {
  const _TuClaseBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Tu clase',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HorarioFijoCard extends StatelessWidget {
  final Map<String, dynamic> horario;
  final VoidCallback onEdit, onDelete;
  final ValueChanged<bool> onToggle;
  final bool esMiClase;
  const _HorarioFijoCard({required this.horario, required this.onEdit, required this.onDelete, required this.onToggle, this.esMiClase = false});
  @override
  Widget build(BuildContext context) {
    final nombre = horario['nombre']?.toString() ?? 'Clase';
    final instructor = horario['instructor']?.toString();
    final hora = horario['hora_inicio']?.toString() ?? '08:00';
    final duracion = (horario['duracion_min'] as num?)?.toInt() ?? 60;
    final cupos = (horario['lugares_total'] as num?)?.toInt() ?? 12;
    final creditos = (horario['creditos'] as num?)?.toInt() ?? 10;
    final sala = horario['sala']?.toString();
    // Muestra hasta 2 categorías + "+N" para no romper la fila.
    final cats = _parseCategorias(horario);
    final cat = cats.isEmpty
        ? null
        : (cats.length <= 2
            ? cats.join(' · ')
            : '${cats.take(2).join(' · ')} +${cats.length - 2}');
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
              Row(children: [
                Flexible(child: Text(nombre, style: const TextStyle(color: AppColors.black, fontSize: 15, fontWeight: FontWeight.w700))),
                if (esMiClase) ...[
                  const SizedBox(width: 8),
                  const _TuClaseBadge(),
                ],
              ]),
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
  /// Solo se muestra si la clase está cancelada: la vuelve reservable.
  final VoidCallback? onReactivar;
  // false para la profe: solo edita, no puede cancelar (borrar) la clase.
  final bool puedeEditar;
  /// Cuántas esperan lugar en esta clase. 0 = no se muestra nada.
  final int enEspera;
  const _ClaseDetalleSheet({required this.clase, required this.onEdit, required this.onCancel, this.onAvisar, this.onReactivar, this.puedeEditar = true, this.enEspera = 0});

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
    // Los tres campos de "Descripción, sala y fotos" ya venían en el mapa
    // (`getClasesDeEstudio` hace `.select()`), pero esta hoja nunca los
    // dibujaba: el estudio los cargaba y no los veía en ningún lado. Ahora
    // que el bloque dejó de estar plegado (25/8) se empiezan a llenar.
    final sala = (clase['sala'] ?? '').toString().trim();
    final descripcion = (clase['descripcion'] ?? '').toString().trim();
    final incluye = (clase['incluye'] ?? '').toString().trim();
    final instructorDesc =
        (clase['instructor_descripcion'] ?? '').toString().trim();
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF7F5F2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      // Con descripción y "qué incluye" el contenido puede pasarse de alto:
      // sin scroll la hoja se desborda (raya amarilla y texto cortado). Se
      // limita a 85% de la pantalla y adentro scrollea.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: SingleChildScrollView(
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
        if (enEspera > 0)
          _DetailRow(
            icon: Icons.hourglass_bottom_rounded,
            text: enEspera == 1
                ? '1 persona esperando un lugar'
                : '$enEspera personas esperando un lugar',
          ),
        _DetailRow(icon: Icons.timer_outlined, text: '$duracion min · $creditos créditos'),
        if (sala.isNotEmpty)
          _DetailRow(icon: Icons.meeting_room_outlined, text: sala),
        if (instructorDesc.isNotEmpty)
          _BloqueTexto(titulo: 'Sobre quien la da', texto: instructorDesc),
        if (descripcion.isNotEmpty)
          _BloqueTexto(titulo: 'Descripción', texto: descripcion),
        if (incluye.isNotEmpty)
          _BloqueTexto(titulo: 'Qué incluye', texto: incluye),
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
        // Una clase cancelada no se edita: editarla la dejaba igual de
        // cancelada e irreservable, y el estudio creía que la había
        // "arreglado" (revisión del 25/8). Se reactiva explícitamente.
        if (clase['cancelada'] == true) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Esta clase está cancelada: nadie puede reservarla. Si querés volver a ofrecerla, reactivala (las alumnas que ya recibieron sus créditos tienen que anotarse de nuevo).',
              style: TextStyle(color: Color(0xFF8F877F), fontSize: 12, height: 1.35),
            ),
          ),
          if (puedeEditar && onReactivar != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onReactivar,
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text('Reactivar clase'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF43A047), foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
        ] else
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Editar'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary), padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
          // Cancelar (borrar) la clase es solo de admin/dueña.
          if (puedeEditar) ...[
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text('Cancelar clase'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF44336), foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ],
        ]),
      ]),
      ),
    );
  }
}

/// Un campo largo de la clase (descripción, qué incluye…) con su título.
/// Va en la hoja de detalle, debajo de los renglones cortos con ícono.
class _BloqueTexto extends StatelessWidget {
  final String titulo, texto;
  const _BloqueTexto({required this.titulo, required this.texto});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titulo.toUpperCase(), style: const TextStyle(color: Color(0xFF8F877F), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      const SizedBox(height: 4),
      Text(texto, style: const TextStyle(color: Color(0xFF5F5953), fontSize: 14, height: 1.4)),
    ]),
  );
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

/// Botón de selección de tipo de clase (Clase vs Workshop/Evento).
class _TipoOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _TipoOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFE0DAD3),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: selected ? AppColors.primary : AppColors.grey,
                size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? AppColors.primary : AppColors.grey,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
  final ValueChanged<String>? onChanged;
  const _AuraTextField({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.maxLines = 1,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 15),
      decoration: _formInputDecoration(label: label, hint: hint),
    );
  }
}

/// Campo de instructor (F5): texto libre + botón-dropdown con las profes del
/// estudio. Elegir una completa el campo; igual se puede escribir a mano.
class _InstructorField extends StatelessWidget {
  final TextEditingController controller;
  final List<String> profes;
  const _InstructorField({required this.controller, required this.profes});

  @override
  Widget build(BuildContext context) {
    const field = 'Instructor/a';
    if (profes.isEmpty) {
      return _AuraTextField(
        controller: controller,
        label: field,
        hint: 'Florencia Pérez',
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: _AuraTextField(
            controller: controller,
            label: field,
            hint: 'Elegí una profe o escribí un nombre',
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: PopupMenuButton<String>(
            tooltip: 'Elegir profe',
            icon: const Icon(Icons.arrow_drop_down_circle_outlined,
                color: AppColors.primary),
            onSelected: (v) => controller.text = v,
            itemBuilder: (_) => profes
                .map((p) => PopupMenuItem<String>(value: p, child: Text(p)))
                .toList(),
          ),
        ),
      ],
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

/// Fila de icono + texto del resumen previo a generar la grilla.
class _FilaResumenGrilla extends StatelessWidget {
  final IconData icono;
  final String texto;
  const _FilaResumenGrilla({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                  color: AppColors.black, fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Formatea pesos con separador de miles: 12345 -> "$12.345".
String _fmtPesosCr(int v) {
  final s = v.abs().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}\$$buf';
}

/// Campo de créditos por clase en el panel del estudio: SIEMPRE de solo
/// lectura. El precio lo define Aura desde el backoffice y lo calcula la base
/// (`calcular_precio_clase`); acá solo lo mostramos junto con el motivo.
///
///   modo fijo  -> "Precio del estudio · 11 créditos"
///   modo rango -> "⚡ Horario pico · 16 créditos"
///
/// [porHorario] es para el form de grilla, donde se generan clases en varios
/// días y franjas: ahí no hay un número único que mostrar, así que explicamos
/// la regla.
class _PrecioCalculadoField extends StatelessWidget {
  final Map<String, dynamic>? estudio;
  final int dia; // isodow 1=lunes..7=domingo
  final TimeOfDay hora;
  final bool porHorario;

  const _PrecioCalculadoField({
    required this.estudio,
    required this.dia,
    required this.hora,
    this.porHorario = false,
  });

  @override
  Widget build(BuildContext context) {
    if (estudio == null) {
      return const _AuraReadOnlyField(
        label: 'Créditos por clase',
        value: '—',
        caption: 'Cargando la configuración de precios…',
      );
    }

    final cfg = PricingCalculator.configDe(estudio);
    if (!cfg.configurado) {
      return const _AuraReadOnlyField(
        label: 'Créditos por clase',
        value: 'Sin configurar',
        caption: 'Aura todavía no definió el precio de este estudio. '
            'Escribinos para activarlo.',
      );
    }

    final horaTxt =
        '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}';
    final res = PricingCalculator.calcular(
      estudio: estudio,
      hora: horaTxt,
      dia: dia,
    );
    final creditos = res.creditos ?? 0;

    // Grilla en modo rango: cada clase generada toma el precio de su franja.
    final variaPorHorario = porHorario && cfg.esRango;

    final Color badgeColor;
    switch (res.tipo) {
      case TipoPrecio.pico:
        badgeColor = const Color(0xFFE8763A);
        break;
      case TipoPrecio.valle:
        badgeColor = const Color(0xFF4CAF50);
        break;
      default:
        badgeColor = AppColors.primary;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEDE7E1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Créditos por clase',
                style: TextStyle(
                  color: AppColors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (variaPorHorario)
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text(
                        'Según el horario',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${cfg.min} a ${cfg.max} cr.',
                      style: const TextStyle(
                        color: AppColors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        res.badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$creditos créditos',
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
                variaPorHorario
                    ? 'Cada clase de la grilla toma el precio de su día y '
                        'horario: valle en los flojos, pico en el resto.'
                    : res.detalle,
                style: const TextStyle(
                    color: AppColors.grey, fontSize: 12, height: 1.35),
              ),
              if (!variaPorHorario) ...[
                const SizedBox(height: 8),
                _VosRecibis(creditos: creditos, estudio: estudio),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// "Vos recibís: $X" con la fórmula real de liquidación (valor_credito del
/// estudio, comisión real y período de gracia por fecha_inicio_cobro).
class _VosRecibis extends StatelessWidget {
  final int creditos;
  final Map<String, dynamic>? estudio;
  const _VosRecibis({required this.creditos, required this.estudio});

  @override
  Widget build(BuildContext context) {
    if (creditos <= 0) return const SizedBox.shrink();
    final neto = Liquidacion.netoDeCreditos(creditos, estudio);
    final enGracia = !Liquidacion.cobraComision(estudio);
    return Row(
      children: [
        const Icon(Icons.account_balance_wallet_outlined,
            size: 15, color: AppColors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            enGracia
                ? 'Vos recibís: ${_fmtPesosCr(neto)} (sin comisión por ahora)'
                : 'Vos recibís: ${_fmtPesosCr(neto)}',
            style: const TextStyle(
                color: AppColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// ── Widgets nuevos para M1 / M2 / M3 ────────────────────────────────────────

class _ViewToggle extends StatelessWidget {
  final bool gridView;
  final ValueChanged<bool> onChanged;
  const _ViewToggle({required this.gridView, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ViewToggleButton(
            icon: Icons.view_list_rounded,
            selected: !gridView,
            onTap: () => onChanged(false),
            tooltip: 'Vista lista',
          ),
          _ViewToggleButton(
            icon: Icons.grid_view_rounded,
            selected: gridView,
            onTap: () => onChanged(true),
            tooltip: 'Vista grilla',
          ),
        ],
      ),
    );
  }
}

class _ViewToggleButton extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String tooltip;
  const _ViewToggleButton({
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 44,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: selected ? Colors.white : const Color(0xFF8F877F),
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _ClaseGridCard extends StatelessWidget {
  final Map<String, dynamic> clase;
  final bool esMiClase;
  const _ClaseGridCard({required this.clase, this.esMiClase = false});

  static const _weekday = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.tryParse(clase['fecha']?.toString() ?? '');
    final hora = dt != null ? DateFormat('HH:mm').format(dt) : '--:--';
    final diaStr = dt != null
        ? '${_weekday[dt.weekday - 1]} ${dt.day}'
        : '—';
    final nombre = clase['nombre']?.toString() ?? 'Clase';
    final total = (clase['lugares_total'] as num?)?.toInt() ?? 0;
    final disp = ((clase['lugares_disponibles'] ??
            clase['lugares_ disponibles']) as num?)
            ?.toInt() ??
        0;
    final ocupados =
        total > 0 ? (total - disp).clamp(0, total) : 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.blackSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  hora,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  diaStr.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8F877F),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (clase['cancelada'] == true)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                'CANCELADA',
                style: TextStyle(
                  color: Color(0xFF8F877F),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          Text(
            nombre,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.black,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          if (esMiClase) ...[
            const SizedBox(height: 6),
            const _TuClaseBadge(),
          ],
          const Spacer(),
          Row(
            children: [
              const Icon(Icons.people_outline_rounded,
                  color: Color(0xFF8F877F), size: 14),
              const SizedBox(width: 4),
              Text(
                '$ocupados / $total cupos',
                style: const TextStyle(
                  color: Color(0xFF8F877F),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OpcionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const _OpcionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.black;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          // Tap target generoso para iPad / mobile (~56 px).
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fila de plantillas de aviso, con scroll horizontal para no comerse el
/// alto del bottom sheet (son 11 generales).
class _PlantillaFila extends StatelessWidget {
  final String etiqueta;
  final List<String> plantillas;
  final bool urgente;

  /// Texto actual del campo, para marcar cuál plantilla está en uso.
  final String seleccionada;
  final ValueChanged<String> onTap;

  const _PlantillaFila({
    required this.etiqueta,
    required this.plantillas,
    required this.urgente,
    required this.seleccionada,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final acento = urgente ? AppColors.primary : const Color(0xFF6A635D);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta,
          style: TextStyle(
            color: acento,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: plantillas.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final texto = plantillas[i];
              final activa = seleccionada == texto.trim();
              return GestureDetector(
                onTap: () => onTap(texto),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: activa
                        ? acento.withValues(alpha: 0.12)
                        : const Color(0xFFF7F5F2),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: activa ? acento : const Color(0xFFEDE7E1),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      // Recortado: el texto completo va al campo editable.
                      texto.length > 38
                          ? '${texto.substring(0, 36)}…'
                          : texto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: activa ? acento : const Color(0xFF6A635D),
                        fontSize: 12,
                        fontWeight:
                            activa ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Máximo de categorías por clase o workshop. Espejado en el trigger
/// `sync_categorias_clase` de la base, que rechaza el insert si se pasa.
const int kMaxCategoriasClase = 5;

/// Lee `categorias` (text[]) de una clase u horario fijo, con fallback al
/// escalar `categoria` para las filas que todavía no migraron. Mismo
/// criterio que `Estudio.parseCategorias`.
List<String> _parseCategorias(Map<String, dynamic> row) =>
    Estudio.parseCategorias(row);


/// Precio de un workshop expresado en PESOS que recibe el estudio.
///
/// El estudio no elige créditos: dice cuánta plata quiere recibir y Aura
/// deriva el precio en créditos sumando su comisión. Antes este campo era
/// "Precio en créditos" libre, sin tope: se podía cargar un workshop de 9999
/// créditos sin que nadie lo notara.
class _WorkshopPrecioField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;
  final Map<String, dynamic>? estudio;

  const _WorkshopPrecioField({
    required this.controller,
    required this.onChanged,
    required this.estudio,
  });

  @override
  Widget build(BuildContext context) {
    final monto =
        int.tryParse(controller.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final creditos = Liquidacion.creditosDeWorkshop(monto, estudio);
    final money = NumberFormat.currency(
      locale: 'es_AR',
      symbol: r'$',
      decimalDigits: 0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AuraTextField(
          controller: controller,
          label: 'Cuánto querés recibir (pesos)',
          hint: '40000',
          keyboardType: TextInputType.number,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1E8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            monto <= 0
                ? 'Poné el monto que querés recibir y calculamos los créditos.'
                : 'Recibís ${money.format(monto)} · '
                    'Cuesta $creditos crédito${creditos == 1 ? '' : 's'}',
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}


// ─── Grilla: horarios por día ────────────────────────────────────────────────

const Map<int, String> _kDiaCorto = {
  1: 'Lun', 2: 'Mar', 3: 'Mié', 4: 'Jue', 5: 'Vie', 6: 'Sáb', 7: 'Dom',
};

int _minutoDe(TimeOfDay t) => t.hour * 60 + t.minute;

String _hhmmTop(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Primera hora cargada (para el precio "de arranque" del formulario). Si no
/// hay ninguna todavía, 08:00: es solo un valor inicial, el trigger de la base
/// le pone a cada horario el precio de su propia franja.
TimeOfDay _primeraHora(Set<int> dias, Map<int, List<TimeOfDay>> horarios) {
  for (final d in dias.toList()..sort()) {
    final l = horarios[d];
    if (l != null && l.isNotEmpty) {
      final copia = List<TimeOfDay>.of(l)
        ..sort((a, b) => _minutoDe(a).compareTo(_minutoDe(b)));
      return copia.first;
    }
  }
  return const TimeOfDay(hour: 8, minute: 0);
}

int _totalHorarios(Set<int> dias, Map<int, List<TimeOfDay>> horarios) {
  var n = 0;
  for (final d in dias) {
    n += (horarios[d] ?? const []).map(_minutoDe).toSet().length;
  }
  return n;
}

/// Time picker SIEMPRE en 24 h, sin importar el locale del teléfono. En 12 h
/// una clase de las 13:30 se lee "1:30" y ya confundió a un estudio (25/8).
Widget _builder24h(BuildContext c, Widget? child) => MediaQuery(
      data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
      child: child ?? const SizedBox.shrink(),
    );

Future<TimeOfDay?> _pickHora24(BuildContext ctx, TimeOfDay initial) {
  return showTimePicker(
    context: ctx,
    initialTime: initial,
    builder: _builder24h,
  );
}

/// Una fila de chips por día marcado, con "+ agregar" y "copiar a…", más el
/// atajo "Completar un rango…" que rellena las filas. Muta [horarios] en el
/// lugar y avisa con [onChanged] para que el sheet se redibuje.
class _HorariosPorDiaEditor extends StatelessWidget {
  final List<int> dias;
  final Map<int, List<TimeOfDay>> horarios;
  final int duracionMin;
  final VoidCallback onChanged;
  /// Texto del chip. Por defecto la hora; el formulario le pasa hora + precio
  /// por franja para que el estudio VEA el ajuste pico/valle antes de crear.
  final String Function(int dia, TimeOfDay t)? etiqueta;
  const _HorariosPorDiaEditor({
    required this.dias,
    required this.horarios,
    required this.duracionMin,
    required this.onChanged,
    this.etiqueta,
  });

  List<TimeOfDay> _lista(int d) => horarios.putIfAbsent(d, () => []);

  void _agregar(int d, TimeOfDay t) {
    final l = _lista(d);
    if (l.any((x) => _minutoDe(x) == _minutoDe(t))) return;
    l.add(t);
    l.sort((a, b) => _minutoDe(a).compareTo(_minutoDe(b)));
    onChanged();
  }

  Future<void> _copiarA(BuildContext ctx, int origen) async {
    final destinos = dias.where((d) => d != origen).toList();
    if (destinos.isEmpty) return;
    final elegidos = <int>{...destinos};
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => StatefulBuilder(builder: (dctx, setS) {
        return AlertDialog(
          title: Text('Copiar ${_kDiaCorto[origen]} a…'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final d in destinos)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppColors.primary,
                  value: elegidos.contains(d),
                  title: Text(_kDiaCorto[d] ?? ''),
                  subtitle: (horarios[d] ?? const []).isEmpty
                      ? null
                      : const Text('reemplaza lo que tiene',
                          style: TextStyle(fontSize: 11)),
                  onChanged: (v) => setS(() {
                    if (v == true) {
                      elegidos.add(d);
                    } else {
                      elegidos.remove(d);
                    }
                  }),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Volver')),
            ElevatedButton(
              onPressed:
                  elegidos.isEmpty ? null : () => Navigator.pop(dctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              child: const Text('Copiar'),
            ),
          ],
        );
      }),
    );
    if (ok != true) return;
    final src = List<TimeOfDay>.of(_lista(origen));
    for (final d in elegidos) {
      horarios[d] = List<TimeOfDay>.of(src);
    }
    onChanged();
  }

  Future<void> _completarRango(BuildContext ctx) async {
    if (dias.isEmpty) return;
    var desde = const TimeOfDay(hour: 7, minute: 0);
    var hasta = const TimeOfDay(hour: 21, minute: 0);
    var cada = duracionMin;
    final elegidos = <int>{...dias};
    int franjas() {
      final a = _minutoDe(desde), b = _minutoDe(hasta);
      if (cada <= 0 || b <= a) return 0;
      var n = 0;
      for (var t = a; t + cada <= b; t += cada) {
        n++;
      }
      return n;
    }

    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => StatefulBuilder(builder: (dctx, setS) {
        final n = franjas();
        return AlertDialog(
          title: const Text('Completar un rango'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Agrega una clase cada X minutos entre dos horas. Después podés sacar las que no quieras.',
                  style: TextStyle(color: AppColors.grey, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _AuraTapField(
                      label: 'Desde',
                      value: _hhmmTop(desde),
                      icon: Icons.schedule_rounded,
                      onTap: () async {
                        final p = await _pickHora24(dctx, desde);
                        if (p != null) setS(() => desde = p);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _AuraTapField(
                      label: 'Hasta',
                      value: _hhmmTop(hasta),
                      icon: Icons.schedule_rounded,
                      onTap: () async {
                        final p = await _pickHora24(dctx, hasta);
                        if (p != null) setS(() => hasta = p);
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                _AuraDropdown<int>(
                  label: 'Una clase cada',
                  value: cada,
                  items: const [
                    DropdownMenuItem(value: 30, child: Text('30 min')),
                    DropdownMenuItem(value: 45, child: Text('45 min')),
                    DropdownMenuItem(value: 60, child: Text('60 min')),
                    DropdownMenuItem(value: 75, child: Text('75 min')),
                    DropdownMenuItem(value: 90, child: Text('90 min')),
                    DropdownMenuItem(value: 120, child: Text('2 h')),
                  ],
                  onChanged: (v) => setS(() => cada = v ?? cada),
                ),
                const SizedBox(height: 10),
                const Text('Para',
                    style: TextStyle(
                        color: Color(0xFF6E6761),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in dias)
                      FilterChip(
                        label: Text(_kDiaCorto[d] ?? ''),
                        selected: elegidos.contains(d),
                        selectedColor: const Color(0xFFFFF1E8),
                        checkmarkColor: AppColors.primary,
                        onSelected: (v) => setS(() {
                          if (v) {
                            elegidos.add(d);
                          } else {
                            elegidos.remove(d);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  n == 0
                      ? 'Con esos valores no entra ninguna clase.'
                      : '$n clase${n != 1 ? 's' : ''} por día: ${_hhmmTop(desde)}'
                          '${n > 1 ? ' … ${_hhmmTop(TimeOfDay(hour: (_minutoDe(desde) + cada * (n - 1)) ~/ 60, minute: (_minutoDe(desde) + cada * (n - 1)) % 60))}' : ''}',
                  style: TextStyle(
                    color: n == 0 ? Colors.red : AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Volver')),
            ElevatedButton(
              onPressed: (n == 0 || elegidos.isEmpty)
                  ? null
                  : () => Navigator.pop(dctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              child: Text(n == 0 ? 'Completar' : 'Agregar $n por día'),
            ),
          ],
        );
      }),
    );
    if (ok != true) return;
    final a = _minutoDe(desde), b = _minutoDe(hasta);
    for (final d in elegidos) {
      for (var t = a; t + cada <= b; t += cada) {
        _agregar(d, TimeOfDay(hour: t ~/ 60, minute: t % 60));
      }
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Horarios',
                style: TextStyle(
                  color: Color(0xFF6E6761),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (dias.isNotEmpty)
              TextButton.icon(
                onPressed: () => _completarRango(context),
                icon: const Icon(Icons.playlist_add_rounded, size: 18),
                label: const Text('Completar un rango…'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        if (dias.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Marcá al menos un día.',
                style: TextStyle(color: Color(0xFF9A928B), fontSize: 13)),
          ),
        for (final d in dias) ...[
          const SizedBox(height: 8),
          _FilaDia(
            dia: d,
            horarios: List<TimeOfDay>.of(_lista(d)),
            etiqueta: (t) => etiqueta?.call(d, t) ?? _hhmmTop(t),
            puedeCopiar: dias.length > 1,
            onAgregar: () async {
              final l = _lista(d);
              final p = await _pickHora24(
                  context,
                  l.isEmpty
                      ? const TimeOfDay(hour: 8, minute: 0)
                      : l.last);
              if (p != null) _agregar(d, p);
            },
            onQuitar: (t) {
              _lista(d).removeWhere((x) => _minutoDe(x) == _minutoDe(t));
              onChanged();
            },
            onCopiar: () => _copiarA(context, d),
          ),
        ],
      ],
    );
  }
}

class _FilaDia extends StatelessWidget {
  final int dia;
  final List<TimeOfDay> horarios;
  final String Function(TimeOfDay) etiqueta;
  final bool puedeCopiar;
  final VoidCallback onAgregar;
  final void Function(TimeOfDay) onQuitar;
  final VoidCallback onCopiar;
  const _FilaDia({
    required this.dia,
    required this.horarios,
    required this.etiqueta,
    required this.puedeCopiar,
    required this.onAgregar,
    required this.onQuitar,
    required this.onCopiar,
  });

  @override
  Widget build(BuildContext context) {
    final vacio = horarios.isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: _kFieldFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: vacio ? const Color(0xFFF2B8A5) : const Color(0xFFE5E0DA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _kDiaCorto[dia] ?? '',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Expanded(
            child: vacio
                ? const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('sin horarios',
                        style: TextStyle(
                            color: Color(0xFFC0392B), fontSize: 13)),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in horarios)
                        InputChip(
                          label: Text(etiqueta(t)),
                          labelStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.black),
                          backgroundColor: AppColors.white,
                          side: const BorderSide(color: Color(0xFFE5E0DA)),
                          visualDensity: VisualDensity.compact,
                          deleteIconColor: const Color(0xFF9A928B),
                          onDeleted: () => onQuitar(t),
                        ),
                    ],
                  ),
          ),
          IconButton(
            tooltip: 'Agregar horario',
            onPressed: onAgregar,
            icon: const Icon(Icons.add_circle_outline_rounded,
                color: AppColors.primary),
            visualDensity: VisualDensity.compact,
          ),
          if (puedeCopiar)
            IconButton(
              tooltip: 'Copiar a otros días',
              onPressed: vacio ? null : onCopiar,
              icon: const Icon(Icons.copy_all_rounded),
              color: const Color(0xFF6E6761),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

/// SOLO PARA TESTS: expone el editor privado de horarios por día para
/// poder pumpearlo en un widget test sin levantar la pantalla entera.
@visibleForTesting
Widget debugHorariosPorDiaEditor({
  required List<int> dias,
  required Map<int, List<TimeOfDay>> horarios,
  int duracionMin = 60,
  VoidCallback? onChanged,
}) =>
    _HorariosPorDiaEditor(
      dias: dias,
      horarios: horarios,
      duracionMin: duracionMin,
      onChanged: onChanged ?? () {},
    );
