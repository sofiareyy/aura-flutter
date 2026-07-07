import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/organizadores_links.dart';
import '../../models/estudio.dart';
import '../../providers/app_provider.dart';
import '../../services/clases_service.dart';
import '../../services/estudios_service.dart';

class ExplorarScreen extends StatefulWidget {
  const ExplorarScreen({super.key});

  @override
  State<ExplorarScreen> createState() => _ExplorarScreenState();
}

class _ExplorarScreenState extends State<ExplorarScreen> {
  final _estudiosService = EstudiosService();
  final _clasesService = ClasesService();
  final _searchCtrl = TextEditingController();

  List<Estudio> _estudios = [];
  List<Map<String, dynamic>> _clases = [];
  List<String> _categorias = const ['Todos'];
  String _categoriaSeleccionada = 'Todos';
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMoreClases = true;
  int _clasesOffset = 0;
  static const _pageSize = 20;
  bool _categoriaInicialAplicada = false;
  bool _showAllDestacados = false;
  int? _estudioAsociadoId;

  // Filtros avanzados
  Set<int> _diasFiltro = {};
  Set<String> _horarioFiltro = {};
  int _maxCreditos = 50;

  int get _cantFiltrosActivos =>
      _diasFiltro.length + _horarioFiltro.length + (_maxCreditos < 50 ? 1 : 0);

  @override
  void initState() {
    super.initState();
    _cargar();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Leer estudio asociado del provider (no rebuilds innecesarios)
    _estudioAsociadoId =
        context.read<AppProvider>().estudioAsociado?.id;

    if (_categoriaInicialAplicada) return;
    final categoria =
        GoRouterState.of(context).uri.queryParameters['categoria'];
    if (categoria != null && categoria.isNotEmpty) {
      _categoriaSeleccionada = categoria;
    }
    _categoriaInicialAplicada = true;
  }

  Future<void> _cargar() async {
    if (mounted) setState(() => _loading = true);

    final results = await Future.wait([
      _estudiosService.getEstudios(),
      _clasesService.getProximasClases(limit: _pageSize, offset: 0),
      _estudiosService.getCategorias(),
    ]);

    if (!mounted) return;
    final nuevasClases = List<Map<String, dynamic>>.from(
      results[1] as List<Map<String, dynamic>>,
    );
    // Sort defensivo asc en el cliente, aunque el backend ya lo haga.
    nuevasClases.sort((a, b) {
      final fa = DateTime.tryParse(a['fecha']?.toString() ?? '');
      final fb = DateTime.tryParse(b['fecha']?.toString() ?? '');
      if (fa == null && fb == null) return 0;
      if (fa == null) return 1;
      if (fb == null) return -1;
      return fa.compareTo(fb);
    });
    setState(() {
      _estudios = results[0] as List<Estudio>;
      _clases = nuevasClases;
      _clasesOffset = nuevasClases.length;
      _hasMoreClases = nuevasClases.length == _pageSize;
      _categorias = results[2] as List<String>;
      if (!_categorias.contains(_categoriaSeleccionada)) {
        _categoriaSeleccionada = 'Todos';
      }
      _loading = false;
    });
  }

