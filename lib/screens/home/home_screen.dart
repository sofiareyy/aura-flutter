import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../models/estudio.dart';
import '../../providers/app_provider.dart';
import '../../services/clases_service.dart';
import '../../services/estudios_service.dart';
import '../../services/location_service.dart';
import '../../services/notificaciones_service.dart';
import '../../services/studio_geo_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _clasesService = ClasesService();
  final _estudiosService = EstudiosService();
  final _locationService = LocationService();
  final _studioGeoService = StudioGeoService();

  List<Map<String, dynamic>> _proximasClases = [];
  List<Estudio> _estudios = [];
  List<String> _categorias = const ['Todos'];
  bool _loading = true;
  bool _requestingLocation = false;
  bool _bannerDismissed = false;
  String _categoriaSeleccionada = 'Todos';
  AuraLocationState _locationState =
      const AuraLocationState(status: AuraLocationStatus.unknown);

  void _abrirMapa([String? categoria]) {
    final categoriaActiva = categoria ?? _categoriaSeleccionada;
    final query = <String, String>{};
    if (categoriaActiva.isNotEmpty && categoriaActiva != 'Todos') {
      query['categoria'] = categoriaActiva;
    }
    final uri = Uri(
      path: '/mapa',
      queryParameters: query.isEmpty ? null : query,
    );
    context.push(uri.toString());
  }

  Future<void> _pedirUbicacion() async {
    if (_requestingLocation) return;
    setState(() => _requestingLocation = true);
    try {
      final state = await _locationService.getCurrentLocation();
      if (!mounted) return;
      setState(() => _locationState = state);
    } finally {
      if (mounted) setState(() => _requestingLocation = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _cargar();
    _checkBannerDismissed();
  }

  Future<void> _checkBannerDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissedDate = prefs.getString('credits_expiry_banner_dismissed');
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (dismissedDate == today && mounted) {
      setState(() => _bannerDismissed = true);
    }
  }

  Future<void> _dismissBanner() async {
    setState(() => _bannerDismissed = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'credits_expiry_banner_dismissed',
      DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
  }

  Future<void> _cargar() async {
    if (mounted) setState(() => _loading = true);

    final provider = context.read<AppProvider>();

    try {
      await provider.cargarUsuario();
      // Schedule credits expiry notifications after user is loaded
      final vencimiento = provider.usuario?.creditosVencimiento;
      if (vencimiento != null) {
        NotificacionesService.instance
            .scheduleCreditsExpiryReminder(expiresAt: vencimiento)
            .ignore();
      }
      final results = await Future.wait([
        _clasesService.getProximasClases(limit: 5),
        _estudiosService.getCategorias(),
        _estudiosService.getEstudios(),
      ]);
      final clases = results[0] as List<Map<String, dynamic>>;
      final categorias = results[1] as List<String>;
      final estudios = results[2] as List<Estudio>;
      clases.sort((a, b) {
        final fechaA = DateTime.tryParse(a['fecha']?.toString() ?? '');
        final fechaB = DateTime.tryParse(b['fecha']?.toString() ?? '');
        if (fechaA == null && fechaB == null) return 0;
        if (fechaA == null) return 1;
        if (fechaB == null) return -1;
        return fechaA.compareTo(fechaB);
      });
      if (mounted) {
        setState(() {
          _proximasClases = clases;
          _estudios = estudios;
          _categorias = categorias;
          if (!_categorias.contains(_categoriaSeleccionada)) {
            _categoriaSeleccionada = 'Todos';
          }
        });
      }
    } catch (_) {
      // Dejamos UI vacia si falla la carga.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _saludo() {
    final hora = DateTime.now().hour;
    if (hora < 12) return 'Buenos días';
    if (hora < 18) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    final finSemana = ahora.add(const Duration(days: 7));
    final clasesFiltradas = _categoriaSeleccionada == 'Todos'
        ? _proximasClases
        : _proximasClases.where((clase) {
            final estudio = clase['estudios'] as Map<String, dynamic>?;
            final categoria = (estudio?['categoria'] ?? '').toString();
            return categoria.toLowerCase() ==
                _categoriaSeleccionada.toLowerCase();
          }).toList();
    final clasesEstaSemana = clasesFiltradas.where((clase) {
      final fecha = DateTime.tryParse(clase['fecha']?.toString() ?? '');
      if (fecha == null) return false;
      return !fecha.isBefore(ahora) && !fecha.isAfter(finSemana);
    }).toList();
    final estudiosFiltrados = _categoriaSeleccionada == 'Todos'
        ? _estudios
        : _estudios.where((estudio) {
            return estudio.categoria.toLowerCase() ==
                _categoriaSeleccionada.toLowerCase();
          }).toList();
    final estudiosCerca = _studioGeoService
        .sortByDistance(estudiosFiltrados, _locationState.position)
        .take(6)
        .toList();
    final hayDistanciaReal =
        estudiosCerca.any((result) => result.distanceKm != null);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _cargar,
        child: Consumer<AppProvider>(
          builder: (context, provider, _) {
            final usuario = provider.usuario;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _saludo(),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: AppColors.grey,
                                        fontSize: 14,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                RichText(
                                  text: TextSpan(
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                          color: AppColors.black,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                    children: [
                                      TextSpan(
                                        text: usuario?.nombre.split(' ').first ??
                                            'Bienvenida',
                                      ),
                                      const TextSpan(text: ' ✦'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () => context.go('/perfil'),
                            child: Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _initial(usuario?.nombre),
                              style: const TextStyle(
                                color: AppColors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: _PlanCard(usuario: usuario),
                  ),
                ),
                // ── Credits expiry banner ─────────────────────────────
                if (!_bannerDismissed && usuario != null) ...[
                  SliverToBoxAdapter(
                    child: Builder(
                      builder: (ctx) {
                        final venc = usuario.creditosVencimiento;
                        if (venc == null) return const SizedBox.shrink();
                        final dias = venc.difference(DateTime.now()).inDays;
                        if (dias < 0 || dias > 7) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                          child: _CreditosExpiryBanner(
                            dias: dias,
                            creditos: usuario.creditos,
                            onDismiss: _dismissBanner,
                            onExplorar: () => context.push('/explorar'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: _categorias
                            .map(
                              (categoria) => Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: _CategoryChip(
                                  label: categoria,
                                  active: _categoriaSeleccionada == categoria,
                                  onTap: () => setState(() {
                                    _categoriaSeleccionada = categoria;
                                  }),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: _MapEntryCard(
                      categoria: _categoriaSeleccionada,
                      onTap: () => _abrirMapa(),
                    ),
                  ),
                ),
                // ── Card estudio asociado (alumno directo) ──────────
                if (provider.estudioAsociado != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: _EstudioAsociadoCard(
                        estudio: provider.estudioAsociado!,
                        onTap: () => context.push(
                            '/estudio/${provider.estudioAsociado!.id}'),
                        onVerClases: () => context.push(
                            '/estudio/${provider.estudioAsociado!.id}'),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'CERCA TUYO',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        GestureDetector(
                          onTap: () => context.push('/explorar'),
                          child: const Text(
                            'Ver todo',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                    child: _locationState.granted
                        ? Column(
                            children: [
                              _NearbyStatusCard(
                                locationState: _locationState,
                                hasRealDistance: hayDistanciaReal,
                                requesting: _requestingLocation,
                                onPrimaryTap: _pedirUbicacion,
                                onSecondaryTap: () => _abrirMapa(),
                              ),
                              const SizedBox(height: 14),
                              if (estudiosCerca.isEmpty)
                                const _EmptyNearbyCard()
                              else
                                SizedBox(
                                  height: 204,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: estudiosCerca.length,
                                    itemBuilder: (context, index) {
                                      final nearby = estudiosCerca[index];
                                      return SizedBox(
                                        width: 220,
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.only(right: 14),
                                          child: _NearbyStudyCard(
                                            estudio: nearby.estudio,
                                            distanceLabel: _studioGeoService
                                                .formatDistance(
                                                    nearby.distanceKm),
                                            onTap: () => context.push(
                                              '/estudio/${nearby.estudio.id}',
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          )
                        : _LocationPromptCard(
                            locationState: _locationState,
                            requesting: _requestingLocation,
                            onPrimaryTap: _pedirUbicacion,
                            onSecondaryTap: () => _abrirMapa(),
                          ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'CLASES ESTA SEMANA',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        GestureDetector(
                          onTap: () => context.push('/explorar'),
                          child: const Text(
                            'Explorar',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_loading)
                  const SliverToBoxAdapter(child: SizedBox.shrink())
                else if (clasesEstaSemana.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Text(
                        'No encontramos clases para esta semana en esta categoría.',
                        style: TextStyle(color: AppColors.grey, height: 1.5),
                      ),
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 270,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: clasesEstaSemana.length,
                        itemBuilder: (context, index) {
                          final clase = clasesEstaSemana[index];
                          return SizedBox(
                            width: 320,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: _HomeNearbyClassCard(
                                clase: clase,
                                onTap: () => context.push('/clase/${clase['id']}'),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ESTUDIOS',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        GestureDetector(
                          onTap: () => context.push('/explorar'),
                          child: const Text(
                            'Ver todo',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_loading)
                  const SliverToBoxAdapter(child: SizedBox.shrink())
                else if (estudiosFiltrados.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Text(
                        'No encontramos estudios para esta categoría.',
                        style: TextStyle(color: AppColors.grey, height: 1.5),
                      ),
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 252,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: estudiosFiltrados.length,
                        itemBuilder: (context, index) {
                          final estudio = estudiosFiltrados[index];
                          return SizedBox(
                            width: 220,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: _HomeStudyCard(
                                estudio: estudio,
                                onTap: () => context.push('/estudio/${estudio.id}'),
                              ),
                            ),
                          );
                        },
                      ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 26, 20, 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TODAS LAS EXPERIENCIAS',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        GestureDetector(
                          onTap: () => context.push('/explorar'),
                          child: const Text(
                            'Ver todo',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_loading)
                  const SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  )
                else if (clasesFiltradas.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      child: Center(
                        child: Text(
                          'No hay clases para esta categoría cerca tuyo.\nProbá con otra opción.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.grey, height: 1.6),
                        ),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final clase = clasesFiltradas[index];
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: _HomeNearbyClassCard(
                            clase: clase,
                            onTap: () => context.push('/clase/${clase['id']}'),
                          ),
                        );
                      },
                      childCount: clasesFiltradas.length,
                    ),
                  ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: 28),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _initial(String? nombre) {
    if (nombre == null) return 'A';
    final limpio = nombre.trim();
    if (limpio.isEmpty) return 'A';
    return limpio.substring(0, 1).toUpperCase();
  }
}

// ─── Credits expiry banner ────────────────────────────────────────────────────

class _CreditosExpiryBanner extends StatelessWidget {
  final int dias;
  final int creditos;
  final VoidCallback onDismiss;
  final VoidCallback onExplorar;

  const _CreditosExpiryBanner({
    required this.dias,
    required this.creditos,
    required this.onDismiss,
    required this.onExplorar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF0E8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.access_time_rounded,
            color: Color(0xFFE8763A),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dias == 0
                      ? 'Tus créditos vencen hoy'
                      : 'Tus créditos vencen en $dias ${dias == 1 ? 'día' : 'días'}',
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tenés $creditos crédito${creditos != 1 ? 's' : ''} disponibles — reservá algo',
                  style: const TextStyle(
                    color: Color(0xFF8F877F),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onExplorar,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE8763A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Explorar'),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDismiss,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                color: Color(0xFF8F877F),
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Plan card ────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final dynamic usuario;

  const _PlanCard({this.usuario});

  @override
  Widget build(BuildContext context) {
    final vencimiento = usuario?.creditosVencimiento as DateTime?;
    final planRaw = (usuario?.plan ?? '').toString().trim();
    final plan = planRaw.isEmpty ? 'Sin plan' : planRaw;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${usuario?.creditos ?? 0}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 50,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'créditos disponibles',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vencimiento != null
                          ? 'Vencen el ${DateFormat('d \'de\' MMMM', 'es').format(vencimiento)}'
                          : plan == 'Sin plan'
                              ? 'Elegí un plan o comprá créditos'
                              : 'Tus créditos se acreditaron correctamente',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(
                  plan,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => context.push('/comprar-creditos'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    '+ Comprar más',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.push('/cambiar-plan'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Cambiar plan',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _CategoryChip({
    required this.label,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.black : AppColors.white,
          borderRadius: BorderRadius.circular(9999),
          border: active
              ? null
              : Border.all(color: AppColors.grey.withValues(alpha: 0.18)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.white : AppColors.grey,
            fontSize: 15,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _HomeNearbyClassCard extends StatelessWidget {
  final Map<String, dynamic> clase;
  final VoidCallback onTap;

  const _HomeNearbyClassCard({
    required this.clase,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final estudio = clase['estudios'] as Map<String, dynamic>?;
    final fecha = clase['fecha'] != null
        ? DateTime.tryParse(clase['fecha'].toString())
        : null;
    final categoria = (estudio?['categoria'] ?? '').toString();
    final imageUrl = (clase['imagen_url'] ?? estudio?['foto_url'])?.toString();
    final lugaresDisponibles =
        (clase['lugares_disponibles'] as num?) ?? 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.grey.withValues(alpha: 0.14)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: SizedBox(
                  height: 132,
                  width: double.infinity,
                  child: _HomeClassImage(imageUrl: imageUrl),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (categoria.isNotEmpty)
                            Text(
                              categoria.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          if (categoria.isNotEmpty) const SizedBox(height: 4),
                          Text(
                            (clase['nombre'] ?? 'Clase').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.black,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${estudio?['nombre'] ?? 'Estudio'} · ${lugaresDisponibles.toInt()} lugares',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.grey,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                          if (fecha != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  size: 14,
                                  color: AppColors.grey,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    '${DateFormat('EEE d MMM', 'es').format(fecha)} · ${DateFormat('HH:mm').format(fecha)} hs',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.grey,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Text(
                        '${clase['creditos'] ?? 0} cr',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
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
    );
  }
}

class _HomeClassImage extends StatelessWidget {
  final String? imageUrl;

  const _HomeClassImage({this.imageUrl});

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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFD6B17D), Color(0xFFEEDFCB)],
        ),
      ),
    );
  }
}

class _HomeStudyCard extends StatelessWidget {
  final Estudio estudio;
  final VoidCallback onTap;

  const _HomeStudyCard({
    required this.estudio,
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
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.grey.withValues(alpha: 0.14)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: SizedBox(
                  height: 100,
                  width: double.infinity,
                  child: _HomeClassImage(imageUrl: estudio.fotoUrl),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (estudio.categoria.isNotEmpty)
                        Text(
                          estudio.categoria.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      if (estudio.categoria.isNotEmpty) const SizedBox(height: 4),
                      Text(
                        estudio.nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.black,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 15,
                            color: Color(0xFFF5A623),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            estudio.rating != null && estudio.rating! > 0
                                ? estudio.rating!.toStringAsFixed(1)
                                : 'Nuevo',
                            style: const TextStyle(
                              color: AppColors.black,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        estudio.barrio?.isNotEmpty == true
                            ? estudio.barrio!
                            : 'Estudio en Aura',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.grey,
                          fontSize: 13,
                        ),
                      ),
                      if ((estudio.direccion ?? '').isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          estudio.direccion!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFB2A89F),
                            fontSize: 12,
                          ),
                        ),
                      ],
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
}

class _MapEntryCard extends StatelessWidget {
  final String categoria;
  final VoidCallback onTap;

  const _MapEntryCard({
    required this.categoria,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = categoria == 'Todos'
        ? 'Buscá estudios por zona y filtrá mejor desde el mapa.'
        : 'Abrí el mapa para ver estudios de $categoria cerca tuyo.';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4EC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF0D9C9)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.map_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Buscar estudios en mapa',
                      style: TextStyle(
                        color: AppColors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.grey,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
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

class _NearbyStatusCard extends StatelessWidget {
  final AuraLocationState locationState;
  final bool hasRealDistance;
  final bool requesting;
  final VoidCallback onPrimaryTap;
  final VoidCallback onSecondaryTap;

  const _NearbyStatusCard({
    required this.locationState,
    required this.hasRealDistance,
    required this.requesting,
    required this.onPrimaryTap,
    required this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4EC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0D9C9)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.near_me_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Te mostramos opciones cerca tuyo',
                  style: TextStyle(
                    color: AppColors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Usamos tu ubicación actual para priorizar estudios cercanos y también podés explorar todo desde el mapa.',
                  style: TextStyle(
                    color: AppColors.grey,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            children: [
              TextButton(
                onPressed: requesting ? null : onPrimaryTap,
                child: Text(requesting ? 'Actualizando...' : 'Actualizar'),
              ),
              TextButton(
                onPressed: onSecondaryTap,
                child: const Text('Mapa'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyNearbyCard extends StatelessWidget {
  const _EmptyNearbyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.warmBorder),
      ),
      child: const Text(
        'Todavía no pudimos estimar estudios cercanos con esta categoría. Probá explorar todo desde el mapa.',
        style: TextStyle(
          color: AppColors.grey,
          fontSize: 13,
          height: 1.45,
        ),
      ),
    );
  }
}

class _NearbyStudyCard extends StatelessWidget {
  final Estudio estudio;
  final String distanceLabel;
  final VoidCallback onTap;

  const _NearbyStudyCard({
    required this.estudio,
    required this.distanceLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ratingLabel = estudio.rating != null && estudio.rating! > 0
        ? estudio.rating!.toStringAsFixed(1)
        : 'Nuevo';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.grey.withValues(alpha: 0.14)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: SizedBox(
                  height: 96,
                  width: double.infinity,
                  child: _HomeClassImage(imageUrl: estudio.fotoUrl),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        distanceLabel,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        estudio.nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.black,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 15,
                            color: Color(0xFFF5A623),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            ratingLabel,
                            style: const TextStyle(
                              color: AppColors.black,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        estudio.barrio?.isNotEmpty == true
                            ? estudio.barrio!
                            : estudio.categoria,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationPromptCard extends StatelessWidget {
  final AuraLocationState locationState;
  final bool requesting;
  final VoidCallback onPrimaryTap;
  final VoidCallback onSecondaryTap;

  const _LocationPromptCard({
    required this.locationState,
    required this.requesting,
    required this.onPrimaryTap,
    required this.onSecondaryTap,
  });

  String get _title {
    switch (locationState.status) {
      case AuraLocationStatus.granted:
        return 'Ubicación activada';
      case AuraLocationStatus.deniedForever:
        return 'Ubicación bloqueada';
      case AuraLocationStatus.denied:
        return 'Activá tu ubicación';
      case AuraLocationStatus.unavailable:
        return 'Ubicación no disponible';
      case AuraLocationStatus.unknown:
        return 'Activá tu ubicación';
    }
  }

  String get _subtitle {
    switch (locationState.status) {
      case AuraLocationStatus.granted:
        return 'Ya podemos usar tu ubicación para priorizar opciones cerca tuyo. Cuando sumemos coordenadas a los estudios, esta sección va a quedar totalmente personalizada.';
      case AuraLocationStatus.deniedForever:
        return 'Para mostrarte estudios cerca tuyo, necesitás habilitar la ubicación desde la configuración del dispositivo o navegador.';
      case AuraLocationStatus.denied:
        return 'Si aceptás el permiso, vamos a priorizar estudios y experiencias cerca tuyo.';
      case AuraLocationStatus.unavailable:
        return 'No pudimos acceder a la ubicación. Mientras tanto, te mostramos opciones destacadas.';
      case AuraLocationStatus.unknown:
        return 'Así podemos priorizar estudios y experiencias realmente cerca tuyo. Mientras tanto, te mostramos opciones destacadas.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.warmBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4EC),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.location_on_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: TextStyle(
                    color: AppColors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _subtitle,
                  style: const TextStyle(
                    color: AppColors.grey,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: requesting ? null : onPrimaryTap,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                      ),
                      child: Text(
                        requesting ? 'Pidiendo permiso...' : 'Permitir ubicación',
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: onSecondaryTap,
                      child: const Text('Ver mapa'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card estudio asociado ─────────────────────────────────────────────────────

class _EstudioAsociadoCard extends StatelessWidget {
  final Estudio estudio;
  final VoidCallback onTap;
  final VoidCallback onVerClases;

  const _EstudioAsociadoCard({
    required this.estudio,
    required this.onTap,
    required this.onVerClases,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppColors.black,
          borderRadius: BorderRadius.circular(24),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Foto del estudio con overlay oscuro
            if (estudio.fotoUrl != null && estudio.fotoUrl!.isNotEmpty)
              Opacity(
                opacity: 0.35,
                child: CachedNetworkImage(
                  imageUrl: estudio.fotoUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),

            // Contenido
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge naranja
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Tu estudio',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Nombre del estudio
                  Text(
                    estudio.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (estudio.barrio != null &&
                      estudio.barrio!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      estudio.barrio!,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const Spacer(),
                  // Botón "Ver clases"
                  GestureDetector(
                    onTap: onVerClases,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F5F2), // crema
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Ver clases',
                        style: TextStyle(
                          color: AppColors.black,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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

