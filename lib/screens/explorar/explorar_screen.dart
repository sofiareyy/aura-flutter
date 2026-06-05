import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../services/clases_service.dart';
import '../../services/reservas_service.dart';

const _darkAppBar = Color(0xFF1A1A1A);
const _darkChip = Color(0xFF252525);
const _chipBorder = Color(0xFF333333);
const _cream = Color(0xFFF5F0E8);
const _creamSubtle = Color(0xFFC7BFB6);
const _categoryBadgeBg = Color(0xFFFDF0E8);

class ExplorarScreen extends StatefulWidget {
  const ExplorarScreen({super.key});

  @override
  State<ExplorarScreen> createState() => _ExplorarScreenState();
}

class _ExplorarScreenState extends State<ExplorarScreen> {
  final _clasesService = ClasesService();
  final _reservasService = ReservasService();

  List<Map<String, dynamic>> _clases = [];
  List<Map<String, dynamic>> _misReservas = [];
  List<String> _categorias = const ['Todos'];
  String _categoriaSeleccionada = 'Todos';
  String? _diaSeleccionadoKey;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final categoria =
        GoRouterState.of(context).uri.queryParameters['categoria'];
    if (categoria != null &&
        categoria.isNotEmpty &&
        _categoriaSeleccionada == 'Todos') {
      setState(() => _categoriaSeleccionada = categoria);
    }
  }

  Future<void> _cargar() async {
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _clasesService.getProximasClases(limit: 200, offset: 0),
        Future(() async {
          try {
            // listCategorias no existe; usamos las categorias derivadas de las
            // clases cargadas. Keep para futura expansion.
            return <String>[];
          } catch (_) {
            return <String>[];
          }
        }),
        _reservasService.getReservasUsuario(),
      ]);
      if (!mounted) return;

      final clases = (results[0] as List<Map<String, dynamic>>).toList()
        ..sort(_compareByFecha);
      final reservas = (results[2] as List<Map<String, dynamic>>).toList()
        ..sort(_compareByReservaFecha);

      // Categorias: derivadas de los estudios presentes en las clases.
      final categoriasSet = <String>{};
      for (final c in clases) {
        final est = c['estudios'] as Map<String, dynamic>?;
        final cat = est?['categoria']?.toString().trim();
        if (cat != null && cat.isNotEmpty) categoriasSet.add(cat);
      }
      final categorias = ['Todos', ...categoriasSet.toList()..sort()];

      setState(() {
        _clases = clases;
        _misReservas = reservas;
        _categorias = categorias;
        if (!_categorias.contains(_categoriaSeleccionada)) {
          _categoriaSeleccionada = 'Todos';
        }
        _diaSeleccionadoKey = _primerDiaConClases();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Helpers de fecha ──────────────────────────────────────────────────────
  //
  // Las fechas en DB son strings naive ('YYYY-MM-DD HH:MM:SS') que ya estan
  // en hora Argentina (UTC-3). DateTime.tryParse las devuelve como locales,
  // y para 'ahora' construimos un local-naive con componentes AR para
  // comparar manzanas con manzanas, independiente del timezone del device.

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

  // ── Filtros derivados ─────────────────────────────────────────────────────

  bool _matchesCategoria(Map<String, dynamic> clase) {
    if (_categoriaSeleccionada == 'Todos') return true;
    final cat =
        (clase['estudios'] as Map?)?['categoria']?.toString().toLowerCase();
    return cat == _categoriaSeleccionada.toLowerCase();
  }

  /// Lista de dias (ordenados ASC) que tienen al menos una clase disponible
  /// con la categoria seleccionada.
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

  /// Clases del dia seleccionado, filtradas por categoria, ordenadas ASC.
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
      // Si la categoria nueva no incluye el dia seleccionado, saltar al
      // primer dia que si la tenga.
      final dias = _diasDisponibles;
      if (dias.isEmpty) {
        _diaSeleccionadoKey = null;
      } else if (!dias.any((d) => _dayKey(d) == _diaSeleccionadoKey)) {
        _diaSeleccionadoKey = _dayKey(dias.first);
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AppProvider>().usuario;
    final creditos = usuario?.creditos ?? 0;
    final dias = _diasDisponibles;
    final hoy = _ahoraAr();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: _darkAppBar,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Explorar',
          style: TextStyle(
            color: _cream,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: _cream),
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
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 16, bottom: 32),
                children: [
                  if (_misReservas.isNotEmpty) ...[
                    const _SectionLabel('MIS PRÓXIMAS CLASES'),
                    const SizedBox(height: 10),
                    _MisReservasRow(reservas: _misReservas),
                    const SizedBox(height: 24),
                  ],
                  if (dias.isNotEmpty) ...[
                    _DaySelector(
                      dias: dias,
                      seleccionadoKey: _diaSeleccionadoKey,
                      hoy: hoy,
                      dayKeyOf: _dayKey,
                      onTap: (key) =>
                          setState(() => _diaSeleccionadoKey = key),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_categorias.length > 1) ...[
                    _CategorySelector(
                      categorias: _categorias,
                      seleccionada: _categoriaSeleccionada,
                      onTap: _seleccionarCategoria,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_clasesDelDia.isEmpty)
                    const _EmptyDayState()
                  else
                    ..._clasesDelDia.map(
                      (clase) => Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: _ClaseCard(
                          clase: clase,
                          hoy: hoy,
                          onTap: () =>
                              context.push('/clase/${clase['id']}'),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

// ── Widgets ─────────────────────────────────────────────────────────────────

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
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _MisReservasRow extends StatelessWidget {
  final List<Map<String, dynamic>> reservas;
  const _MisReservasRow({required this.reservas});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: reservas.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final r = reservas[index];
          return _ReservaMiniCard(reserva: r);
        },
      ),
    );
  }
}

class _ReservaMiniCard extends StatelessWidget {
  final Map<String, dynamic> reserva;
  const _ReservaMiniCard({required this.reserva});

  @override
  Widget build(BuildContext context) {
    final clase = reserva['clases'] as Map<String, dynamic>?;
    final estudio = clase?['estudios'] as Map<String, dynamic>?;
    final fecha = DateTime.tryParse(clase?['fecha']?.toString() ?? '');
    final hora = fecha != null
        ? '${fecha.hour.toString().padLeft(2, '0')}:'
            '${fecha.minute.toString().padLeft(2, '0')}'
        : '--:--';
    final codigoQr = reserva['codigo_qr']?.toString() ?? '';

    return InkWell(
      onTap: codigoQr.isEmpty
          ? null
          : () => context.push('/reserva-confirmada/$codigoQr'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 160,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: _darkChip,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (clase?['nombre'] ?? 'Clase').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _cream,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              (estudio?['nombre'] ?? '').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _creamSubtle,
                fontSize: 11,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Text(
                  hora,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'QR',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
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
                color: active ? AppColors.primary : _darkChip,
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
                  color: active ? AppColors.primary : const Color(0xFF5A534D),
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

class _ClaseCard extends StatelessWidget {
  final Map<String, dynamic> clase;
  final DateTime hoy;
  final VoidCallback onTap;

  const _ClaseCard({
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
    final fotoUrl = (clase['imagen_url'] ?? estudio?['foto_url'])?.toString();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
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
        ),
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
      child: const Icon(
        Icons.fitness_center_rounded,
        color: AppColors.grey,
        size: 26,
      ),
    );

    if (url == null || url!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url!,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
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

class _EmptyDayState extends StatelessWidget {
  const _EmptyDayState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      child: Column(
        children: [
          const Icon(
            Icons.calendar_today_outlined,
            size: 44,
            color: Color(0xFFB2A89F),
          ),
          const SizedBox(height: 12),
          const Text(
            'No hay clases disponibles este día',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.black,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Probá con otro día o categoría',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.grey,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
