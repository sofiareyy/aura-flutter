import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../models/estudio.dart';
import '../../providers/app_provider.dart';
import '../../services/clases_service.dart';
import '../../services/reservas_service.dart';
import '../../utils/cierre_minutos.dart';

const _darkAppBar = Color(0xFF1A1A1A);
const _cream = Color(0xFFF5F0E8);
const _chipDark = Color(0xFF252525);
const _chipBorder = Color(0xFF333333);
const _categoryBadgeBg = Color(0xFFFDF0E8);
const _successBg = Color(0xFFE8F5E9);
const _successFg = Color(0xFF2E7D32);

class MisReservasScreen extends StatefulWidget {
  const MisReservasScreen({super.key});

  @override
  State<MisReservasScreen> createState() => _MisReservasScreenState();
}

class _MisReservasScreenState extends State<MisReservasScreen> {
  final _reservasService = ReservasService();
  final _clasesService = ClasesService();

  List<Map<String, dynamic>> _proximas = [];
  List<Map<String, dynamic>> _historial = [];
  List<Map<String, dynamic>> _clases = [];
  // Entries de lista_espera del usuario + pre_confirmadas.
  List<Map<String, dynamic>> _enEspera = [];
  List<Map<String, dynamic>> _preReservas = [];
  List<String> _categorias = const ['Todos'];
  String _categoriaSeleccionada = 'Todos';
  String? _diaSeleccionadoKey;
  bool _loading = true;
  String? _error;
  bool _loadingMoreHistorial = false;
  bool _hasMoreHistorial = true;
  int _historialOffset = 0;
  bool _historialExpanded = false;
  static const _historialPageSize = 20;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (uid.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _historialOffset = 0;
        _hasMoreHistorial = true;
      });
    }

    // Refrescar el usuario NO debe bloquear la carga de reservas si falla.
    try {
      await context.read<AppProvider>().refrescarUsuario();
    } catch (e) {
      debugPrint('[mis-reservas] refrescarUsuario falló: $e');
    }

    // Cada query se protege por separado: si una falla (red, RLS, schema), cae
    // a lista vacía y las demás igual cargan. Antes, una sola excepción dejaba
    // la pantalla cargando para siempre (no había try/catch y _loading nunca
    // volvía a false).
    Future<List<Map<String, dynamic>>> guard(
      Future<List<Map<String, dynamic>>> f,
      String label,
    ) async {
      try {
        return await f;
      } catch (e) {
        debugPrint('[mis-reservas] query "$label" falló: $e');
        return <Map<String, dynamic>>[];
      }
    }

    List<List<Map<String, dynamic>>> results;
    try {
      results = await Future.wait([
        guard(_reservasService.getReservasUsuario(uid), 'reservas'),
        guard(
            _reservasService.getHistorialReservas(uid,
                limit: _historialPageSize, offset: 0),
            'historial'),
        guard(_clasesService.getProximasClases(limit: 200, offset: 0),
            'proximas'),
        guard(_reservasService.getListaEsperaUsuario(uid), 'espera'),
        guard(_reservasService.getPreReservasUsuario(uid), 'preReservas'),
      ]);
    } catch (e) {
      debugPrint('[mis-reservas] _cargar falló: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'No pudimos cargar tus reservas. Revisá tu conexión e intentá de nuevo.';
      });
      return;
    }
    if (!mounted) return;

    final proximas = results[0].toList()..sort(_compareByReservaFecha);
    final historial = results[1];
    final clases = results[2].toList()..sort(_compareByFecha);
    final enEspera = List<Map<String, dynamic>>.from(results[3]);
    final preReservas = List<Map<String, dynamic>>.from(results[4]);

    // Filtrar de "disponibles" las clases que el usuario ya tiene reservadas,
    // para que no aparezcan en ambas secciones.
    final claseIdsReservadas = proximas
        .map((r) => (r['clase_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet();
    final clasesFiltered = clases
        .where((c) => !claseIdsReservadas.contains((c['id'] as num?)?.toInt()))
        .toList();

    // Categorias derivadas de los estudios presentes en las clases.
    final cats = <String>{};
    for (final c in clasesFiltered) {
      final estudio = c['estudios'] as Map?;
      if (estudio == null) continue;
      cats.addAll(
        Estudio.parseCategorias(Map<String, dynamic>.from(estudio))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty),
      );
    }
    final categorias = ['Todos', ...cats.toList()..sort()];

    setState(() {
      _proximas = proximas;
      _historial = historial;
      _clases = clasesFiltered;
      _enEspera = enEspera;
      _preReservas = preReservas;
      _categorias = categorias;
      if (!_categorias.contains(_categoriaSeleccionada)) {
        _categoriaSeleccionada = 'Todos';
      }
      _historialOffset = historial.length;
      _hasMoreHistorial = historial.length == _historialPageSize;
      _diaSeleccionadoKey = _primerDiaConClases();
      _loading = false;
    });
  }

  Future<void> _salirDeListaEspera(int claseId) async {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return;
    try {
      await Supabase.instance.client
          .from('lista_espera')
          .delete()
          .eq('clase_id', claseId)
          .eq('usuario_id', uid);
      // No hay nada que renumerar: la posición no es una columna, se deriva
      // del orden de llegada (created_at) en waitlist_mis_posiciones().
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saliste de la lista de espera.'),
          backgroundColor: AppColors.blackSoft,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo salir: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _cargarMasHistorial() async {
    if (_loadingMoreHistorial || !_hasMoreHistorial) return;
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return;
    setState(() => _loadingMoreHistorial = true);
    try {
      final mas = await _reservasService.getHistorialReservas(
        uid,
        limit: _historialPageSize,
        offset: _historialOffset,
      );
      if (!mounted) return;
      setState(() {
        _historial = [..._historial, ...mas];
        _historialOffset += mas.length;
        _hasMoreHistorial = mas.length == _historialPageSize;
        _loadingMoreHistorial = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMoreHistorial = false);
    }
  }

  // ── Fecha helpers (DB strings naive AR; comparamos contra "ahora AR") ─────

  DateTime _ahoraAr() {
    final u = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second);
  }

  DateTime? _parseFecha(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  String _dayKey(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';

  int _compareByFecha(Map<String, dynamic> a, Map<String, dynamic> b) {
    final fa = _parseFecha(a['fecha']);
    final fb = _parseFecha(b['fecha']);
    if (fa == null && fb == null) return 0;
    if (fa == null) return 1;
    if (fb == null) return -1;
    return fa.compareTo(fb);
  }

  int _compareByReservaFecha(Map<String, dynamic> a, Map<String, dynamic> b) {
    final fa = _parseFecha((a['clases'] as Map?)?['fecha']);
    final fb = _parseFecha((b['clases'] as Map?)?['fecha']);
    if (fa == null && fb == null) return 0;
    if (fa == null) return 1;
    if (fb == null) return -1;
    return fa.compareTo(fb);
  }

  bool _matchesCategoria(Map<String, dynamic> clase) {
    if (_categoriaSeleccionada == 'Todos') return true;
    final estudio = clase['estudios'] as Map?;
    if (estudio == null) return false;
    // Matchea si CUALQUIERA de las categorias del estudio coincide.
    final objetivo = _categoriaSeleccionada.toLowerCase();
    return Estudio.parseCategorias(Map<String, dynamic>.from(estudio))
        .any((c) => c.trim().toLowerCase() == objetivo);
  }

  List<DateTime> get _diasDisponibles {
    final seen = <String, DateTime>{};
    for (final c in _clases) {
      if (!_matchesCategoria(c)) continue;
      final fecha = _parseFecha(c['fecha']);
      if (fecha == null) continue;
      final dia = DateTime(fecha.year, fecha.month, fecha.day);
      seen.putIfAbsent(_dayKey(dia), () => dia);
    }
    final dias = seen.values.toList()..sort();
    return dias;
  }

  String? _primerDiaConClases() {
    final dias = _diasDisponibles;
    if (dias.isEmpty) return null;
    return _dayKey(dias.first);
  }

  List<Map<String, dynamic>> get _clasesDelDia {
    final key = _diaSeleccionadoKey;
    if (key == null) return const [];
    return _clases.where((c) {
      if (!_matchesCategoria(c)) return false;
      final fecha = _parseFecha(c['fecha']);
      if (fecha == null) return false;
      return _dayKey(DateTime(fecha.year, fecha.month, fecha.day)) == key;
    }).toList()
      ..sort(_compareByFecha);
  }

  void _seleccionarCategoria(String categoria) {
    setState(() {
      _categoriaSeleccionada = categoria;
      final dias = _diasDisponibles;
      if (dias.isEmpty) {
        _diaSeleccionadoKey = null;
      } else if (!dias.any((d) => _dayKey(d) == _diaSeleccionadoKey)) {
        _diaSeleccionadoKey = _dayKey(dias.first);
      }
    });
  }

  // ── Cancelar reserva (logica preservada del original) ─────────────────────

  /// Minutos antes del inicio en que cierra la CANCELACION (no la reserva:
  /// son dos ventanas distintas). Se resuelve clase -> estudio -> 720 (12 hs).
  int _cierreMinutosDe(Map<String, dynamic> reserva) =>
      CierreMinutos.cancelacion(reserva['clases'] as Map?);

  bool _puedeCancelar(Map<String, dynamic> reserva) {
    final fecha = _parseFecha((reserva['clases'] as Map?)?['fecha']);
    if (fecha == null) return false;
    final cierreMin = _cierreMinutosDe(reserva);
    return _ahoraAr()
        .isBefore(fecha.subtract(Duration(minutes: cierreMin)));
  }

  /// Formato amigable de duracion para los mensajes.
  String _formatDuracion(int minutes) => CierreMinutos.formatDuracion(minutes);

  Future<void> _cancelar(Map<String, dynamic> reserva) async {
    if (!_puedeCancelar(reserva)) {
      final cierreMin = _cierreMinutosDe(reserva);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Ya no se puede cancelar',
            style: TextStyle(
                color: AppColors.black,
                fontSize: 16,
                fontWeight: FontWeight.w700),
          ),
          content: Text(
            'La ventana para cancelar cerró ${_formatDuracion(cierreMin)} antes '
            'de la clase, así que esta reserva ya no se puede cancelar.\n\n'
            'Si no asistís, se descuentan los créditos: el estudio ya te '
            'guardó el lugar y no puede ofrecérselo a otra persona.',
            style: const TextStyle(
                color: AppColors.black, fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Entendido',
                  style: TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          '¿Cancelar esta reserva?',
          style: TextStyle(
            color: AppColors.black,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Tus créditos se devuelven al instante.',
          style: TextStyle(
            color: AppColors.black,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.grey),
            child: const Text(
              'No, mantener',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
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
            child: const Text(
              'Sí, cancelar',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<AppProvider>();
    try {
      final devueltos = await _reservasService.cancelarReserva(
        reserva['codigo_qr']?.toString() ?? '',
      );
      // El aviso a quien sigue en la lista de espera lo hace el SERVIDOR:
      // cancelarReserva() dispara waitlist_promote_next, que promueve, crea la
      // campanita y (via el trigger de notificaciones_usuario) manda el push.
      await provider.refrescarUsuario();
      await _cargar();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            devueltos > 0
                ? 'Reserva cancelada. Te devolvimos $devueltos crédito${devueltos == 1 ? '' : 's'}.'
                : 'Reserva cancelada.',
          ),
          backgroundColor: AppColors.blackSoft,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              'No se pudo cancelar: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _verQr(Map<String, dynamic> reserva) {
    final codigoQr = reserva['codigo_qr']?.toString() ?? '';
    if (codigoQr.isNotEmpty) {
      context.push('/reserva-confirmada/${Uri.encodeComponent(codigoQr)}');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AppProvider>().usuario;
    final creditos = usuario?.creditos ?? 0;
    final hoy = _ahoraAr();
    final dias = _diasDisponibles;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: _darkAppBar,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Mis Reservas',
          style: TextStyle(
            color: _cream,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: _cream),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _cream),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _CreditosChip(
              creditos: creditos,
              onTap: () => context.push('/mis-creditos'),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _cargar,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
                        child: Column(
                          children: [
                            const Icon(Icons.cloud_off_rounded,
                                size: 48, color: AppColors.grey),
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppColors.grey, height: 1.4),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: _cargar,
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 16, bottom: 32),
                children: [
                  // SECCIÓN EN ESPERA (pre_confirmadas + lista_espera).
                  // Solo aparece si hay algo, sino la pantalla arranca en
                  // PRÓXIMAS como antes.
                  if (_preReservas.isNotEmpty || _enEspera.isNotEmpty) ...[
                    const _SectionLabel('EN ESPERA'),
                    const SizedBox(height: 10),
                    ..._preReservas.map((pre) => Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: _PreReservaCard(
                            reserva: pre,
                            onConfirmar: () {
                              final claseId =
                                  (pre['clase_id'] as num?)?.toInt();
                              if (claseId != null) {
                                context.push('/clase/$claseId');
                              }
                            },
                          ),
                        )),
                    ..._enEspera.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final item = entry.value;
                      final claseId =
                          (item['clase_id'] as num?)?.toInt();
                      return Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: _EsperaCard(
                          entry: item,
                          posicion: (item['posicion'] as num?)?.toInt() ??
                              idx + 1,
                          onSalir: claseId == null
                              ? null
                              : () => _salirDeListaEspera(claseId),
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                  ],

                  // SECCIÓN PRÓXIMAS
                  const _SectionLabel('PRÓXIMAS'),
                  const SizedBox(height: 10),
                  if (_proximas.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: _ProximasVacioCard(
                        onExplorar: () => context.go('/explorar'),
                      ),
                    )
                  else ...[
                    ..._proximas.map((reserva) => Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: _ProximaCard(
                            reserva: reserva,
                            hoy: hoy,
                            canCancel: _puedeCancelar(reserva),
                            onQr: () => _verQr(reserva),
                            onCancelar: () => _cancelar(reserva),
                          ),
                        )),
                    const SizedBox(height: 12),
                  ],

                  // SECCIÓN DISPONIBLES
                  const _SectionLabel('DISPONIBLES'),
                  const SizedBox(height: 10),
                  if (dias.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: _SinDisponiblesCard(
                        onExplorar: () => context.go('/explorar'),
                      ),
                    )
                  else ...[
                    _DaySelector(
                      dias: dias,
                      seleccionadoKey: _diaSeleccionadoKey,
                      hoy: hoy,
                      dayKeyOf: _dayKey,
                      onTap: (key) =>
                          setState(() => _diaSeleccionadoKey = key),
                    ),
                    const SizedBox(height: 10),
                    if (_categorias.length > 1) ...[
                      _CategorySelector(
                        categorias: _categorias,
                        seleccionada: _categoriaSeleccionada,
                        onTap: _seleccionarCategoria,
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_clasesDelDia.isEmpty)
                      const _EmptyDayState()
                    else
                      ..._clasesDelDia.map((clase) => Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: _ClaseDisponibleCard(
                              clase: clase,
                              hoy: hoy,
                              onTap: () =>
                                  context.push('/clase/${clase['id']}'),
                            ),
                          )),
                    const SizedBox(height: 12),
                  ],

                  // SECCIÓN HISTORIAL
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _HistorialToggle(
                      expanded: _historialExpanded,
                      onTap: () => setState(
                          () => _historialExpanded = !_historialExpanded),
                    ),
                  ),
                  if (_historialExpanded) ...[
                    const SizedBox(height: 12),
                    if (_historial.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Text(
                          'Tu historial está vacío.',
                          style: TextStyle(
                            color: AppColors.grey,
                            fontSize: 13,
                          ),
                        ),
                      )
                    else
                      ..._historial.map((reserva) => Padding(
                            padding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            child: _HistorialCompactCard(reserva: reserva),
                          )),
                    if (_hasMoreHistorial || _loadingMoreHistorial)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: Center(
                          child: _loadingMoreHistorial
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                )
                              : TextButton(
                                  onPressed: _cargarMasHistorial,
                                  child: const Text('Cargar más'),
                                ),
                        ),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}

// ── Widgets compartidos ──────────────────────────────────────────────────────

class _CreditosChip extends StatelessWidget {
  final int creditos;
  final VoidCallback onTap;

  const _CreditosChip({required this.creditos, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$creditos cr',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

// ── Próxima Card ────────────────────────────────────────────────────────────

class _ProximaCard extends StatelessWidget {
  final Map<String, dynamic> reserva;
  final DateTime hoy;
  final bool canCancel;
  final VoidCallback onQr;
  final VoidCallback onCancelar;

  const _ProximaCard({
    required this.reserva,
    required this.hoy,
    required this.canCancel,
    required this.onQr,
    required this.onCancelar,
  });

  @override
  Widget build(BuildContext context) {
    final clase = reserva['clases'] as Map<String, dynamic>?;
    final estudio = clase?['estudios'] as Map<String, dynamic>?;
    final fecha = DateTime.tryParse(clase?['fecha']?.toString() ?? '');
    final hora = fecha != null
        ? '${fecha.hour.toString().padLeft(2, '0')}:'
            '${fecha.minute.toString().padLeft(2, '0')}'
        : '--:--';
    final fotoUrl =
        (clase?['imagen_url'] ?? estudio?['foto_url'])?.toString();

    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StudioImage(url: fotoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (clase?['nombre'] ?? 'Clase').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      (estudio?['nombre'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                hora,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (fecha != null) _FechaBadge(fecha: fecha, hoy: hoy),
              const SizedBox(width: 6),
              const _Badge(
                text: 'Confirmada',
                bg: _successBg,
                fg: _successFg,
              ),
              const Spacer(),
              _SmallButton(
                label: 'QR',
                onTap: onQr,
                primary: true,
              ),
              const SizedBox(width: 6),
              _SmallButton(
                label: 'Cancelar',
                onTap: onCancelar,
                primary: false,
                dimmed: !canCancel,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Clase Disponible Card ───────────────────────────────────────────────────

class _ClaseDisponibleCard extends StatelessWidget {
  final Map<String, dynamic> clase;
  final DateTime hoy;
  final VoidCallback onTap;

  const _ClaseDisponibleCard({
    required this.clase,
    required this.hoy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final estudio = clase['estudios'] as Map<String, dynamic>?;
    final fecha = DateTime.tryParse(clase['fecha']?.toString() ?? '');
    final hora = fecha != null
        ? '${fecha.hour.toString().padLeft(2, '0')}:'
            '${fecha.minute.toString().padLeft(2, '0')}'
        : '--:--';
    final categoria = (estudio?['categoria'] ?? '').toString();
    final lugares = (clase['lugares_disponibles'] as num?)?.toInt() ?? 0;
    final creditos = (clase['creditos'] as num?)?.toInt() ?? 0;
    final fotoUrl =
        (clase['imagen_url'] ?? estudio?['foto_url'])?.toString();

    return _WhiteCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StudioImage(url: fotoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (clase['nombre'] ?? 'Clase').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      (estudio?['nombre'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                hora,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (categoria.isNotEmpty) ...[
                _Badge(
                  text: categoria,
                  bg: _categoryBadgeBg,
                  fg: AppColors.primary,
                ),
                const SizedBox(width: 6),
              ],
              if (fecha != null) ...[
                _TiempoBadge(claseFecha: fecha, hoy: hoy),
                const SizedBox(width: 6),
              ],
              _LugaresBadge(lugares: lugares),
              const Spacer(),
              Text(
                '$creditos cr',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Historial Compact ───────────────────────────────────────────────────────

class _HistorialToggle extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;

  const _HistorialToggle({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.lightGrey),
        ),
        child: Row(
          children: [
            const Icon(Icons.history_rounded,
                color: AppColors.grey, size: 18),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Ver historial',
                style: TextStyle(
                  color: AppColors.grey,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: AppColors.grey,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _HistorialCompactCard extends StatelessWidget {
  final Map<String, dynamic> reserva;
  const _HistorialCompactCard({required this.reserva});

  @override
  Widget build(BuildContext context) {
    final clase = reserva['clases'] as Map<String, dynamic>?;
    final estudio = clase?['estudios'] as Map<String, dynamic>?;
    final fecha = DateTime.tryParse(clase?['fecha']?.toString() ?? '');
    final estado = (reserva['estado'] as String?) ?? '';
    final fotoUrl =
        (clase?['imagen_url'] ?? estudio?['foto_url'])?.toString();

    Color estadoFg;
    Color estadoBg;
    String estadoLabel;
    switch (estado) {
      case 'completada':
        estadoFg = _successFg;
        estadoBg = _successBg;
        estadoLabel = 'Presente';
        break;
      case 'cancelada':
      case 'cancelada_por_estudio':
        estadoFg = AppColors.error;
        estadoBg = const Color(0xFFFFEBEE);
        estadoLabel = 'Cancelada';
        break;
      case 'ausente':
        estadoFg = const Color(0xFFE65100);
        estadoBg = const Color(0xFFFFF3E0);
        estadoLabel = 'Ausente';
        break;
      default:
        estadoFg = AppColors.grey;
        estadoBg = AppColors.lightGrey;
        estadoLabel = estado.isEmpty
            ? '—'
            : '${estado[0].toUpperCase()}${estado.substring(1)}';
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 40,
              height: 40,
              child: fotoUrl != null && fotoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: fotoUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => _smallFallback(),
                      errorWidget: (context, url, error) => _smallFallback(),
                    )
                  : _smallFallback(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (clase?['nombre'] ?? 'Clase').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  (estudio?['nombre'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.grey,
                    fontSize: 11,
                  ),
                ),
                if (fecha != null)
                  Text(
                    DateFormat('d MMM · HH:mm', 'es').format(fecha),
                    style: const TextStyle(
                      color: AppColors.mutedText,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Badge(text: estadoLabel, bg: estadoBg, fg: estadoFg),
        ],
      ),
    );
  }

  Widget _smallFallback() {
    return Container(
      color: AppColors.lightGrey,
      child: const Icon(Icons.fitness_center_rounded,
          color: AppColors.grey, size: 18),
    );
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

class _WhiteCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _WhiteCard({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final container = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return container;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: container,
      ),
    );
  }
}

class _StudioImage extends StatelessWidget {
  final String? url;
  const _StudioImage({required this.url});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.fitness_center_rounded,
          color: AppColors.grey, size: 26),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url!,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        placeholder: (context, url) => fallback,
        errorWidget: (context, url, error) => fallback,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const _Badge({required this.text, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FechaBadge extends StatelessWidget {
  final DateTime fecha;
  final DateTime hoy;
  const _FechaBadge({required this.fecha, required this.hoy});

  static const _weekdayAbbr = [
    'LUN',
    'MAR',
    'MIÉ',
    'JUE',
    'VIE',
    'SÁB',
    'DOM'
  ];

  @override
  Widget build(BuildContext context) {
    final hoyDia = DateTime(hoy.year, hoy.month, hoy.day);
    final fechaDia = DateTime(fecha.year, fecha.month, fecha.day);
    final diff = fechaDia.difference(hoyDia).inDays;

    String text;
    bool urgent = false;
    if (diff == 0) {
      text = 'HOY';
      urgent = true;
    } else if (diff == 1) {
      text = 'MAÑANA';
    } else {
      text = '${_weekdayAbbr[fecha.weekday - 1]} ${fecha.day}';
    }

    return _Badge(
      text: text,
      bg: urgent ? _categoryBadgeBg : const Color(0xFFF1F1F1),
      fg: urgent ? AppColors.primary : AppColors.grey,
    );
  }
}

class _TiempoBadge extends StatelessWidget {
  final DateTime claseFecha;
  final DateTime hoy;
  const _TiempoBadge({required this.claseFecha, required this.hoy});

  @override
  Widget build(BuildContext context) {
    final diffMin = claseFecha.difference(hoy).inMinutes;
    final hoyDia = DateTime(hoy.year, hoy.month, hoy.day);
    final claseDia =
        DateTime(claseFecha.year, claseFecha.month, claseFecha.day);
    final diffDias = claseDia.difference(hoyDia).inDays;

    String text;
    bool urgent = false;

    if (diffMin > 0 && diffMin < 180) {
      urgent = true;
      if (diffMin < 60) {
        text = 'En $diffMin min';
      } else {
        final h = (diffMin / 60).round();
        text = h == 1 ? 'En 1 hora' : 'En $h horas';
      }
    } else if (diffDias == 0) {
      text = 'Hoy';
    } else if (diffDias == 1) {
      text = 'Mañana';
    } else {
      const abbr = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
      text = '${abbr[claseFecha.weekday - 1]} ${claseFecha.day}';
    }

    return _Badge(
      text: text,
      bg: urgent ? _categoryBadgeBg : const Color(0xFFF1F1F1),
      fg: urgent ? AppColors.primary : AppColors.grey,
    );
  }
}

class _LugaresBadge extends StatelessWidget {
  final int lugares;
  const _LugaresBadge({required this.lugares});

  @override
  Widget build(BuildContext context) {
    if (lugares <= 0) {
      return const _Badge(
        text: 'Sin lugares',
        bg: Color(0xFFF1F1F1),
        fg: AppColors.grey,
      );
    }
    if (lugares == 1) {
      return const _Badge(
        text: 'Último lugar',
        bg: _categoryBadgeBg,
        fg: AppColors.primary,
      );
    }
    return _Badge(
      text: '$lugares lugares',
      bg: const Color(0xFFF1F1F1),
      fg: AppColors.grey,
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  // dimmed: el boton se ve disabled visualmente PERO sigue siendo tappable.
  // Lo usamos para "Cancelar" cuando esta fuera de la ventana: el tap
  // dispara el snackbar con el mensaje del motivo.
  final bool dimmed;

  const _SmallButton({
    required this.label,
    required this.onTap,
    required this.primary,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final atenuado = disabled || dimmed;
    final bg = primary
        ? (atenuado ? AppColors.lightGrey : AppColors.primary)
        : Colors.transparent;
    final fg = primary
        ? Colors.white
        : (atenuado ? AppColors.lightGrey : AppColors.grey);
    final border = primary
        ? Colors.transparent
        : (atenuado ? AppColors.lightGrey : AppColors.grey);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DaySelector extends StatelessWidget {
  final List<DateTime> dias;
  final String? seleccionadoKey;
  final DateTime hoy;
  final String Function(DateTime) dayKeyOf;
  final ValueChanged<String> onTap;

  const _DaySelector({
    required this.dias,
    required this.seleccionadoKey,
    required this.hoy,
    required this.dayKeyOf,
    required this.onTap,
  });

  static const _weekdayAbbr = [
    'LUN',
    'MAR',
    'MIÉ',
    'JUE',
    'VIE',
    'SÁB',
    'DOM'
  ];

  String _label(DateTime dia) {
    final hoyDia = DateTime(hoy.year, hoy.month, hoy.day);
    final diff = dia.difference(hoyDia).inDays;
    if (diff == 0) return 'HOY';
    if (diff == 1) return 'MAÑ';
    return '${_weekdayAbbr[dia.weekday - 1]} ${dia.day}';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: dias.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final dia = dias[index];
          final key = dayKeyOf(dia);
          final active = key == seleccionadoKey;
          return GestureDetector(
            onTap: () => onTap(key),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active ? AppColors.primary : _chipDark,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _label(dia),
                style: TextStyle(
                  color: active ? Colors.black : _cream,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  final List<String> categorias;
  final String seleccionada;
  final ValueChanged<String> onTap;

  const _CategorySelector({
    required this.categorias,
    required this.seleccionada,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categorias.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final categoria = categorias[index];
          final active = categoria == seleccionada;
          return GestureDetector(
            onTap: () => onTap(categoria),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: active ? _darkAppBar : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: active ? AppColors.primary : _chipBorder,
                  width: active ? 1.4 : 1,
                ),
              ),
              child: Text(
                categoria,
                style: TextStyle(
                  color:
                      active ? AppColors.primary : const Color(0xFF5A534D),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProximasVacioCard extends StatelessWidget {
  final VoidCallback onExplorar;
  const _ProximasVacioCard({required this.onExplorar});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.calendar_today_outlined,
            color: AppColors.primary,
            size: 32,
          ),
          const SizedBox(height: 12),
          const Text(
            'No tenés clases próximas',
            style: TextStyle(
              color: AppColors.black,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Explorá lo que hay disponible',
            style: TextStyle(
              color: AppColors.grey,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onExplorar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'Explorar clases',
                style:
                    TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SinDisponiblesCard extends StatelessWidget {
  final VoidCallback onExplorar;
  const _SinDisponiblesCard({required this.onExplorar});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Por ahora no hay clases disponibles para reservar.',
              style: TextStyle(color: AppColors.grey, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: onExplorar,
            child: const Text('Explorar'),
          ),
        ],
      ),
    );
  }
}

class _EmptyDayState extends StatelessWidget {
  const _EmptyDayState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          const Icon(
            Icons.calendar_today_outlined,
            size: 40,
            color: Color(0xFFB2A89F),
          ),
          const SizedBox(height: 10),
          const Text(
            'No hay clases disponibles este día',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.black,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Probá con otro día o categoría',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Cards de "EN ESPERA" ─────────────────────────────────────────────────────

class _PreReservaCard extends StatelessWidget {
  final Map<String, dynamic> reserva;
  final VoidCallback onConfirmar;

  const _PreReservaCard({
    required this.reserva,
    required this.onConfirmar,
  });

  @override
  Widget build(BuildContext context) {
    final clase = reserva['clases'] as Map<String, dynamic>?;
    final estudio = clase?['estudios'] as Map<String, dynamic>?;
    final fecha = DateTime.tryParse(clase?['fecha']?.toString() ?? '');
    final fechaStr = fecha != null
        ? DateFormat("EEE d 'de' MMM · HH:mm", 'es').format(fecha)
        : '—';
    final expiresAt =
        DateTime.tryParse(reserva['expires_at']?.toString() ?? '');
    final remaining = expiresAt != null
        ? expiresAt.toLocal().difference(DateTime.now())
        : Duration.zero;
    final mins = remaining.inMinutes.clamp(0, 99);
    final secs = (remaining.inSeconds % 60).clamp(0, 59);
    final remainingStr =
        '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    return _WhiteCard(
      onTap: onConfirmar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timer_rounded,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Tenés $remainingStr para confirmar',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            (clase?['nombre'] ?? 'Clase').toString(),
            style: const TextStyle(
              color: AppColors.black,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            (estudio?['nombre'] ?? '').toString(),
            style: const TextStyle(color: AppColors.grey, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            fechaStr,
            style: const TextStyle(
              color: AppColors.mutedText,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Text(
              'Confirmar mi lugar',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EsperaCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  final int posicion;
  final VoidCallback? onSalir;

  const _EsperaCard({
    required this.entry,
    required this.posicion,
    required this.onSalir,
  });

  @override
  Widget build(BuildContext context) {
    final clase = entry['clases'] as Map<String, dynamic>?;
    final estudio = clase?['estudios'] as Map<String, dynamic>?;
    final fecha = DateTime.tryParse(clase?['fecha']?.toString() ?? '');
    final fechaStr = fecha != null
        ? DateFormat("EEE d 'de' MMM · HH:mm", 'es').format(fecha)
        : '—';

    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _categoryBadgeBg,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  'Posición #$posicion',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            (clase?['nombre'] ?? 'Clase').toString(),
            style: const TextStyle(
              color: AppColors.black,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            (estudio?['nombre'] ?? '').toString(),
            style: const TextStyle(color: AppColors.grey, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            fechaStr,
            style: const TextStyle(
              color: AppColors.mutedText,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'No se cobran créditos hasta confirmar.',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onSalir,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.grey,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
              ),
              child: const Text(
                'Salir de la lista',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
