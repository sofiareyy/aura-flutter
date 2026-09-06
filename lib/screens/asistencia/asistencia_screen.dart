import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../services/estudio_admin_service.dart';
import '../../widgets/ancho_maximo.dart';

class AsistenciaScreen extends StatefulWidget {
  const AsistenciaScreen({super.key});

  @override
  State<AsistenciaScreen> createState() => _AsistenciaScreenState();
}

class _AsistenciaScreenState extends State<AsistenciaScreen> {
  final _estudioService = EstudioAdminService();
  List<Map<String, dynamic>> _clases = [];
  List<Map<String, dynamic>> _asistentes = [];
  Map<String, dynamic>? _claseSeleccionada;
  bool _loading = true;
  DateTime _now = DateTime.now();
  Timer? _bannerTimer;
  Timer? _syncTimer;
  bool _isOffline = false;

  // Scanner
  late bool _usarCamara;
  bool _procesando = false;
  final _qrController = TextEditingController();
  final _qrFocusNode = FocusNode();
  MobileScannerController? _cameraController;

  // Debug del ultimo escaneo — visible en pantalla mientras estamos
  // depurando el bug critico de "QR invalido". Quitar cuando este resuelto.
  String? _debugRaw;
  String? _debugNormalized;
  String? _debugResult;
  DateTime? _debugAt;