  Future<void> _cargarMasClases() async {
    if (_loadingMore || !_hasMoreClases) return;
    setState(() => _loadingMore = true);
    try {
      final mas = await _clasesService.getProximasClases(
        limit: _pageSize,
        offset: _clasesOffset,
      );
      if (!mounted) return;
      final merged = [..._clases, ...mas];
      merged.sort((a, b) {
        final fa = DateTime.tryParse(a['fecha']?.toString() ?? '');
        final fb = DateTime.tryParse(b['fecha']?.toString() ?? '');
        if (fa == null && fb == null) return 0;
        if (fa == null) return 1;
        if (fb == null) return -1;
        return fa.compareTo(fb);
      });
      setState(() {
        _clases = merged;
        _clasesOffset += mas.length;
        _hasMoreClases = mas.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _abrirMapa() {
    final query = <String, String>{};
    final texto = _searchCtrl.text.trim();
    if (texto.isNotEmpty) query['q'] = texto;
    if (_categoriaSeleccionada != 'Todos') {
      query['categoria'] = _categoriaSeleccionada;
    }
    final uri = Uri(path: '/mapa', queryParameters: query.isEmpty ? null : query);
    context.push(uri.toString());
  }

  List<Estudio> get _estudiosFiltrados {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtrados = _estudios.where((estudio) {
      final matchesCategory = _categoriaSeleccionada == 'Todos' ||
          estudio.categoria.toLowerCase() ==
              _categoriaSeleccionada.toLowerCase();
      final matchesSearch = query.isEmpty ||
          estudio.nombre.toLowerCase().contains(query) ||
          (estudio.barrio?.toLowerCase().contains(query) ?? false) ||
          estudio.categoria.toLowerCase().contains(query);
      return matchesCategory && matchesSearch;
    }).toList();

    // Pinear estudio asociado al tope si está en los resultados
    if (_estudioAsociadoId != null) {
      final idx =
          filtrados.indexWhere((e) => e.id == _estudioAsociadoId);
      if (idx > 0) {
        final asociado = filtrados.removeAt(idx);
        filtrados.insert(0, asociado);
      }
    }
    return filtrados;
  }

  List<Map<String, dynamic>> get _clasesConEstudio {
    final filteredIds = _estudiosFiltrados.map((e) => e.id).toSet();
    final filtered = _clases.where((clase) {
      final estudio = clase['estudios'] as Map<String, dynamic>?;
      if (filteredIds.isNotEmpty && !filteredIds.contains(estudio?['id'])) {
        return false;
      }
      // BUG 15: parsear con 'Z' fuerza UTC en vez de local del device, y
      // como las fechas en DB ya estan en hora Argentina (UTC-3) sin
      // marker, weekday/hour del DateTime UTC reflejan la hora Argentina
      // independiente del timezone del device.
      // Filtro por día de la semana
      if (_diasFiltro.isNotEmpty) {
        final raw = clase['fecha']?.toString() ?? '';
        final fecha = DateTime.tryParse('${raw.replaceFirst(' ', 'T')}Z');
        if (fecha == null || !_diasFiltro.contains(fecha.weekday)) return false;
      }
      // Filtro por horario
      if (_horarioFiltro.isNotEmpty) {
        final raw = clase['fecha']?.toString() ?? '';
        final fecha = DateTime.tryParse('${raw.replaceFirst(' ', 'T')}Z');
        if (fecha == null) return false;
        final hora = fecha.hour;
        final matchesHorario = _horarioFiltro.any((h) {
          switch (h) {
            case 'manana':
              return hora >= 6 && hora <= 11;
            case 'mediodia':
              return hora >= 12 && hora <= 14;
            case 'tarde':
              return hora >= 15 && hora <= 18;
            case 'noche':
              return hora >= 19 && hora <= 22;
            default:
              return false;
          }
        });
        if (!matchesHorario) return false;
      }
      // Filtro por créditos
      final creditos = (clase['creditos'] as num?)?.toInt() ?? 99;
      if (creditos > _maxCreditos) return false;

      return true;
    }).toList();
    // Sort por fecha asc para que la mas proxima quede primero.
    filtered.sort((a, b) {
      final fa = DateTime.tryParse(a['fecha']?.toString() ?? '');
      final fb = DateTime.tryParse(b['fecha']?.toString() ?? '');
      if (fa == null && fb == null) return 0;
      if (fa == null) return 1;
      if (fb == null) return -1;
      return fa.compareTo(fb);
    });
    return filtered;
  }

  void _mostrarFiltros() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        Set<int> diasTemp = Set.from(_diasFiltro);
        Set<String> horarioTemp = Set.from(_horarioFiltro);
        int creditosTemp = _maxCreditos;

        const diasLabels = {1: 'Lun', 2: 'Mar', 3: 'Mié', 4: 'Jue', 5: 'Vie', 6: 'Sáb', 7: 'Dom'};
        const horarioLabels = {
          'manana': 'Mañana',
          'mediodia': 'Mediodía',
          'tarde': 'Tarde',
          'noche': 'Noche',
        };

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
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
                          borderRadius: BorderRadius.circular(999)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Filtros',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.black),
                  ),
                  const SizedBox(height: 18),
                  const Text('Día',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF403A35))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: diasLabels.entries.map((e) {
                      final selected = diasTemp.contains(e.key);
                      return GestureDetector(
                        onTap: () => setSheetState(() {
                          if (selected) {
                            diasTemp.remove(e.key);
                          } else {
                            diasTemp.add(e.key);
                          }
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.black : AppColors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: selected
                                    ? AppColors.black
                                    : AppColors.warmBorder),
                          ),
                          child: Text(
                            e.value,
                            style: TextStyle(
                              color: selected
                                  ? AppColors.white
                                  : const Color(0xFFC7C0B9),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  const Text('Horario',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF403A35))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: horarioLabels.entries.map((e) {
                      final selected = horarioTemp.contains(e.key);
                      return GestureDetector(
                        onTap: () => setSheetState(() {
                          if (selected) {
                            horarioTemp.remove(e.key);
                          } else {
                            horarioTemp.add(e.key);
                          }
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.black : AppColors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: selected
                                    ? AppColors.black
                                    : AppColors.warmBorder),
                          ),
                          child: Text(
                            e.value,
                            style: TextStyle(
                              color: selected
                                  ? AppColors.white
                                  : const Color(0xFFC7C0B9),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Créditos máximos',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF403A35))),
                      Text(
                        creditosTemp < 50 ? '$creditosTemp cr' : 'Todos',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary),
                      ),
                    ],
                  ),
                  Slider(
                    value: creditosTemp.toDouble(),
                    min: 5,
                    max: 50,
                    divisions: 9,
                    activeColor: AppColors.primary,
                    inactiveColor: const Color(0xFFE0DBD6),
                    onChanged: (v) =>
                        setSheetState(() => creditosTemp = v.toInt()),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _diasFiltro = {};
                              _horarioFiltro = {};
                              _maxCreditos = 50;
                            });
                            Navigator.of(ctx).pop();
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.black,
                            side: const BorderSide(color: AppColors.warmBorder),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Limpiar',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _diasFiltro = diasTemp;
                              _horarioFiltro = horarioTemp;
                              _maxCreditos = creditosTemp;
                            });
                            Navigator.of(ctx).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.black,
                            foregroundColor: AppColors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Aplicar',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final destacados = _showAllDestacados ? _estudiosFiltrados : _estudiosFiltrados.take(2).toList();
    final lista = _clasesConEstudio;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _cargar,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
            children: [
              const Text(
                'Explorar',
                style: TextStyle(
                  color: AppColors.black,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.warmBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: Color(0xFFC7C0B9),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              decoration: const InputDecoration(
                                hintText: 'Buscá clases, estudios...',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                hintStyle: TextStyle(
                                  color: Color(0xFFC7C0B9),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          if (_searchCtrl.text.isNotEmpty)
                            GestureDetector(
                              onTap: () => _searchCtrl.clear(),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Color(0xFFB4ACA5),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SizedBox(
                        height: 40,
                        child: OutlinedButton.icon(
                          onPressed: _mostrarFiltros,
                          icon: const Icon(Icons.tune_rounded, size: 16),
                          label: const Text('Filtrar',
                              style: TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.black,
                            side: const BorderSide(color: AppColors.warmBorder),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                      if (_cantFiltrosActivos > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$_cantFiltrosActivos',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _abrirMapa,
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4EC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFF0D9C9)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.map_outlined,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Ver estudios en mapa',
                          style: TextStyle(
                            color: AppColors.black,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 34,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categorias.length,
                  itemBuilder: (context, index) {
                    final categoria = _categorias[index];
                    final active = categoria == _categoriaSeleccionada;
                    return GestureDetector(
                      onTap: () => setState(() => _categoriaSeleccionada = categoria),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: active ? AppColors.black : AppColors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: active
                                ? AppColors.black
                                : AppColors.warmBorder,
                          ),
                        ),
                        child: Text(
                          categoria,
                          style: TextStyle(
                            color: active
                                ? AppColors.white
                                : const Color(0xFFC7C0B9),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'DESTACADOS HOY',
                    style: TextStyle(
                      color: Color(0xFF403A35),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _showAllDestacados = !_showAllDestacados),
                    child: Text(
                      _showAllDestacados ? 'Ver menos' : 'Ver todo',
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
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else if (destacados.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      const Icon(Icons.search_off_rounded, size: 44, color: Color(0xFFB2A89F)),
                      const SizedBox(height: 12),
                      const Text(
                        'No encontramos resultados',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Probá con otro término o categoría.',
                        style: TextStyle(color: Color(0xFF8C847C), fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _searchCtrl.clear();
                          _categoriaSeleccionada = 'Todos';
                        }),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Limpiar filtros'),
                      ),
                    ],
                  ),
                )
              else ...[
                SizedBox(
                  height: 180,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: destacados.length,
                    itemBuilder: (context, index) {
                      final estudio = destacados[index];
                      final esAsociado =
                          _estudioAsociadoId != null &&
                          estudio.id == _estudioAsociadoId;
                      return _FeaturedExploreCard(
                        estudio: estudio,
                        accentColor: index.isEven
                            ? AppColors.beigeCard
                            : AppColors.greenCard,
                        showBadge: esAsociado,
                        onTap: () {
                          if (estudio.id != null) {
                            context.push('/estudio/${estudio.id}');
                          }
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'TODOS LOS RESULTADOS',
                  style: TextStyle(
                    color: Color(0xFF403A35),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (lista.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No hay clases disponibles para esta búsqueda.',
                      style: TextStyle(color: Color(0xFF8C847C)),
                    ),
                  )
                else ...[
                  ...lista.asMap().entries.map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ResultCard(
                            clase: entry.value,
                            accentColor: entry.key.isEven
                                ? AppColors.beigeCard
                                : AppColors.blueCard,
                            onTap: () => context.push('/clase/${entry.value['id']}'),
                          ),
                        ),
                      ),
                  if (_hasMoreClases || _loadingMore)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: Center(
                        child: _loadingMore
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              )
                            : TextButton.icon(
                                onPressed: _cargarMasClases,
                                icon: const Icon(Icons.expand_more_rounded, size: 18),
                                label: const Text('Cargar más clases'),
                              ),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedExploreCard extends StatelessWidget {
  final Estudio estudio;
  final Color accentColor;
  final VoidCallback onTap;
  final bool showBadge;

  const _FeaturedExploreCard({
    required this.estudio,
    required this.accentColor,
    required this.onTap,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 166,
      margin: const EdgeInsets.only(right: 12),
      child: Material(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.warmBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                  child: SizedBox(
                    height: 92,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _FeaturedPhoto(
                          url: estudio.fotoUrl,
                          accentColor: accentColor,
                        ),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Pill(
                                text: estudio.categoria.toUpperCase(),
                                dark: true,
                              ),
                              const Spacer(),
                              if (showBadge)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Text(
                                    'Tu estudio',
                                    style: TextStyle(
                                      color: AppColors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Text(
                    estudio.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.black,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Text(
                    estudio.barrio ?? 'Buenos Aires',
                    style: const TextStyle(
                      color: Color(0xFFAAA19A),
                      fontSize: 12,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                  child: Text(
                    estudio.direccion ?? 'Ver estudio y ubicación',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFC1B7AF),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final Map<String, dynamic> clase;
  final Color accentColor;
  final VoidCallback onTap;

  const _ResultCard({
    required this.clase,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final estudio = clase['estudios'] as Map<String, dynamic>?;
    final categoria = (estudio?['categoria'] ?? '').toString().toUpperCase();
    final barrio = (estudio?['barrio'] ?? '').toString().toUpperCase();
    final imageUrl = (clase['imagen_url'] ?? estudio?['foto_url'])?.toString();
    final tipoPrecio = clase['tipo_precio']?.toString();
    final esWorkshop = clase['tipo']?.toString() == 'workshop';
    final organizadores = (clase['organizadores'] as List?) ?? const [];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 112,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.warmBorder),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(18),
                ),
                child: SizedBox(
                  width: 96,
                  height: double.infinity,
                  child: _ExploreClassImage(
                    imageUrl: imageUrl,
                    accentColor: accentColor,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              [categoria, barrio]
                                  .where((e) => e.isNotEmpty)
                                  .join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFD0C6BD),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (esWorkshop)
                            const _PriceBadge(
                              text: 'EVENTO',
                              color: AppColors.primary,
                            )
                          else if (tipoPrecio == 'pico')
                            _PriceBadge(
                              text: '⚡ POPULAR',
                              color: Color(0xFFE8763A),
                            )
                          else if (tipoPrecio == 'normal' ||
                              tipoPrecio == 'valle')
                            _PriceBadge(
                              text: '🏷️ PRECIO REDUCIDO',
                              color: Color(0xFF4CAF50),
                            ),
                          // tipoPrecio == 'experiencia' -> sin badge
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        (clase['nombre'] ?? 'Clase').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (esWorkshop && organizadores.isNotEmpty)
                        OrganizadoresLinks(organizadores: organizadores)
                      else
                        Text(
                          estudio?['direccion']?.toString() ?? 'Malabia 1510',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFA49B94),
                            fontSize: 12,
                          ),
                        ),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              clase['fecha'] != null
                                  ? _formatFecha(clase['fecha'].toString())
                                  : '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFB2A89F),
                                fontSize: 11,
                              ),
                            ),
                          ),
                          _Pill(text: '${clase['creditos'] ?? 10} cr'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatFecha(String raw) {
    final date = DateTime.tryParse(raw);
    if (date == null) return '';
    final hora = DateFormat('HH:mm', 'es').format(date);
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final fechaDia = DateTime(date.year, date.month, date.day);
    final diff = fechaDia.difference(hoy).inDays;

    String dia;
    if (diff == 0) {
      dia = 'Hoy';
    } else if (diff == 1) {
      dia = 'Mañana';
    } else if (diff > 1 && diff < 7) {
      // dia de la semana (lunes, martes, etc.)
      dia = toBeginningOfSentenceCase(
            DateFormat('EEEE', 'es').format(date),
          ) ??
          DateFormat('EEEE', 'es').format(date);
    } else {
      // 8 jun, 23 sep, etc.
      dia = DateFormat("d MMM", 'es').format(date);
    }
    return '$dia · $hora hs';
  }
}

class _ExploreClassImage extends StatelessWidget {
  final String? imageUrl;
  final Color accentColor;

  const _ExploreClassImage({
    required this.imageUrl,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imageUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => _fallback(),
        errorWidget: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Container(
      decoration: BoxDecoration(
        color: accentColor,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accentColor.withValues(alpha: 0.95),
            accentColor.withValues(alpha: 0.75),
            accentColor.withValues(alpha: 0.45),
          ],
        ),
      ),
    );
  }
}

class _FeaturedPhoto extends StatelessWidget {
  final String? url;
  final Color accentColor;

  const _FeaturedPhoto({required this.url, required this.accentColor});

  static const _placeholderBg = Color(0xFF252525);

  Widget _placeholder() {
    return Container(
      color: _placeholderBg,
      child: const Center(
        child: Icon(
          Icons.image,
          color: AppColors.grey,
          size: 28,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return _placeholder();
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      placeholder: (context, url) => _placeholder(),
      errorWidget: (context, url, error) => _placeholder(),
    );
  }
}

class _PriceBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _PriceBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final bool dark;

  const _Pill({
    required this.text,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF5A534D) : const Color(0xFFFFF1E8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: dark ? AppColors.white : AppColors.primary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}



