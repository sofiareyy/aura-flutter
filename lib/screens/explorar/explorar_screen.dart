import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
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
  bool _categoriaInicialAplicada = false;
  bool _showAllDestacados = false;
  int? _estudioAsociadoId;

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
      _clasesService.getProximasClases(limit: 20),
      _estudiosService.getCategorias(),
    ]);

    if (!mounted) return;
    setState(() {
      _estudios = results[0] as List<Estudio>;
      _clases = results[1] as List<Map<String, dynamic>>;
      _categorias = results[2] as List<String>;
      if (!_categorias.contains(_categoriaSeleccionada)) {
        _categoriaSeleccionada = 'Todos';
      }
      _loading = false;
    });
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
    return _clases.where((clase) {
      final estudio = clase['estudios'] as Map<String, dynamic>?;
      return filteredIds.isEmpty || filteredIds.contains(estudio?['id']);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final destacados = _showAllDestacados ? _estudiosFiltrados : _estudiosFiltrados.take(2).toList();
    final lista = _clasesConEstudio.take(6).toList();

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
              Container(
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
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No encontramos resultados.',
                    style: TextStyle(color: Color(0xFF8C847C)),
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
                else
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
                Container(
                  height: 92,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        accentColor.withOpacity(0.95),
                        accentColor.withOpacity(0.7),
                        accentColor.withOpacity(0.35),
                      ],
                    ),
                  ),
                  child: Padding(
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
                      Text(
                        [categoria, barrio]
                            .where((e) => e.isNotEmpty)
                            .join(' Â· '),
                        style: const TextStyle(
                          color: Color(0xFFD0C6BD),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
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
                                  : 'Hoy Â· 20:30 hs',
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
    if (date == null) return 'Hoy Â· 20:30 hs';
    final hour = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} hs';
    return 'Hoy Â· $hour';
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