  // Busqueda en lista de asistentes (filtra por nombre/email)
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _usarCamara = !kIsWeb;
    if (_usarCamara) _cameraController = MobileScannerController();
    _cargar();
    _bannerTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _syncTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkSync(),
    );
    _searchCtrl.addListener(() => setState(() {}));
  }

  List<Map<String, dynamic>> get _asistentesFiltrados {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _asistentes;
    return _asistentes.where((a) {
      final user = a['usuario'] as Map<String, dynamic>?;
      final nombre = (user?['nombre']?.toString() ?? '').toLowerCase();
      final email = (user?['email']?.toString() ?? '').toLowerCase();
      return nombre.contains(q) || email.contains(q);
    }).toList();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _syncTimer?.cancel();
    _qrController.dispose();
    _qrFocusNode.dispose();
    _searchCtrl.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final now = DateTime.now();
    // IMPORTANTE: solo clases del estudio ACTIVO. getClasesDeEstudio scopea por
    // usuarios.estudio_id (el estudio en el que estás parada en el panel). Antes
    // esto era un `from('clases')` sin filtro y traía clases de TODO el
    // marketplace, así que aparecían estudios ajenos para marcar asistencia.
    final clases = await _estudioService.getClasesDeEstudio(
      from: DateTime(now.year, now.month, now.day),
      limit: 50,
    );

    // "Clases activas" = las de HOY del estudio activo. Si no hay ninguna hoy,
    // _claseSeleccionada queda null y la UI muestra "Sin clases activas": no
    // auto-seleccionamos una clase de otro día (ni de otro estudio).
    // 2026-08-25 (item 14): el Build 20 filtraba SOLO HOY y dejaba la sección
    // PROXIMAS siempre vacía; 6 de 11 estudios no tenían clases hoy y veían
    // la lista en blanco. getClasesDeEstudio(from: hoy) ya recorta a
    // hoy-en-adelante, que es lo que esperan los buckets AHORA/HOY/PROXIMAS.
    final mapped = List<Map<String, dynamic>>.from(clases);
    final selected = _autoSeleccionarClase(mapped, now);
    final attendees = await _cargarAsistentes(selected);

    if (!mounted) return;
    setState(() {
      _clases = mapped;
      _claseSeleccionada = selected;
      _asistentes = attendees;
      _loading = false;
    });

    // El scanner (cámara) queda SIEMPRE visible, aunque no haya clase activa:
    // si desaparece, el estudio piensa que algo se rompió. En modo cámara nos
    // aseguramos de que esté prendida.
    if (_usarCamara) _cameraController?.start();
  }

  // ── Buckets AHORA / HOY / PROXIMAS ────────────────────────────────────────

  /// Devuelve 'ahora' si la clase empieza en las proximas 2h o empezo hace
  /// menos de 1h, 'hoy' si es del mismo dia pero fuera de esa ventana,
  /// 'proximas' si es a futuro otro dia, null si ya termino del todo.
  String? _bucketDeClase(Map<String, dynamic> clase, DateTime now) {
    final fecha = DateTime.tryParse(clase['fecha']?.toString() ?? '');
    if (fecha == null) return null;
    final diffMin = fecha.difference(now).inMinutes;
    if (diffMin <= 120 && diffMin >= -60) return 'ahora';
    final hoyDia = DateTime(now.year, now.month, now.day);
    final fechaDia = DateTime(fecha.year, fecha.month, fecha.day);
    if (fechaDia == hoyDia) return 'hoy';
    if (fecha.isAfter(now)) return 'proximas';
    return null;
  }

  /// Si hay exactamente una clase "AHORA" la abrimos directo. Sino preferimos
  /// la primera AHORA, despues la primera HOY, despues la primera de PROXIMAS.
  Map<String, dynamic>? _autoSeleccionarClase(
    List<Map<String, dynamic>> clases,
    DateTime now,
  ) {
    if (clases.isEmpty) return null;
    final ahora = clases
        .where((c) => _bucketDeClase(c, now) == 'ahora')
        .toList();
    if (ahora.isNotEmpty) return ahora.first;
    final hoy = clases.where((c) => _bucketDeClase(c, now) == 'hoy').toList();
    if (hoy.isNotEmpty) return hoy.first;
    final proximas = clases
        .where((c) => _bucketDeClase(c, now) == 'proximas')
        .toList();
    if (proximas.isNotEmpty) return proximas.first;
    return clases.first;
  }

  // ── Cache ─────────────────────────────────────────────────────────────────

  Future<void> _guardarCache(
    int claseId,
    List<Map<String, dynamic>> asistentes,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'asistencia_cache_$claseId',
        jsonEncode(asistentes),
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _leerCache(int claseId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('asistencia_cache_$claseId');
      if (raw == null) return [];
      final decoded = jsonDecode(raw) as List;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _guardarPendienteSync(String codigoQr) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pendientes_sync') ?? '[]';
      final lista = (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      lista.add({
        'codigo_qr': codigoQr,
        'timestamp': DateTime.now().toIso8601String(),
      });
      await prefs.setString('pendientes_sync', jsonEncode(lista));
    } catch (_) {}
  }

  Future<void> _sincronizarPendientes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pendientes_sync');
      if (raw == null || raw == '[]') return;
      final lista = (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (lista.isEmpty) return;

      for (final item in lista) {
        final codigo = item['codigo_qr']?.toString() ?? '';
        if (codigo.isEmpty) continue;
        await Supabase.instance.client
            .from('reservas')
            .update({
              'estado': 'presente',
              'checked_in_at': DateTime.now().toIso8601String(),
            })
            .eq('codigo_qr', codigo);
      }

      await prefs.setString('pendientes_sync', '[]');
      if (mounted) {
        setState(() {
          _isOffline = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✓ Cambios sincronizados correctamente'),
            backgroundColor: const Color(0xFF43A047),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _checkSync() async {
    if (!_isOffline) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendientesStr = prefs.getString('pendientes_sync');
      if (pendientesStr == null || pendientesStr == '[]') {
        // No pending, just try to reload
        try {
          final attendees = await _cargarAsistentes(_claseSeleccionada);
          if (mounted)
            setState(() {
              _asistentes = attendees;
              _isOffline = false;
            });
        } catch (_) {}
        return;
      }
      await _sincronizarPendientes();
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _cargarAsistentes(
    Map<String, dynamic>? clase,
  ) async {
    if (clase == null) return [];
    final claseId = (clase['id'] as num?)?.toInt() ?? 0;
    try {
      final reservas = await Supabase.instance.client
          .from('reservas')
          .select()
          .eq('clase_id', clase['id'])
          .neq('estado', 'cancelada');

      // 2026-08-25 (item 22): una sola RPC que devuelve SOLO nombre/email de
      // alumnas con reserva en clases del estudio. Antes leía `usuarios`
      // directo, fila por fila, y la RLS lo negaba: todas salían 'Alumno'.
      // La policy provisoria de esa mañana se dropeó con esta RPC.
      final rows = List<Map<String, dynamic>>.from(reservas as List);
      final ids = rows
          .map((r) => r['usuario_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();
      final nombres = <String, Map<String, dynamic>>{};
      if (ids.isNotEmpty) {
        final res = await Supabase.instance.client.rpc(
          'estudio_nombres_alumnas',
          params: {'p_ids': ids},
        );
        for (final u in (res as List)) {
          final m = Map<String, dynamic>.from(u as Map);
          nombres[m['id'].toString()] = m;
        }
      }
      final result = <Map<String, dynamic>>[];
      for (final r in rows) {
        result.add({...r, 'usuario': nombres[r['usuario_id']?.toString()]});
      }
      // Save to cache on success
      await _guardarCache(claseId, result);
      if (mounted && _isOffline) setState(() => _isOffline = false);
      return result;
    } catch (_) {
      // Try loading from cache as fallback
      final cached = await _leerCache(claseId);
      if (cached.isNotEmpty) {
        if (mounted) setState(() => _isOffline = true);
        return cached;
      }
      return [];
    }
  }

  Future<void> _seleccionarClase(Map<String, dynamic> clase) async {
    setState(() => _loading = true);
    final attendees = await _cargarAsistentes(clase);
    if (!mounted) return;
    setState(() {
      _claseSeleccionada = clase;
      _asistentes = attendees;
      _loading = false;
    });
  }

  // ── QR validation ────────────────────────────────────────────────────────

  /// Limpia caracteres invisibles que algunos escaneres meten (BOM, ZWSP,
  /// \r, \n, espacios) y deja solo lo que puede aparecer en un codigo_qr
  /// generado por la app: letras, digitos y guiones.
  String _normalizarQr(String raw) {
    final stripped = raw.replaceAll(RegExp(r'[^A-Za-z0-9\-]'), '');
    return stripped.toUpperCase();
  }

  /// "Ahora" en hora Argentina como DateTime naive — para comparar con
  /// las fechas de clases que en DB se guardan como naive en hora AR.
  DateTime _ahoraAr() {
    final u = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second);
  }

  /// Devuelve 'tarde' / 'futura' si el escaneo cae fuera de la ventana de
  /// gracia (la clase paso hace mas de 10 min o es de otro dia), o null si
  /// el check-in es directo (mismo dia, antes o dentro de los 10 min de
  /// gracia post-inicio).
  String? _verificarVentanaGracia(DateTime fechaClase) {
    final ahora = _ahoraAr();
    final hoyDia = DateTime(ahora.year, ahora.month, ahora.day);
    final claseDia = DateTime(
      fechaClase.year,
      fechaClase.month,
      fechaClase.day,
    );

    if (claseDia.isAfter(hoyDia)) return 'futura';
    if (claseDia.isBefore(hoyDia)) return 'tarde';
    // Mismo dia.
    final diffMin = ahora.difference(fechaClase).inMinutes;
    if (diffMin > 10) return 'tarde';
    return null;
  }

  /// Dialogo de confirmacion cuando el QR cae fuera de la ventana de
  /// gracia. Devuelve true si el estudio confirma igual.
  Future<bool> _pedirConfirmacionFueraVentana({
    required String kind,
    required DateTime fechaClase,
  }) async {
    String titulo;
    String mensaje;
    if (kind == 'futura') {
      final fmt = DateFormat(
        "EEEE d 'de' MMMM 'a las' HH:mm 'hs'",
        'es',
      ).format(fechaClase);
      titulo = 'La clase es a futuro';
      mensaje =
          'Esta clase es el $fmt. ¿Estás seguro que querés confirmar ahora?';
    } else {
      titulo = 'La clase ya comenzó';
      mensaje =
          'Esta clase comenzó hace más de 10 minutos. ¿Confirmar igualmente?';
    }
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text(
              'Confirmar igual',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Formato de codigo_qr generado por la app:
  ///   `AURA-<8 hex mayus>-<clase_id>-<timestamp_ms>-<random 4>`.
  /// Cualquier cosa fuera de este patron no es un QR de Aura y se ignora
  /// para que el scanner no procese basura random capturada por la camara.
  static final RegExp _kQrPattern = RegExp(r'^AURA-[A-Z0-9]{8}-\d+-\d+-\d{4}$');

  /// Throttle para no spamear el mismo "no es QR Aura" en cada frame
  /// mientras la camara sigue viendo el mismo codigo invalido.
  String? _ultimoInvalido;
  DateTime? _ultimoInvalidoAt;

  Future<void> _validarQR(String codigo) async {
    if (_procesando) return;
    final normalizado = _normalizarQr(codigo);
    if (normalizado.isEmpty) {
      setState(() {
        _debugRaw = codigo;
        _debugNormalized = normalizado;
        _debugResult = 'vacio tras normalizar';
        _debugAt = DateTime.now();
      });
      return;
    }

    // 1) Validar prefijo + formato AURA. No es un QR de Aura -> mostrar
    //    feedback liviano y dejar la camara escaneando.
    if (!_kQrPattern.hasMatch(normalizado)) {
      final ahora = DateTime.now();
      final repetido =
          _ultimoInvalido == normalizado &&
          _ultimoInvalidoAt != null &&
          ahora.difference(_ultimoInvalidoAt!).inSeconds < 3;
      _ultimoInvalido = normalizado;
      _ultimoInvalidoAt = ahora;
      setState(() {
        _debugRaw = codigo;
        _debugNormalized = normalizado;
        _debugResult = 'no es QR de Aura (formato invalido)';
        _debugAt = ahora;
      });
      if (!repetido) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este no es un QR de Aura'),
            backgroundColor: AppColors.blackSoft,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() {
      _procesando = true;
      _debugRaw = codigo;
      _debugNormalized = normalizado;
      _debugResult = 'buscando…';
      _debugAt = DateTime.now();
    });
    debugPrint(
      '[QR scan] raw="$codigo" len=${codigo.length} '
      'normalized="$normalizado" len=${normalizado.length}',
    );

    final claseId = (_claseSeleccionada?['id'] as num?)?.toInt();

    try {
      // 2) Buscar la reserva. Filtramos por clase_id Y estado='confirmada'
      //    para que el QR de OTRA clase no sirva, ni los QR de reservas
      //    canceladas / ausentes / ya-presentes vuelvan a confirmar.
      var query = Supabase.instance.client
          .from('reservas')
          .select()
          .eq('codigo_qr', normalizado)
          .eq('estado', 'confirmada');
      if (claseId != null) {
        query = query.eq('clase_id', claseId);
      }
      final reserva = await query.maybeSingle();

      if (!mounted) return;

      if (reserva == null) {
        // Diagnostico: contar matches sin filtros para distinguir entre
        // "no existe / RLS bloquea" vs "existe pero es de otra clase / ya
        // se uso / esta cancelada".
        int countAll = -1;
        int countOtherClass = 0;
        String? otherClassEstado;
        try {
          final allMatches = await Supabase.instance.client
              .from('reservas')
              .select('id, clase_id, estado')
              .eq('codigo_qr', normalizado);
          final list = List<Map<String, dynamic>>.from(allMatches as List);
          countAll = list.length;
          if (claseId != null && list.isNotEmpty) {
            final otra = list.firstWhere(
              (r) => (r['clase_id'] as num?)?.toInt() != claseId,
              orElse: () => const {},
            );
            if (otra.isNotEmpty) {
              countOtherClass = 1;
              otherClassEstado = otra['estado']?.toString();
            }
          }
        } catch (_) {}

        String titulo;
        String subtitulo;
        if (countOtherClass > 0) {
          titulo = 'QR de otra clase';
          subtitulo =
              'Este QR pertenece a una reserva de otra clase (estado: ${otherClassEstado ?? '?'}).';
        } else if (countAll > 0) {
          titulo = 'Reserva no disponible';
          subtitulo = 'La reserva existe pero no está en estado confirmada.';
        } else {
          titulo = 'QR inválido';
          subtitulo = 'No se encontró una reserva activa\n$normalizado';
        }
        setState(() {
          _debugResult =
              'NOT FOUND (countAll: $countAll, otherClass: $countOtherClass'
              '${otherClassEstado != null ? ', otherEstado=$otherClassEstado' : ''})';
        });
        _mostrarPopup(exito: false, titulo: titulo, subtitulo: subtitulo);
        return;
      }

      setState(
        () => _debugResult =
            'OK (id=${reserva['id']}, clase_id=${reserva['clase_id']}, estado=${reserva['estado']})',
      );

      final usuarioRows = await Supabase.instance.client.rpc(
        'estudio_nombres_alumnas',
        params: {
          'p_ids': [reserva['usuario_id'].toString()],
        },
      );
      final usuario = (usuarioRows as List).isEmpty
          ? null
          : Map<String, dynamic>.from(usuarioRows.first as Map);

      final clase = await Supabase.instance.client
          .from('clases')
          .select('nombre, fecha')
          .eq('id', reserva['clase_id'])
          .maybeSingle();

      // Ventana de gracia para escaneo fuera de hora. Si la clase es de
      // otro dia o paso hace mas de 10 min, le pedimos confirmacion al
      // estudio antes de marcar presente.
      final fechaClase = DateTime.tryParse(clase?['fecha']?.toString() ?? '');
      if (fechaClase != null) {
        final fueraDeVentana = _verificarVentanaGracia(fechaClase);
        if (fueraDeVentana != null) {
          if (!mounted) return;
          final confirmar = await _pedirConfirmacionFueraVentana(
            kind: fueraDeVentana,
            fechaClase: fechaClase,
          );
          if (!mounted) return;
          if (!confirmar) {
            setState(
              () => _debugResult =
                  'cancelado por estudio (fuera de ventana: $fueraDeVentana)',
            );
            return;
          }
        }
      }

      await Supabase.instance.client
          .from('reservas')
          .update({
            'estado': 'presente',
            'checked_in_at': DateTime.now().toIso8601String(),
          })
          .eq('codigo_qr', normalizado);

      if (!mounted) return;

      _mostrarPopup(
        exito: true,
        titulo: usuario?['nombre']?.toString() ?? 'Usuario',
        subtitulo: clase?['nombre']?.toString() ?? 'Clase',
      );

      _cargarAsistentes(_claseSeleccionada).then((list) {
        if (mounted) setState(() => _asistentes = list);
      });
    } catch (e) {
      setState(() => _debugResult = 'EXCEPTION: $e');
      if (!mounted) return;
      // Offline fallback: search locally
      final match = _asistentes
          .where(
            (a) =>
                _normalizarQr(a['codigo_qr']?.toString() ?? '') == normalizado,
          )
          .toList();

      if (match.isNotEmpty) {
        final asistente = match.first;
        final update = {
          'estado': 'presente',
          'checked_in_at': DateTime.now().toIso8601String(),
        };
        setState(() {
          _isOffline = true;
          _asistentes = _asistentes.map((a) {
            if (_normalizarQr(a['codigo_qr']?.toString() ?? '') ==
                normalizado) {
              return {...a, ...update};
            }
            return a;
          }).toList();
        });
        await _guardarPendienteSync(normalizado);
        final user = asistente['usuario'] as Map<String, dynamic>?;
        _mostrarPopup(
          exito: true,
          titulo: user?['nombre']?.toString() ?? 'Usuario',
          subtitulo: 'Guardado offline',
        );
      } else {
        setState(() => _isOffline = true);
        _mostrarPopup(
          exito: false,
          titulo: 'Sin conexión',
          subtitulo: 'QR no encontrado en caché',
        );
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  void _mostrarPopup({
    required bool exito,
    required String titulo,
    required String subtitulo,
  }) {
    _cameraController?.stop();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _ResultPopup(exito: exito, titulo: titulo, subtitulo: subtitulo),
    ).then((_) {
      if (_usarCamara) {
        _cameraController?.start();
      } else {
        _qrFocusNode.requestFocus();
      }
    });

    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    });
  }

  void _cambiarModo() {
    setState(() {
      _usarCamara = !_usarCamara;
      if (_usarCamara) {
        _cameraController ??= MobileScannerController();
        _cameraController!.start();
      } else {
        _cameraController?.stop();
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _qrFocusNode.requestFocus();
        });
      }
    });
  }

  // ── Banner ─────────────────────────────────────────────────────────────────

  Widget _buildBanner() {
    final fecha = DateTime.tryParse(
      _claseSeleccionada?['fecha']?.toString() ?? '',
    );
    if (fecha == null) return const SizedBox.shrink();

    final mins = fecha.difference(_now).inMinutes;
    if (mins <= 0 || mins > 120) return const SizedBox.shrink();

    final String titulo;
    if (mins > 60) {
      final horas = mins ~/ 60;
      final minutosRest = mins % 60;
      final horasStr = horas == 1 ? '1 hora' : '$horas horas';
      titulo = minutosRest == 0
          ? 'La clase empieza en $horasStr'
          : 'La clase empieza en $horasStr y $minutosRest minuto${minutosRest != 1 ? 's' : ''}';
    } else {
      titulo = '¡La clase empieza en $mins minuto${mins != 1 ? 's' : ''}!';
    }

    final totalReservas = _asistentes.length;
    final totalCupos =
        (_claseSeleccionada?['lugares_total'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF0E8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.access_time_rounded,
            color: Color(0xFFE8763A),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$totalReservas alumnos confirmados de $totalCupos cupos',
                  style: const TextStyle(
                    color: Color(0xFF8F877F),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Debug panel (QR scan diagnostics) ─────────────────────────────────────

  Widget _buildDebugQrPanel() {
    // Solo visible en builds de debug local. En producción NUNCA se muestra:
    // una dueña de estudio no puede ver un panel de debug sobre el escáner.
    if (!kDebugMode) return const SizedBox.shrink();
    if (_debugRaw == null && _debugNormalized == null && _debugResult == null) {
      return const SizedBox.shrink();
    }
    final ts = _debugAt;
    final tsStr = ts == null
        ? ''
        : '${ts.hour.toString().padLeft(2, '0')}:'
              '${ts.minute.toString().padLeft(2, '0')}:'
              '${ts.second.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'DEBUG QR',
                style: TextStyle(
                  color: Color(0xFFE8763A),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              if (tsStr.isNotEmpty)
                Text(
                  tsStr,
                  style: const TextStyle(
                    color: Color(0xFF8F877F),
                    fontSize: 10,
                    fontFamily: 'Courier',
                  ),
                ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() {
                  _debugRaw = null;
                  _debugNormalized = null;
                  _debugResult = null;
                  _debugAt = null;
                }),
                child: const Icon(
                  Icons.close_rounded,
                  color: Color(0xFF8F877F),
                  size: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _debugLine('raw', _debugRaw),
          _debugLine('norm', _debugNormalized),
          _debugLine('result', _debugResult),
        ],
      ),
    );
  }

  Widget _debugLine(String label, String? value) {
    final text = value ?? '—';
    final len = value?.length ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontFamily: 'Courier',
            fontSize: 11,
            color: Color(0xFFE0DBD6),
          ),
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(
                color: Color(0xFF9A928B),
                fontWeight: FontWeight.w700,
              ),
            ),
            if (label != 'result')
              TextSpan(
                text: '($len) ',
                style: const TextStyle(color: Color(0xFF8F877F)),
              ),
            TextSpan(text: text),
          ],
        ),
      ),
    );
  }

  // ── Desktop ────────────────────────────────────────────────────────────────

  Widget _buildDesktopContent() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: class selector + scanner
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Class selector card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CLASE ACTIVA',
                            style: TextStyle(
                              color: Color(0xFFB0A8A0),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _claseSeleccionada?['nombre']?.toString() ??
                                'Sin clase',
                            style: const TextStyle(
                              color: AppColors.black,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_clases.length > 1)
                      TextButton(
                        onPressed: _mostrarSelectorClases,
                        child: const Text(
                          'Cambiar',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildBanner(),
              if (_isOffline) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        color: Color(0xFFE8763A),
                        size: 18,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sin conexión — escaneando en modo offline',
                              style: TextStyle(
                                color: Color(0xFF1A1A1A),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Los cambios se sincronizan al reconectarte',
                              style: TextStyle(
                                color: Color(0xFF8F877F),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Scanner
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.blackSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _usarCamara ? 'Cámara' : 'Lector USB',
                          style: const TextStyle(
                            color: Color(0xFF9A928B),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        GestureDetector(
                          onTap: _cambiarModo,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _usarCamara
                                      ? Icons.keyboard_rounded
                                      : Icons.camera_alt_rounded,
                                  color: AppColors.primary,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _usarCamara ? 'Usar lector' : 'Usar cámara',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 260,
                        child: _usarCamara
                            ? _CameraScanner(
                                controller: _cameraController!,
                                procesando: _procesando,
                                onDetect: _validarQR,
                              )
                            : _USBScanner(
                                controller: _qrController,
                                focusNode: _qrFocusNode,
                                procesando: _procesando,
                                onSubmit: (v) {
                                  _validarQR(v);
                                  _qrController.clear();
                                  _qrFocusNode.requestFocus();
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _usarCamara
                          ? 'Apuntá la cámara al QR del usuario'
                          : 'Pasá el lector QR por el código del usuario',
                      style: const TextStyle(
                        color: Color(0xFF8F877F),
                        fontSize: 13,
                      ),
                    ),
                    _buildDebugQrPanel(),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        // Right: stats + attendee table
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stats row
              Row(
                children: [
                  Expanded(
                    child: _CountBox(
                      value: _presentes.toString(),
                      label: 'Presentes',
                      color: const Color(0xFFE3F3E5),
                      valueColor: const Color(0xFF43A047),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CountBox(
                      value: _pendientes.toString(),
                      label: 'Pendientes',
                      color: const Color(0xFFFFF3DE),
                      valueColor: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CountBox(
                      value: _ausentes.toString(),
                      label: 'Ausentes',
                      color: const Color(0xFFF1F1F1),
                      valueColor: const Color(0xFF6E6761),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Attendees table
              const Text(
                'LISTA DE ASISTENTES',
                style: TextStyle(
                  color: Color(0xFF8F877F),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              if (_asistentes.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'Sin reservas para esta clase',
                      style: TextStyle(color: Color(0xFF9A928B)),
                    ),
                  ),
                )
              else ...[
                _AsistentesSearchField(controller: _searchCtrl),
                const SizedBox(height: 10),
                if (_asistentesFiltrados.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'Sin coincidencias',
                        style: TextStyle(color: Color(0xFF9A928B)),
                      ),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF7F5F2),
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Nombre',
                                  style: TextStyle(
                                    color: Color(0xFF888888),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 90,
                                child: Text(
                                  'Estado',
                                  style: TextStyle(
                                    color: Color(0xFF888888),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ..._asistentesFiltrados.asMap().entries.map((e) {
                          final a = e.value;
                          final user = a['usuario'] as Map<String, dynamic>?;
                          final nombre =
                              user?['nombre']?.toString() ?? 'Sin nombre';
                          final estado =
                              a['estado']?.toString() ?? 'confirmada';
                          final esPresente = estado == 'presente';
                          final esAusente = estado == 'ausente';
                          final badgeColor = esPresente
                              ? const Color(0xFFE3F3E5)
                              : esAusente
                              ? const Color(0xFFFFEBEE)
                              : const Color(0xFFFFF3DE);
                          final badgeTextColor = esPresente
                              ? const Color(0xFF43A047)
                              : esAusente
                              ? const Color(0xFFE53935)
                              : AppColors.primary;
                          final badgeLabel = esPresente
                              ? 'Presente'
                              : esAusente
                              ? 'Ausente'
                              : 'Pendiente';
                          return InkWell(
                            borderRadius:
                                e.key == _asistentesFiltrados.length - 1
                                ? const BorderRadius.vertical(
                                    bottom: Radius.circular(16),
                                  )
                                : null,
                            onTap: () => _mostrarAccionesAsistente(a),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: Colors.grey.shade100),
                                ),
                                borderRadius:
                                    e.key == _asistentesFiltrados.length - 1
                                    ? const BorderRadius.vertical(
                                        bottom: Radius.circular(16),
                                      )
                                    : null,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: _avatarColor(nombre),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        _initials(nombre),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nombre,
                                          style: const TextStyle(
                                            color: AppColors.black,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (esPresente)
                                          Text(
                                            'Ingreso ${_horaIngreso(a)}',
                                            style: const TextStyle(
                                              color: Color(0xFF9A928B),
                                              fontSize: 11,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: 90,
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: badgeColor,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          badgeLabel,
                                          style: TextStyle(
                                            color: badgeTextColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    if (isDesktop) {
      return GestureDetector(
        onTap: () {
          if (!_usarCamara && !_procesando) _qrFocusNode.requestFocus();
        },
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: AnchoMaximo(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : RefreshIndicator(
                    onRefresh: _cargar,
                    color: AppColors.primary,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: _buildDesktopContent(),
                    ),
                  ),
          ),
        ),
      );
    }

    return GestureDetector(
      // Re-enfocar el campo USB si el usuario toca fuera
      onTap: () {
        if (!_usarCamara && !_procesando) _qrFocusNode.requestFocus();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : SafeArea(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                    children: [
                      // Header
                      Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              final router = GoRouter.of(context);
                              if (router.canPop()) {
                                router.pop();
                              } else {
                                context.go('/estudio/dashboard');
                              }
                            },
                            icon: const Icon(Icons.arrow_back_rounded),
                            color: AppColors.black,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Asistencia',
                            style: TextStyle(
                              color: AppColors.black,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Offline banner
                      if (_isOffline) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.wifi_off_rounded,
                                color: Color(0xFFE8763A),
                                size: 18,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Sin conexión — escaneando en modo offline',
                                      style: TextStyle(
                                        color: Color(0xFF1A1A1A),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      'Los cambios se sincronizan al reconectarte',
                                      style: TextStyle(
                                        color: Color(0xFF8F877F),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Clase activa
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'CLASE ACTIVA',
                                    style: TextStyle(
                                      color: Color(0xFFB0A8A0),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _claseSeleccionada?['nombre']?.toString() ??
                                        'Sin clase activa ahora',
                                    style: TextStyle(
                                      color: _claseSeleccionada == null
                                          ? const Color(0xFF8F877F)
                                          : AppColors.black,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (_claseSeleccionada == null) ...[
                                    const SizedBox(height: 4),
                                    const Text(
                                      'No tenés clases hoy. Podés escanear igual: '
                                      'registramos la asistencia en la reserva.',
                                      style: TextStyle(
                                        color: Color(0xFFB0A8A0),
                                        fontSize: 12,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: _clases.isEmpty
                                  ? null
                                  : _mostrarSelectorClases,
                              child: const Text(
                                'Cambiar',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildBanner(),

                      // Scanner
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                        decoration: BoxDecoration(
                          color: AppColors.blackSoft,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          children: [
                            // Modo toggle
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _usarCamara ? 'Cámara' : 'Lector USB',
                                  style: const TextStyle(
                                    color: Color(0xFF9A928B),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _cambiarModo,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2A2A2A),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _usarCamara
                                              ? Icons.keyboard_rounded
                                              : Icons.camera_alt_rounded,
                                          color: AppColors.primary,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _usarCamara
                                              ? 'Usar lector'
                                              : 'Usar cámara',
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Scanner area
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                height: 230,
                                child: _usarCamara
                                    ? _CameraScanner(
                                        controller: _cameraController!,
                                        procesando: _procesando,
                                        onDetect: _validarQR,
                                      )
                                    : _USBScanner(
                                        controller: _qrController,
                                        focusNode: _qrFocusNode,
                                        procesando: _procesando,
                                        onSubmit: (v) {
                                          _validarQR(v);
                                          _qrController.clear();
                                          _qrFocusNode.requestFocus();
                                        },
                                      ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _usarCamara
                                  ? 'Apuntá la cámara al QR del usuario'
                                  : 'Pasá el lector QR por el código del usuario',
                              style: const TextStyle(
                                color: Color(0xFF8F877F),
                                fontSize: 13,
                              ),
                            ),
                            _buildDebugQrPanel(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Contadores
                      Row(
                        children: [
                          Expanded(
                            child: _CountBox(
                              value: _presentes.toString(),
                              label: 'Presentes',
                              color: const Color(0xFFE3F3E5),
                              valueColor: const Color(0xFF43A047),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _CountBox(
                              value: _pendientes.toString(),
                              label: 'Pendientes',
                              color: const Color(0xFFFFF3DE),
                              valueColor: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _CountBox(
                              value: _ausentes.toString(),
                              label: 'Ausentes',
                              color: const Color(0xFFF1F1F1),
                              valueColor: const Color(0xFF6E6761),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Lista
                      const Text(
                        'LISTA DE ASISTENTES',
                        style: TextStyle(
                          color: Color(0xFF8F877F),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_asistentes.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Sin reservas para esta clase',
                              style: TextStyle(color: Color(0xFF9A928B)),
                            ),
                          ),
                        )
                      else ...[
                        _AsistentesSearchField(controller: _searchCtrl),
                        const SizedBox(height: 10),
                        if (_asistentesFiltrados.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Sin coincidencias',
                                style: TextStyle(color: Color(0xFF9A928B)),
                              ),
                            ),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              children: _asistentesFiltrados.map((a) {
                                final user =
                                    a['usuario'] as Map<String, dynamic>?;
                                final nombre =
                                    user?['nombre']?.toString() ?? 'Sin nombre';
                                final email = user?['email']?.toString();
                                final avatarUrl = user?['avatar_url']
                                    ?.toString();
                                final estado =
                                    a['estado']?.toString() ?? 'confirmada';
                                final esPresente = estado == 'presente';
                                final esAusente = estado == 'ausente';
                                return _AttendeeRow(
                                  nombre: nombre,
                                  email: email,
                                  avatarUrl: avatarUrl,
                                  subtitle: esPresente
                                      ? 'Ingreso ${_horaIngreso(a)}'
                                      : esAusente
                                      ? 'Ausente'
                                      : 'Pendiente',
                                  initials: _initials(nombre),
                                  color: _avatarColor(nombre),
                                  icon: esPresente
                                      ? Icons.check_circle_rounded
                                      : esAusente
                                      ? Icons.cancel_rounded
                                      : Icons.access_time_rounded,
                                  iconColor: esPresente
                                      ? const Color(0xFF43A047)
                                      : esAusente
                                      ? const Color(0xFFE53935)
                                      : const Color(0xFFB0A8A0),
                                  onTap: () => _mostrarAccionesAsistente(a),
                                );
                              }).toList(),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ── Marcado manual ────────────────────────────────────────────────────────

  Future<void> _marcarAsistente(
    Map<String, dynamic> asistente,
    String nuevoEstado,
  ) async {
    final codigoQr = asistente['codigo_qr']?.toString();
    if (codigoQr == null || codigoQr.isEmpty) return;

    final nombre =
        (asistente['usuario'] as Map<String, dynamic>?)?['nombre']
            ?.toString() ??
        'Alumno';

    final update = <String, dynamic>{'estado': nuevoEstado};
    if (nuevoEstado == 'presente') {
      update['checked_in_at'] = DateTime.now().toIso8601String();
    } else {
      update['checked_in_at'] = null;
    }

    try {
      await Supabase.instance.client
          .from('reservas')
          .update(update)
          .eq('codigo_qr', codigoQr);
      if (mounted && _isOffline) setState(() => _isOffline = false);
    } catch (_) {
      // Offline: queue for sync
      await _guardarPendienteSync(codigoQr);
      if (mounted) setState(() => _isOffline = true);
    }

    // Actualizar lista local
    if (mounted) {
      setState(() {
        _asistentes = _asistentes.map((a) {
          if (a['codigo_qr'] == codigoQr) {
            return {...a, ...update};
          }
          return a;
        }).toList();
      });

      final msg = nuevoEstado == 'presente'
          ? '✓ $nombre marcado como presente'
          : nuevoEstado == 'ausente'
          ? '$nombre marcado como ausente'
          : '$nombre marcado como pendiente';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFF1A1A1A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Future<void> _mostrarAccionesAsistente(Map<String, dynamic> asistente) async {
    final user = asistente['usuario'] as Map<String, dynamic>?;
    final nombre = user?['nombre']?.toString() ?? 'Sin nombre';
    final estado = asistente['estado']?.toString() ?? 'confirmada';
    final claseNombre = _claseSeleccionada?['nombre']?.toString() ?? 'Clase';
    final fecha = DateTime.tryParse(
      _claseSeleccionada?['fecha']?.toString() ?? '',
    );
    final horario = fecha != null
        ? DateFormat('EEE d MMM · HH:mm', 'es').format(fecha)
        : '';

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0DBD6),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 20),
              // Avatar
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8763A),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    _initials(nombre),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Nombre
              Text(
                nombre,
                style: const TextStyle(
                  color: AppColors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              // Clase y horario
              Text(
                '$claseNombre · $horario',
                style: const TextStyle(color: Color(0xFF9A928B), fontSize: 13),
              ),
              const SizedBox(height: 24),
              if (estado == 'presente') ...[
                // Badge presente
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F3E5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Ya marcado como presente',
                    style: TextStyle(
                      color: Color(0xFF43A047),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ingreso ${_horaIngreso(asistente)}',
                  style: const TextStyle(
                    color: Color(0xFF9A928B),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _marcarAsistente(asistente, 'confirmada');
                  },
                  child: const Text(
                    'Deshacer — marcar como pendiente',
                    style: TextStyle(color: Color(0xFF9A928B), fontSize: 14),
                  ),
                ),
              ] else if (estado == 'ausente') ...[
                // Badge ausente
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Marcado como ausente',
                    style: TextStyle(
                      color: Color(0xFFE53935),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _marcarAsistente(asistente, 'presente');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE8763A),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('Cambiar a presente'),
                  ),
                ),
              ] else ...[
                // Estado confirmada / pendiente
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _marcarAsistente(asistente, 'presente');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF43A047),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('✓  Marcar como presente'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _marcarAsistente(asistente, 'ausente');
                  },
                  child: const Text(
                    'Marcar como ausente',
                    style: TextStyle(color: Color(0xFF9A928B), fontSize: 14),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _mostrarSelectorClases() async {
    final filterCtrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        final maxH = MediaQuery.of(sheetCtx).size.height * 0.85;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: StatefulBuilder(
              builder: (ctx, setSheetState) {
                final now = DateTime.now();
                final q = filterCtrl.text.trim().toLowerCase();

                bool matchesQuery(Map<String, dynamic> c) {
                  if (q.isEmpty) return true;
                  return (c['nombre']?.toString() ?? '').toLowerCase().contains(
                    q,
                  );
                }

                final ahora = _clases
                    .where(
                      (c) =>
                          _bucketDeClase(c, now) == 'ahora' && matchesQuery(c),
                    )
                    .toList();
                final hoy = _clases
                    .where(
                      (c) => _bucketDeClase(c, now) == 'hoy' && matchesQuery(c),
                    )
                    .toList();
                final proximas = _clases
                    .where(
                      (c) =>
                          _bucketDeClase(c, now) == 'proximas' &&
                          matchesQuery(c),
                    )
                    .toList();

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
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
                      const SizedBox(height: 14),
                      const Text(
                        'Elegí la clase',
                        style: TextStyle(
                          color: AppColors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _ClaseSearchField(
                        controller: filterCtrl,
                        onChanged: (_) => setSheetState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            if (ahora.isEmpty &&
                                hoy.isEmpty &&
                                proximas.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 28),
                                child: Center(
                                  child: Text(
                                    'No hay clases que coincidan.',
                                    style: TextStyle(
                                      color: AppColors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            if (ahora.isNotEmpty) ...[
                              const _SeccionLabel('AHORA', accent: true),
                              ...ahora.map(
                                (c) => _ClaseSelectorTile(
                                  clase: c,
                                  highlight: true,
                                  onTap: () {
                                    Navigator.pop(sheetCtx);
                                    _seleccionarClase(c);
                                  },
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            if (hoy.isNotEmpty) ...[
                              const _SeccionLabel('HOY'),
                              ...hoy.map(
                                (c) => _ClaseSelectorTile(
                                  clase: c,
                                  onTap: () {
                                    Navigator.pop(sheetCtx);
                                    _seleccionarClase(c);
                                  },
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            if (proximas.isNotEmpty) ...[
                              const _SeccionLabel('PRÓXIMAS'),
                              ...proximas.map(
                                (c) => _ClaseSelectorTile(
                                  clase: c,
                                  onTap: () {
                                    Navigator.pop(sheetCtx);
                                    _seleccionarClase(c);
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
    filterCtrl.dispose();
  }

  int get _presentes =>
      _asistentes.where((a) => a['estado'] == 'presente').length;

  int get _pendientes => _asistentes
      .where(
        (a) =>
            a['estado'] != 'presente' &&
            a['estado'] != 'cancelada' &&
            a['estado'] != 'ausente',
      )
      .length;

  int get _ausentes =>
      _asistentes.where((a) => a['estado'] == 'ausente').length;

  String _horaIngreso(Map<String, dynamic> a) {
    final dt = DateTime.tryParse(a['checked_in_at']?.toString() ?? '');
    if (dt == null) return '--:--';
    return DateFormat('HH:mm').format(dt.toLocal());
  }

  String _initials(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '??';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Color _avatarColor(String name) {
    final colors = [
      const Color(0xFFD6E9FF),
      const Color(0xFFFFE1EA),
      const Color(0xFFE5F6E8),
      const Color(0xFFFCEACC),
    ];
    return colors[name.length % colors.length];
  }
}

// ── Camera scanner ─────────────────────────────────────────────────────────

class _CameraScanner extends StatelessWidget {
  final MobileScannerController controller;
  final bool procesando;
  final void Function(String) onDetect;

  const _CameraScanner({
    required this.controller,
    required this.procesando,
    required this.onDetect,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: controller,
          onDetect: (capture) {
            final value = capture.barcodes.firstOrNull?.rawValue;
            if (value != null && !procesando) onDetect(value);
          },
        ),
        // Esquinas del viewfinder
        const Positioned(top: 16, left: 16, child: _ScannerCorner()),
        const Positioned(
          top: 16,
          right: 16,
          child: _ScannerCorner(flipX: true),
        ),
        const Positioned(
          bottom: 16,
          left: 16,
          child: _ScannerCorner(flipY: true),
        ),
        const Positioned(
          bottom: 16,
          right: 16,
          child: _ScannerCorner(flipX: true, flipY: true),
        ),
        // Overlay mientras procesa
        if (procesando)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
      ],
    );
  }
}

// ── USB scanner ───────────────────────────────────────────────────────────

class _USBScanner extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool procesando;
  final void Function(String) onSubmit;

  const _USBScanner({
    required this.controller,
    required this.focusNode,
    required this.procesando,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    // En web: campo de texto visible para ingresar el código manualmente
    if (kIsWeb) {
      return Container(
        color: const Color(0xFF2A2A2A),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.keyboard_rounded,
              size: 36,
              color: Color(0xFF595959),
            ),
            const SizedBox(height: 10),
            const Text(
              'Ingresá el código de reserva',
              style: TextStyle(
                color: Color(0xFF8F877F),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'En web ingresá el código que aparece en el ticket del alumno (formato #AUR-XXXX)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6E6761),
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              enabled: !procesando,
              textInputAction: TextInputAction.send,
              onSubmitted: (v) {
                onSubmit(v);
                controller.clear();
                focusNode.requestFocus();
              },
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Ej: abc123-xyz...',
                hintStyle: const TextStyle(color: Color(0xFF555555)),
                filled: true,
                fillColor: const Color(0xFF333333),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                suffixIcon: procesando
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.primary,
                        ),
                        onPressed: () {
                          if (controller.text.trim().isNotEmpty) {
                            onSubmit(controller.text.trim());
                            controller.clear();
                            focusNode.requestFocus();
                          }
                        },
                      ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'El alumno te muestra el código en su teléfono',
              style: TextStyle(color: Color(0xFF555555), fontSize: 11),
            ),
          ],
        ),
      );
    }

    // En mobile/desktop con lector USB: campo oculto que captura el input
    return Container(
      color: const Color(0xFF2A2A2A),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              onSubmitted: onSubmit,
              decoration: const InputDecoration(border: InputBorder.none),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  procesando
                      ? Icons.hourglass_top_rounded
                      : Icons.qr_code_scanner_rounded,
                  size: 64,
                  color: procesando
                      ? AppColors.primary
                      : const Color(0xFF595959),
                ),
                const SizedBox(height: 12),
                Text(
                  procesando ? 'Validando...' : 'Esperando QR...',
                  style: TextStyle(
                    color: procesando
                        ? AppColors.primary
                        : const Color(0xFF8F877F),
                    fontSize: 14,
                    fontWeight: procesando ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const Positioned(top: 16, left: 16, child: _ScannerCorner()),
          const Positioned(
            top: 16,
            right: 16,
            child: _ScannerCorner(flipX: true),
          ),
          const Positioned(
            bottom: 16,
            left: 16,
            child: _ScannerCorner(flipY: true),
          ),
          const Positioned(
            bottom: 16,
            right: 16,
            child: _ScannerCorner(flipX: true, flipY: true),
          ),
        ],
      ),
    );
  }
}

// ── Result popup ──────────────────────────────────────────────────────────

class _ResultPopup extends StatelessWidget {
  final bool exito;
  final String titulo;
  final String subtitulo;

  const _ResultPopup({
    required this.exito,
    required this.titulo,
    required this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: exito ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              exito ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 72,
              color: exito ? const Color(0xFF43A047) : AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.black,
              ),
            ),
            if (subtitulo.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitulo,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF6E6761)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────

class _ScannerCorner extends StatelessWidget {
  final bool flipX;
  final bool flipY;

  const _ScannerCorner({this.flipX = false, this.flipY = false});

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..scale(flipX ? -1.0 : 1.0, flipY ? -1.0 : 1.0),
      child: Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.primary, width: 4),
            left: BorderSide(color: AppColors.primary, width: 4),
          ),
        ),
      ),
    );
  }
}

class _CountBox extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final Color valueColor;

  const _CountBox({
    required this.value,
    required this.label,
    required this.color,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    // Sin Expanded acá: los callers lo envuelven (y algunos ya lo hacían,
    // lo que daba "Incorrect use of ParentDataWidget" en debug, 25/8).
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF6E6761), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AttendeeRow extends StatelessWidget {
  final String nombre;
  final String? email;
  final String? avatarUrl;
  final String subtitle;
  final String initials;
  final Color color;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;

  const _AttendeeRow({
    required this.nombre,
    this.email,
    this.avatarUrl,
    required this.subtitle,
    required this.initials,
    required this.color,
    required this.icon,
    required this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color,
              // La foto de la alumna si la tiene; si no, sus iniciales.
              backgroundImage:
                  (avatarUrl != null && avatarUrl!.trim().isNotEmpty)
                  ? NetworkImage(avatarUrl!)
                  : null,
              child: (avatarUrl != null && avatarUrl!.trim().isNotEmpty)
                  ? null
                  : Text(
                      initials,
                      style: const TextStyle(
                        color: Color(0xFF4473B9),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombre,
                    style: const TextStyle(
                      color: AppColors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (email != null && email!.trim().isNotEmpty)
                    Text(
                      email!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF9A928B),
                        fontSize: 12,
                      ),
                    ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: subtitle == 'Pendiente'
                          ? AppColors.primary
                          : const Color(0xFF9A928B),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(icon, color: iconColor),
          ],
        ),
      ),
    );
  }
}

class _AsistentesSearchField extends StatelessWidget {
  final TextEditingController controller;

  const _AsistentesSearchField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Buscar por nombre o email',
        hintStyle: const TextStyle(color: Color(0xFF9A928B), fontSize: 14),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: Color(0xFF9A928B),
          size: 20,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(
                  Icons.clear_rounded,
                  color: Color(0xFF9A928B),
                  size: 18,
                ),
                onPressed: () => controller.clear(),
              ),
        filled: true,
        fillColor: AppColors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
        ),
      ),
    );
  }
}

// ── Widgets del selector de clase ───────────────────────────────────────────

class _ClaseSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _ClaseSearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Buscar por nombre de clase…',
        hintStyle: const TextStyle(color: Color(0xFF9A928B), fontSize: 14),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: Color(0xFF9A928B),
          size: 20,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: Color(0xFF9A928B),
                  size: 18,
                ),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        filled: true,
        fillColor: const Color(0xFFF7F5F2),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE9DED4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
        ),
      ),
    );
  }
}

class _SeccionLabel extends StatelessWidget {
  final String text;
  final bool accent;
  const _SeccionLabel(this.text, {this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 0, 8),
      child: Text(
        text,
        style: TextStyle(
          color: accent ? AppColors.primary : const Color(0xFF8F877F),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ClaseSelectorTile extends StatelessWidget {
  final Map<String, dynamic> clase;
  final bool highlight;
  final VoidCallback onTap;

  const _ClaseSelectorTile({
    required this.clase,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final fecha = DateTime.tryParse(clase['fecha']?.toString() ?? '');
    final fechaLabel = fecha != null
        ? DateFormat('EEE d MMM · HH:mm', 'es').format(fecha)
        : '—';
    final nombre = clase['nombre']?.toString() ?? 'Clase';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: highlight ? const Color(0xFFFDF0E8) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlight
                  ? AppColors.primary.withValues(alpha: 0.4)
                  : const Color(0xFFE9DED4),
              width: highlight ? 1.2 : 1,
            ),
          ),
          child: Row(
            children: [
              if (highlight) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.black,
                        fontSize: 15,
                        fontWeight: highlight
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fechaLabel,
                      style: TextStyle(
                        color: highlight
                            ? AppColors.primary
                            : const Color(0xFF8F877F),
                        fontSize: 12,
                        fontWeight: highlight
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: highlight ? AppColors.primary : const Color(0xFFB0A8A0),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
