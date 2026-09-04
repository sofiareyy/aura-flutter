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
import '../../utils/explorar_filtros.dart';
import '../../utils/grilla_responsive.dart';
import '../../widgets/foto_red.dart';
import '../../widgets/titulo_seccion.dart';
import '../../widgets/aura_skeleton.dart';
import '../../core/theme/aura_tokens.dart';

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

  /// E2 (arreglo 1/9): las experiencias llegan por su propia query COMPLETA,
  /// no compiten con las clases por la paginación (con ~1000 clases en 60
  /// días, una experiencia del sábado caía en la posición ~97 del feed y el
  /// filtro "Experiencias" arrancaba vacío). Se mezclan por fecha al mostrar.
  List<Map<String, dynamic>> _experiencias = [];
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
  int _maxCreditos = 100;

  /// E2: 'todo' | 'clases' | 'experiencias'.
  String _tipoFiltro = 'todo';

  int get _cantFiltrosActivos =>
      _diasFiltro.length +
      _horarioFiltro.length +
      (_maxCreditos < 100 ? 1 : 0) +
      (_tipoFiltro != 'todo' ? 1 : 0);

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
    _estudioAsociadoId = context.read<AppProvider>().estudioAsociado?.id;

    if (_categoriaInicialAplicada) return;
    final categoria = GoRouterState.of(
      context,
    ).uri.queryParameters['categoria'];
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
      _clasesService.getProximasExperiencias(limit: 100),
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
      _experiencias = List<Map<String, dynamic>>.from(
        results[2] as List<Map<String, dynamic>>,
      );
      _clasesOffset = nuevasClases.length;
      _hasMoreClases = nuevasClases.length == _pageSize;
      _categorias = results[3] as List<String>;
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
    final uri = Uri(
      path: '/mapa',
      queryParameters: query.isEmpty ? null : query,
    );
    context.push(uri.toString());
  }

  List<Estudio> get _estudiosFiltrados {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtrados = _estudios.where((estudio) {
      // Un estudio matchea si CUALQUIERA de sus categorias coincide.
      final matchesCategory =
          _categoriaSeleccionada == 'Todos' ||
          estudio.tieneCategoria(_categoriaSeleccionada);
      final matchesSearch =
          query.isEmpty ||
          estudio.nombre.toLowerCase().contains(query) ||
          (estudio.barrio?.toLowerCase().contains(query) ?? false) ||
          estudio.categorias.any((c) => c.toLowerCase().contains(query));
      return matchesCategory && matchesSearch;
    }).toList();

    // Pinear estudio asociado al tope si está en los resultados
    if (_estudioAsociadoId != null) {
      final idx = filtrados.indexWhere((e) => e.id == _estudioAsociadoId);
      if (idx > 0) {
        final asociado = filtrados.removeAt(idx);
        filtrados.insert(0, asociado);
      }
    }
    return filtrados;
  }

  List<Map<String, dynamic>> get _clasesConEstudio {
    // E3 (1/9/2026): el chip y la busqueda evaluan LA CLASE, no el perfil del
    // estudio. Antes una clase solo aparecia si su estudio pasaba el filtro,
    // y Yessi (perfil "Fitness", 70 clases de Gym/Funcional) era invisible
    // bajo ese chip. El predicado es puro y esta testeado contra una foto de
    // produccion en test/explorar_filtros_test.dart.
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = mezclarFeed(_clases, _experiencias).where((clase) {
      if (!planVisible(
        clase,
        categoria: _categoriaSeleccionada,
        query: query,
      )) {
        return false;
      }
      // E2: filtro Todo / Clases / Experiencias.
      if (!tipoVisible(clase, _tipoFiltro)) return false;
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
        String tipoTemp = _tipoFiltro;

        const diasLabels = {
          1: 'Lun',
          2: 'Mar',
          3: 'Mié',
          4: 'Jue',
          5: 'Vie',
          6: 'Sáb',
          7: 'Dom',
        };
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
                20,
                16,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
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
                        borderRadius: BorderRadius.circular(AuraRadio.pastilla),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Filtros',
                    style: TextStyle(
                      fontSize: AuraTipo.titulo,
                      fontWeight: FontWeight.w700,
                      color: AppColors.black,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Tipo',
                    style: TextStyle(
                      fontSize: AuraTipo.secundario,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textoSecundario,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children:
                        const {
                          'todo': 'Todo',
                          'clases': 'Clases',
                          'experiencias': 'Experiencias',
                        }.entries.map((e) {
                          final selected = tipoTemp == e.key;
                          return GestureDetector(
                            onTap: () => setSheetState(() => tipoTemp = e.key),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.black
                                    : AppColors.white,
                                borderRadius: BorderRadius.circular(AuraRadio.pastilla),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.black
                                      : AppColors.warmBorder,
                                ),
                              ),
                              child: Text(
                                e.value,
                                style: TextStyle(
                                  color: selected
                                      ? AppColors.white
                                      : const Color(0xFF6E6761),
                                  fontSize: AuraTipo.secundario,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Día',
                    style: TextStyle(
                      fontSize: AuraTipo.secundario,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textoSecundario,
                    ),
                  ),
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
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.black : AppColors.white,
                            borderRadius: BorderRadius.circular(AuraRadio.pastilla),
                            border: Border.all(
                              color: selected
                                  ? AppColors.black
                                  : AppColors.warmBorder,
                            ),
                          ),
                          child: Text(
                            e.value,
                            style: TextStyle(
                              color: selected
                                  ? AppColors.white
                                  : AppColors.textoSuave,
                              fontSize: AuraTipo.secundario,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Horario',
                    style: TextStyle(
                      fontSize: AuraTipo.secundario,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textoSecundario,
                    ),
                  ),
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
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.black : AppColors.white,
                            borderRadius: BorderRadius.circular(AuraRadio.pastilla),
                            border: Border.all(
                              color: selected
                                  ? AppColors.black
                                  : AppColors.warmBorder,
                            ),
                          ),
                          child: Text(
                            e.value,
                            style: TextStyle(
                              color: selected
                                  ? AppColors.white
                                  : AppColors.textoSuave,
                              fontSize: AuraTipo.secundario,
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
                      const Text(
                        'Créditos máximos',
                        style: TextStyle(
                          fontSize: AuraTipo.secundario,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textoSecundario,
                        ),
                      ),
                      Text(
                        creditosTemp < 100 ? '$creditosTemp cr' : 'Todos',
                        style: const TextStyle(
                          fontSize: AuraTipo.secundario,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: creditosTemp.toDouble(),
                    min: 5,
                    max: 100,
                    divisions: 19,
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
                              _maxCreditos = 100;
                              _tipoFiltro = 'todo';
                            });
                            Navigator.of(ctx).pop();
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.black,
                            side: const BorderSide(color: AppColors.warmBorder),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AuraRadio.boton),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'Limpiar',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
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
                              _tipoFiltro = tipoTemp;
                            });
                            Navigator.of(ctx).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.black,
                            foregroundColor: AppColors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AuraRadio.boton),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'Aplicar',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
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
    // Colapsado: 4 estudios CON clases, sorteados por día con más chances
    // para el que tiene más oferta (ver destacadosDelDia). Expandido: todos
    // los del filtro, como siempre.
    final destacados = _showAllDestacados
        ? _estudiosFiltrados
        : destacadosDelDia(
            estudios: _estudiosFiltrados,
            clases: _clasesConEstudio,
            hoy: DateTime.now(),
            asociadoId: _estudioAsociadoId,
          );
    final lista = _clasesConEstudio;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _cargar,
          // Toda la pantalla topa en 1100 px de contenido (+44 de padding).
          // Se contiene la pantalla entera y no sólo la grilla: con el buscador
          // y los chips estirados a 1900 y los resultados centrados al medio,
          // la página se veía partida.
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: anchoMaxBuscador + AuraEspacio.margen * 2,
              ),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                // El margen lateral es UNO para toda la app: antes acá era 22
                // y en el Inicio 20.
                padding: const EdgeInsets.fromLTRB(
                  AuraEspacio.margen,
                  AuraEspacio.l,
                  AuraEspacio.margen,
                  AuraEspacio.xl,
                ),
                children: [
                  const Text(
                    'Explorar',
                    style: TextStyle(
                      color: AppColors.black,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AuraEspacio.l),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(AuraRadio.boton),
                            border: Border.all(color: AppColors.warmBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.search_rounded,
                                size: 18,
                                color: AppColors.textoSuave,
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
                                      color: AppColors.textoSuave,
                                      fontSize: AuraTipo.cuerpo,
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
                                    color: AppColors.textoSuave,
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
                              label: const Text(
                                'Filtrar',
                                style: TextStyle(fontSize: AuraTipo.secundario),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.black,
                                side: const BorderSide(
                                  color: AppColors.warmBorder,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AuraRadio.boton),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
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
                                    fontSize: AuraTipo.etiqueta,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AuraEspacio.m),
                  InkWell(
                    onTap: _abrirMapa,
                    borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
                    child: Ink(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4EC),
                        borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
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
                                fontSize: AuraTipo.cuerpo,
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
                  const SizedBox(height: AuraEspacio.l),
                  SizedBox(
                    height: 34,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _categorias.length,
                      itemBuilder: (context, index) {
                        final categoria = _categorias[index];
                        final active = categoria == _categoriaSeleccionada;
                        return GestureDetector(
                          onTap: () => setState(
                            () => _categoriaSeleccionada = categoria,
                          ),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: active ? AppColors.black : AppColors.white,
                              borderRadius: BorderRadius.circular(AuraRadio.pastilla),
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
                                    : AppColors.textoSuave,
                                fontSize: AuraTipo.secundario,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // El nombre es cierto: son de HOY (rotan por día) y están
                  // destacados con un criterio (más oferta, más chances).
                  // Antes eran los dos primeros del abecedario.
                  TituloSeccion(
                    'DESTACADOS HOY',
                    margenLateral: false,
                    accion: _showAllDestacados ? 'Ver menos' : 'Ver todo',
                    onAccion: () => setState(
                      () => _showAllDestacados = !_showAllDestacados,
                    ),
                  ),
                  // Antes: un spinner suelto en un hueco crema de 40+40 px de
                  // alto, y al llegar los datos la tira aparecía de golpe y
                  // empujaba todo lo de abajo. Ahora deja la silueta de las
                  // tarjetas que vienen, con las medidas reales, así nada
                  // salta de lugar.
                  if (_loading)
                    const AuraSkeletonCarrusel(
                      alto: altoCarruselDestacados,
                      anchoTarjeta: 166,
                      altoFoto: 92,
                    )
                  else if (_estudiosFiltrados.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.search_off_rounded,
                            size: 44,
                            color: Color(0xFFB2A89F),
                          ),
                          const SizedBox(height: AuraEspacio.m),
                          const Text(
                            'No encontramos resultados',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: AuraTipo.titulo,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AuraEspacio.s),
                          const Text(
                            'Probá con otro término o categoría.',
                            style: TextStyle(
                              color: AppColors.textoSuave,
                              fontSize: AuraTipo.cuerpo,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AuraEspacio.l),
                          TextButton.icon(
                            onPressed: () => setState(() {
                              _searchCtrl.clear();
                              _categoriaSeleccionada = 'Todos';
                              _tipoFiltro = 'todo';
                            }),
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Limpiar filtros'),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    // La tira se oculta si ningún estudio del filtro tiene
                    // clases próximas: mejor sin tira que destacando vacíos.
                    if (destacados.isNotEmpty) SizedBox(
                      height: altoCarruselDestacados,
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
                    // EXPERIENCIAS próximas. Sale del feed YA filtrado, así que
                    // respeta chip/búsqueda/día/horario/créditos sin código extra
                    // y desaparece sola con el filtro Tipo = Clases. Reutiliza la
                    // card del feed (misma identidad visual). Inicio no se toca.
                    if (experienciasDestacadas(lista).isNotEmpty) ...[
                      const TituloSeccion(
                        'EXPERIENCIAS',
                        margenLateral: false,
                      ),
                      SizedBox(
                        // El mismo alto que la tarjeta angosta que va adentro.
                        height: altoCardBuscador(0),
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: experienciasDestacadas(lista).length,
                          itemBuilder: (context, index) {
                            final exp = experienciasDestacadas(lista)[index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: SizedBox(
                                width: 320,
                                child: _ResultCard(
                                  clase: exp,
                                  accentColor: AppColors.beigeCard,
                                  fotoCompacta: true,
                                  onTap: () =>
                                      context.push('/clase/${exp['id']}'),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const TituloSeccion(
                      'TODOS LOS RESULTADOS',
                      margenLateral: false,
                    ),
                    if (lista.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No hay clases disponibles para esta búsqueda.',
                          style: TextStyle(color: AppColors.textoSuave),
                        ),
                      )
                    else ...[
                      // Grilla de 1 o 2 columnas. Antes era una sola columna
                      // a cualquier ancho: es la que estiraba la tarjeta de
                      // lado a lado en desktop. Las tarjetas del buscador
                      // tienen alto fijo, así que una Row basta y las filas
                      // quedan parejas solas.
                      _GrillaResultados(
                        clases: lista,
                        onTap: (clase) => context.push('/clase/${clase['id']}'),
                      ),
                      if (_hasMoreClases || _loadingMore)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 4),
                          child: Center(
                            child: _loadingMore
                                // La silueta de la próxima tanda, con el alto
                                // real de la tarjeta del buscador: el spinner
                                // ocupaba 24 px y la lista pegaba un salto al
                                // llegar los datos.
                                ? LayoutBuilder(
                                    builder: (context, c) {
                                      // Las MISMAS medidas que la grilla, para
                                      // que la silueta ocupe exactamente lo
                                      // que va a ocupar la tarjeta.
                                      final cols = columnasBuscador(c.maxWidth);
                                      final ancho = anchoCelda(
                                        c.maxWidth,
                                        cols,
                                      );
                                      return AuraSkeleton(
                                        height: altoCardBuscador(ancho),
                                        borderRadius: BorderRadius.circular(
                                          AuraRadio.tarjeta,
                                        ),
                                      );
                                    },
                                  )
                                : TextButton.icon(
                                    onPressed: _cargarMasClases,
                                    icon: const Icon(
                                      Icons.expand_more_rounded,
                                      size: 18,
                                    ),
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
        borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
          child: Ink(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
              border: Border.all(color: AppColors.warmBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AuraRadio.tarjeta),
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
                                // Una sola: el badge va SOBRE la foto y con
                                // varias categorías tapaba la imagen.
                                text: estudio.categoriaPrincipal.toUpperCase(),
                                dark: true,
                              ),
                              const Spacer(),
                              if (showBadge)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(AuraRadio.pastilla),
                                  ),
                                  child: const Text(
                                    'Tu estudio',
                                    style: TextStyle(
                                      color: AppColors.white,
                                      fontSize: AuraTipo.etiqueta,
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
                // La tarjeta tiene ALTO FIJO. Sin `Flexible`, un nombre de
                // dos renglones ("Ambra Espacio Holístico") se comía el lugar
                // y la dirección quedaba apretada o cortada. Con esto el
                // nombre cede: usa hasta 2 renglones si sobra lugar y 1 con
                // puntos suspensivos si no, y barrio y dirección SIEMPRE
                // entran (4/9/2026).
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Text(
                      estudio.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.black,
                        fontSize: AuraTipo.cuerpo,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Text(
                    estudio.barrio ?? 'Buenos Aires',
                    style: const TextStyle(
                      color: Color(0xFFAAA19A),
                      fontSize: AuraTipo.secundario,
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
                      fontSize: AuraTipo.etiqueta,
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

/// Fondo de la card de EXPERIENCIA en Explorar: un crema apenas más cálido
/// que el fondo de la pantalla (#F7F5F2), elegido el 2/9 entre tres
/// candidatos. Las cards de clase quedan blancas, así que la experiencia se
/// reconoce de reojo sin gritar, y el crema deja respirar al naranja del
/// badge (#E8763A). Un intento anterior (#F0E6DA) se descartó por oscuro.
/// Sólo Explorar: la card de Inicio es otra y no se toca.
const _fondoExperiencia = Color(0xFFFDF7F0);
const _bordeExperiencia = Color(0xFFEFE4D8);

/// Los resultados de Explorar en 1 o 2 columnas según el ancho.
class _GrillaResultados extends StatelessWidget {
  final List<Map<String, dynamic>> clases;
  final void Function(Map<String, dynamic>) onTap;

  const _GrillaResultados({required this.clases, required this.onTap});

  Widget _tarjeta(int indice) => _ResultCard(
    clase: clases[indice],
    // El color de acento alterna por posición: se calcula sobre el índice
    // real y no sobre el de la fila, para que siga alternando en dos
    // columnas igual que alternaba en una.
    accentColor: indice.isEven ? AppColors.beigeCard : AppColors.blueCard,
    onTap: () => onTap(clases[indice]),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, restricciones) {
        final columnas = columnasBuscador(restricciones.maxWidth);
        if (columnas <= 1) {
          return Column(
            children: [
              for (var i = 0; i < clases.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _tarjeta(i),
                ),
            ],
          );
        }
        final filas = (clases.length + columnas - 1) ~/ columnas;
        return Column(
          children: [
            for (var f = 0; f < filas; f++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    for (var c = 0; c < columnas; c++) ...[
                      if (c > 0) const SizedBox(width: gapGrilla),
                      // El hueco vacío de la última fila mantiene el ancho de
                      // las columnas: sin él, una sola tarjeta al final se
                      // estiraría al doble.
                      Expanded(
                        child: f * columnas + c < clases.length
                            ? _tarjeta(f * columnas + c)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ResultCard extends StatelessWidget {
  final Map<String, dynamic> clase;
  final Color accentColor;
  final VoidCallback onTap;

  /// El carrusel de experiencias mide 320 fijos en CUALQUIER pantalla, así que
  /// cae en la rama angosta también en desktop. Con esto conserva la foto de
  /// 96 px y el ensanche del 3/9 queda sólo en el teléfono, como se pidió.
  final bool fotoCompacta;

  const _ResultCard({
    required this.clase,
    required this.accentColor,
    required this.onTap,
    this.fotoCompacta = false,
  });

  @override
  Widget build(BuildContext context) {
    final estudio = clase['estudios'] as Map<String, dynamic>?;
    final categoria = estudio == null
        ? ''
        : Estudio.parseCategorias(estudio).take(2).join(' · ').toUpperCase();
    final barrio = (estudio?['barrio'] ?? '').toString().toUpperCase();
    final imageUrl = (clase['imagen_url'] ?? estudio?['foto_url'])?.toString();
    final tipoPrecio = clase['tipo_precio']?.toString();
    final esWorkshop = clase['tipo']?.toString() == 'workshop';
    final creditos = (clase['creditos'] as num?)?.toInt();
    // "PRECIO REDUCIDO" tiene que ser VERDAD, no el nombre de la franja.
    // Antes salía con tipo_precio 'normal' o 'valle' y eso lo ponía en 823 de
    // las 997 clases futuras (83%) — incluso en los tres estudios que cobran
    // un precio único, donde no hay nada reducido, y en la franja 'normal',
    // que en promedio es la MÁS cara (15,2 cr contra 14,3 de 'pico').
    // La regla honesta: esta clase cuesta menos que el techo de SU estudio, y
    // ese estudio de verdad tiene un rango. Se compara contra creditos_max del
    // estudio (no contra las clases cargadas) para que el badge no cambie
    // según qué página de la lista se haya traído. Medido el 26/8: baja a 371
    // de 997 y las tres de precio único dejan de mostrarlo.
    final crMinEstudio = (estudio?['creditos_min'] as num?)?.toInt();
    final crMaxEstudio = (estudio?['creditos_max'] as num?)?.toInt();
    // Un SERVICIO de precio fijo no entra en el juego de franjas: su precio
    // es único por definición. Sin esta exclusión, un sauna de 14 en un
    // estudio con techo 18 salía "PRECIO REDUCIDO" — mintiendo un descuento
    // donde no hay nada reducido. (Ya estaba anotado en el relevamiento de
    // servicios; también quedan afuera de "⚡ POPULAR" por la misma razón.)
    final esServicio = tipoPrecio == 'servicio';
    final esPrecioReducido =
        !esServicio &&
        creditos != null &&
        crMinEstudio != null &&
        crMaxEstudio != null &&
        crMaxEstudio > crMinEstudio &&
        creditos < crMaxEstudio;
    final organizadores = (clase['organizadores'] as List?) ?? const [];

    // La medida de la foto se decide por el ancho de ESTA tarjeta, no por el
    // de la pantalla: una tarjeta ancha (desktop, o una sola columna en una
    // ventana grande) recibe la foto 3:2 y una angosta (teléfono, carrusel de
    // experiencias) se queda con los 96 px de hoy, donde 186 se comerían más
    // de la mitad del renglón y el texto no entraría.
    return LayoutBuilder(
      builder: (context, restricciones) {
        final anchoCard = restricciones.maxWidth;
        final altoCard = altoCardBuscador(anchoCard);
        final anchoFoto = anchoFotoBuscador(anchoCard, compacta: fotoCompacta);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
            child: Ink(
              height: altoCard,
              // La card de EXPERIENCIA se distingue por el fondo, no solo por el
              // badge (pedido del 1/9): un beige calido apenas mas oscuro que el
              // fondo de la pantalla (0xFFF7F5F2), para que la clase (blanca)
              // y la experiencia convivan sin gritar. Solo en Explorar; la card
              // de Inicio es otra y no se toca.
              decoration: BoxDecoration(
                color: esWorkshop ? _fondoExperiencia : AppColors.white,
                borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
                border: Border.all(
                  color: esWorkshop ? _bordeExperiencia : AppColors.warmBorder,
                ),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(AuraRadio.tarjeta),
                    ),
                    child: SizedBox(
                      width: anchoFoto,
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
                                  [
                                    categoria,
                                    barrio,
                                  ].where((e) => e.isNotEmpty).join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    // Daba 1,5:1: no se leía. Ver AppColors.
                                    color: AppColors.textoSuave,
                                    fontSize: AuraTipo.etiqueta,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (esWorkshop)
                                const _PriceBadge(
                                  text: 'EXPERIENCIA',
                                  color: AppColors.primary,
                                )
                              else if (esServicio)
                                const _PriceBadge(
                                  text: 'PRECIO ÚNICO',
                                  color: Color(0xFF4E6F52),
                                )
                              else if (tipoPrecio == 'pico')
                                const _PriceBadge(
                                  text: '⚡ POPULAR',
                                  color: Color(0xFFE8763A),
                                )
                              else if (esPrecioReducido)
                                const _PriceBadge(
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
                              fontSize: AuraTipo.titulo,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (esWorkshop && organizadores.isNotEmpty)
                            OrganizadoresLinks(organizadores: organizadores)
                          else
                            Text(
                              estudio?['direccion']?.toString() ??
                                  'Malabia 1510',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textoSecundario,
                                fontSize: AuraTipo.secundario,
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
                                    color: AppColors.textoSuave,
                                    fontSize: AuraTipo.etiqueta,
                                  ),
                                ),
                              ),
                              _Pill(
                                text: creditos == 0
                                    ? 'GRATIS'
                                    : '${creditos ?? 10} cr',
                              ),
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
      },
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
      dia =
          toBeginningOfSentenceCase(DateFormat('EEEE', 'es').format(date)) ??
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

  const _ExploreClassImage({required this.imageUrl, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    // 400 px de descarga para un hueco de 186: nítida en retina y liviana.
    return FotoRed(url: imageUrl, ancho: 400, fallback: _fallback());
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
        child: Icon(Icons.image, color: AppColors.grey, size: 28),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FotoRed(url: url, ancho: 400, fallback: _placeholder());
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
        borderRadius: BorderRadius.circular(AuraRadio.chip),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: AuraTipo.etiqueta,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final bool dark;

  const _Pill({required this.text, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF5A534D) : const Color(0xFFFFF1E8),
        borderRadius: BorderRadius.circular(AuraRadio.pastilla),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: dark ? AppColors.white : AppColors.primary,
          fontSize: AuraTipo.etiqueta,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// SOLO PARA TESTS: expone la tarjeta de resultados de Explorar para poder
/// medirla en un widget test sin levantar la pantalla entera (que necesita
/// Supabase y el router). Mismo criterio que `debugHorariosPorDiaEditor`.
@visibleForTesting
Widget debugResultCard({
  required Map<String, dynamic> clase,
  bool fotoCompacta = false,
}) => _ResultCard(
  clase: clase,
  accentColor: AppColors.beigeCard,
  fotoCompacta: fotoCompacta,
  onTap: () {},
);

/// SOLO PARA TESTS: expone la tarjeta de "DESTACADOS HOY" con su alto real
/// (el del carrusel) para medir si el texto desborda. Mismo criterio que
/// `debugResultCard` y `debugPaywallSheet`.
@visibleForTesting
Widget debugFeaturedExploreCard({
  required Estudio estudio,
  bool showBadge = false,
}) => SizedBox(
  height: altoCarruselDestacados,
  child: _FeaturedExploreCard(
    estudio: estudio,
    accentColor: AppColors.beigeCard,
    showBadge: showBadge,
    onTap: () {},
  ),
);
