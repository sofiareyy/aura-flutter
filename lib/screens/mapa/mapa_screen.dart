import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import '../../models/estudio.dart';
import '../../services/estudios_service.dart';
import '../../services/location_service.dart';
import '../../services/studio_geo_service.dart';

class MapaScreen extends StatefulWidget {
  const MapaScreen({super.key});

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

class _MapaScreenState extends State<MapaScreen> {
  final _service = EstudiosService();
  final _locationService = LocationService();
  final _geoService = StudioGeoService();
  final _searchCtrl = TextEditingController();
  final _mapCtrl = MapController();

  List<Estudio> _estudios = [];
  bool _loading = true;
  String _categoriaSeleccionada = 'Todos';
  bool _filtrosInicialesAplicados = false;
  AuraLocationState _locationState =
      const AuraLocationState(status: AuraLocationStatus.unknown);
  NearbyStudyResult? _selectedStudy;

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
    if (_filtrosInicialesAplicados) return;
    final uri = GoRouterState.of(context).uri;
    final categoria = uri.queryParameters['categoria'];
    final query = uri.queryParameters['q'];
    if (categoria != null && categoria.isNotEmpty) {
      _categoriaSeleccionada = categoria;
    }
    if (query != null && query.isNotEmpty) {
      _searchCtrl.text = query;
    }
    _filtrosInicialesAplicados = true;
  }

  Future<void> _cargar() async {
    final studies = await _service.getEstudios();
    final location = await _locationService.getCurrentLocation();
    if (!mounted) return;
    setState(() {
      _estudios = studies;
      _locationState = location;
      _loading = false;
    });
  }

  List<NearbyStudyResult> get _results {
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = _estudios.where((estudio) {
      final matchesCategory = _categoriaSeleccionada == 'Todos' ||
          estudio.categoria.toLowerCase() ==
              _categoriaSeleccionada.toLowerCase();
      final matchesSearch = q.isEmpty ||
          estudio.nombre.toLowerCase().contains(q) ||
          (estudio.barrio?.toLowerCase().contains(q) ?? false) ||
          (estudio.direccion?.toLowerCase().contains(q) ?? false) ||
          estudio.categoria.toLowerCase().contains(q);
      return matchesCategory && matchesSearch;
    }).toList();

    return _geoService.sortByDistance(filtered, _locationState.position);
  }

  String _ratingLabel(double? rating) {
    if (rating == null || rating <= 0) return 'Nuevo';
    return '${rating.toStringAsFixed(1)} ★';
  }

  void _resetMap() {
    _searchCtrl.clear();
    setState(() {
      _categoriaSeleccionada = 'Todos';
      _selectedStudy = null;
    });
    final center =
        _geoService.centerForResults(_results, _locationState.position);
    _mapCtrl.move(center, _locationState.granted ? 12.8 : 11.7);
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final center = _geoService.centerForResults(results, _locationState.position);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _categoriaSeleccionada == 'Todos'
                                    ? 'Mapa'
                                    : 'Mapa · $_categoriaSeleccionada',
                                style: const TextStyle(
                                  color: AppColors.black,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${results.length} estudios para explorar',
                                style: const TextStyle(
                                  color: AppColors.grey,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFCF8),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE9DED3)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x12000000),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search_rounded,
                            color: Color(0xFFC4BDB6),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              decoration: const InputDecoration(
                                hintText: 'Buscar estudio o zona...',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _resetMap,
                            icon: const Icon(
                              Icons.my_location_rounded,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(30),
                            child: Stack(
                              children: [
                                FlutterMap(
                                  mapController: _mapCtrl,
                                  options: MapOptions(
                                    initialCenter: center,
                                    initialZoom:
                                        _locationState.granted ? 12.8 : 11.7,
                                    interactionOptions: const InteractionOptions(
                                      flags: InteractiveFlag.all,
                                    ),
                                    onTap: (_, __) =>
                                        setState(() => _selectedStudy = null),
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate:
                                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName: 'com.aura.app',
                                    ),
                                    if (_locationState.granted &&
                                        _locationState.position != null)
                                      MarkerLayer(
                                        markers: [
                                          Marker(
                                            point: LatLng(
                                              _locationState.position!.latitude,
                                              _locationState.position!.longitude,
                                            ),
                                            width: 30,
                                            height: 30,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF1F8CFF),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: AppColors.white,
                                                  width: 4,
                                                ),
                                                boxShadow: const [
                                                  BoxShadow(
                                                    color: Color(0x33000000),
                                                    blurRadius: 12,
                                                    offset: Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    MarkerLayer(
                                      markers: results
                                          .where((result) =>
                                              result.coordinates != null)
                                          .map(
                                            (result) => Marker(
                                              point: result.coordinates!,
                                              width: 132,
                                              height: 54,
                                              child: GestureDetector(
                                                onTap: () => setState(
                                                  () => _selectedStudy = result,
                                                ),
                                                child: _MapPillMarker(
                                                  label: _ratingLabel(
                                                    result.estudio.rating,
                                                  ),
                                                  active:
                                                      _selectedStudy
                                                          ?.estudio
                                                          .id ==
                                                      result.estudio.id,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ],
                                ),
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: IgnorePointer(
                                    child: Container(
                                      height: 56,
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Color(0x26000000),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 24,
                          right: 24,
                          bottom: 18,
                          child: _selectedStudy != null
                              ? _MapSelectedStudyCard(
                                  result: _selectedStudy!,
                                  ratingLabel:
                                      _ratingLabel(_selectedStudy!.estudio.rating),
                                  distanceLabel: _geoService
                                      .formatDistance(_selectedStudy!.distanceKm),
                                  onTap: () => context.push(
                                    '/estudio/${_selectedStudy!.estudio.id}',
                                  ),
                                )
                              : _MapHintCard(
                                  granted: _locationState.granted,
                                  onTap: () {
                                    if (results.isNotEmpty) {
                                      setState(() => _selectedStudy = results.first);
                                    }
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _MapPillMarker extends StatelessWidget {
  final String label;
  final bool active;

  const _MapPillMarker({
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.black : const Color(0xFFFFFCF8),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? AppColors.black : const Color(0xFFE7DBCE),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_rounded,
              size: 14,
              color: active ? const Color(0xFFF5A623) : AppColors.primary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: active ? AppColors.white : AppColors.black,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapHintCard extends StatelessWidget {
  final bool granted;
  final VoidCallback onTap;

  const _MapHintCard({
    required this.granted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4EC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.place_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  granted
                      ? 'Mové el mapa o tocá un rating para ver el estudio.'
                      : 'Explorá el mapa y tocá un rating para abrir un estudio.',
                  style: const TextStyle(
                    color: AppColors.black,
                    fontSize: 13,
                    height: 1.4,
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

class _MapSelectedStudyCard extends StatelessWidget {
  final NearbyStudyResult result;
  final String ratingLabel;
  final String distanceLabel;
  final VoidCallback onTap;

  const _MapSelectedStudyCard({
    required this.result,
    required this.ratingLabel,
    required this.distanceLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final estudio = result.estudio;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x18000000),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 62,
                  height: 62,
                  child: estudio.fotoUrl != null && estudio.fotoUrl!.isNotEmpty
                      ? Image.network(estudio.fotoUrl!, fit: BoxFit.cover)
                      : Container(
                          color: const Color(0xFFFFF4EC),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.storefront_rounded,
                            color: AppColors.primary,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF4EC),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            ratingLabel,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      estudio.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${estudio.barrio ?? estudio.categoria} · $distanceLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.grey,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
