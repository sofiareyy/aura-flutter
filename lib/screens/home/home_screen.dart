import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../models/estudio.dart';
import '../../providers/app_provider.dart';
import '../../services/aviso_alumnos_service.dart';
import '../../services/clases_service.dart';
import '../../services/estudios_service.dart';
import '../../services/location_service.dart';
import '../../services/notificaciones_service.dart';
import '../../services/reservas_service.dart';
import '../../services/studio_geo_service.dart';
import '../../utils/grilla_responsive.dart';
import '../../widgets/foto_red.dart';
import '../../widgets/organizadores_links.dart';
import '../../widgets/registro_muro.dart';

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

  /// Invitado del modo visita: ve el catálogo del home (clases de la semana,
  /// experiencias, estudios cerca) pero no las cards personales. Todas las
  /// cargas de datos ya cortan solas con `uid.isEmpty`.
  bool get esInvitado => Supabase.instance.client.auth.currentUser == null;

  List<Map<String, dynamic>> _proximasClases = [];
  List<Map<String, dynamic>> _experiencias = [];
  List<Map<String, dynamic>> _sugerencias = [];
  final _reservasService = ReservasService();
  // Próxima reserva del usuario dentro de las próximas 24 h (para el QR de hoy).
  Map<String, dynamic>? _proximaReserva;
  List<Estudio> _estudios = [];
  List<String> _categorias = const ['Todos'];
  final _avisoService = AvisoAlumnosService();
  bool _loading = true;
  bool _requestingLocation = false;
  bool _bannerDismissed = false;
  bool _tieneHistorialCreditos = true;
  int _unreadNotifs = 0;
  String _categoriaSeleccionada = 'Todos';
  AuraLocationState _locationState = const AuraLocationState(
    status: AuraLocationStatus.unknown,
  );

  Future<void> _pedirUbicacion() async {
    if (_requestingLocation) return;
    setState(() => _requestingLocation = true);
    try {
      final state = await _locationService.getCurrentLocation();
      if (!mounted) return;
      setState(() => _locationState = state);
      if (state.granted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('ubicacion_permitida', true);
      }
    } finally {
      if (mounted) setState(() => _requestingLocation = false);
    }
  }

  /// Si el usuario ya concedió el permiso en una sesión previa, pedimos la
  /// ubicación sin mostrar el prompt — el OS la entrega directo porque ya
  /// tiene permiso. Si el flag está en false (o ausente) dejamos que la UI
  /// muestre el _LocationPromptCard hasta que el usuario lo tape.
  Future<void> _restaurarUbicacionSiPermitida() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('ubicacion_permitida') == true) {
      await _pedirUbicacion();
    }
  }

  @override
  void initState() {
    super.initState();
    _cargar();
    _checkBannerDismissed();
    _restaurarUbicacionSiPermitida();
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

  /// Busca la reserva activa más próxima y, si cae dentro de las próximas
  /// 24 h, la deja lista para la tarjeta "Tu QR de hoy". getReservasUsuario ya
  /// devuelve solo reservas activas y futuras, ordenadas por fecha.
  Future<void> _cargarProximaReserva() async {
    try {
      final reservas = await _reservasService.getReservasUsuario();
      const argOffset = Duration(hours: -3);
      final ahora = DateTime.now().toUtc().add(argOffset);
      final limite = ahora.add(const Duration(hours: 24));
      Map<String, dynamic>? mejor;
      DateTime? mejorFecha;
      for (final r in reservas) {
        final fechaStr = (r['clases'] as Map?)?['fecha']?.toString() ?? '';
        final parsed = DateTime.tryParse(fechaStr);
        if (parsed == null) continue;
        final fecha = parsed.isUtc ? parsed.add(argOffset) : parsed;
        if (fecha.isAfter(limite)) continue; // más allá de 24 h
        if ((r['codigo_qr']?.toString() ?? '').isEmpty) continue;
        if (mejorFecha == null || fecha.isBefore(mejorFecha)) {
          mejor = r;
          mejorFecha = fecha;
        }
      }
      if (mounted) setState(() => _proximaReserva = mejor);
    } catch (_) {
      // Sin QR destacado si falla.
    }
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
      // Detectar si el usuario tiene historial de créditos (solo cuando tiene 0)
      if ((provider.usuario?.creditos ?? 0) == 0) {
        final uid = Supabase.instance.client.auth.currentUser?.id;
        if (uid != null) {
          try {
            final historial = await Supabase.instance.client
                .from('creditos_movimientos')
                // La columna es `user_id`, no `usuario_id`. Con el nombre
                // viejo esto tiraba 42703, caia en el catch de abajo (que
                // asume "tiene historial") y el usuario nuevo nunca veia el
                // estado de bienvenida en el home.
                .select('id')
                .eq('user_id', uid)
                .limit(1);
            if (mounted) {
              setState(
                () => _tieneHistorialCreditos = (historial as List).isNotEmpty,
              );
            }
          } catch (_) {
            // Si falla, asumimos que tiene historial para no mostrar el estado de nuevo usuario
          }
        }
      } else {
        if (mounted) setState(() => _tieneHistorialCreditos = true);
      }
      // Cargar notificaciones no leídas (non-blocking)
      _avisoService.getUnreadCount().then((count) {
        if (mounted) setState(() => _unreadNotifs = count);
      }).ignore();

      final results = await Future.wait([
        // Subimos el limit (era 5) para que aparezcan las clases mas
        // cercanas en el tiempo. Con limit bajo, si las primeras 5 caian
        // todas el mismo dia lejano, "esta semana" quedaba vacia. Order
        // por fecha asc se sigue manteniendo (soonest first).
        _clasesService.getProximasClases(limit: 50),
        _estudiosService.getCategorias(),
        _estudiosService.getEstudios(),
        _clasesService.getProximasExperiencias(limit: 20),
      ]);
      final clases = results[0] as List<Map<String, dynamic>>;
      final categorias = results[1] as List<String>;
      final estudios = results[2] as List<Estudio>;
      final experiencias = results[3] as List<Map<String, dynamic>>;
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
          _experiencias = experiencias;
          _estudios = estudios;
          _categorias = categorias;
          if (!_categorias.contains(_categoriaSeleccionada)) {
            _categoriaSeleccionada = 'Todos';
          }
        });
      }
      _cargarSugerencias().ignore();
      _cargarProximaReserva().ignore();
    } catch (_) {
      // Dejamos UI vacia si falla la carga.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cargarSugerencias() async {
    final provider = context.read<AppProvider>();
    final uid = provider.userId;
    if (uid.isEmpty) return;
    final sugerencias = await _clasesService.getClasesSugeridas(userId: uid);
    if (mounted) setState(() => _sugerencias = sugerencias);
  }

  Future<void> _mostrarNotificaciones() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _NotificacionesSheet(
        service: _avisoService,
        onLeidas: () {
          if (mounted) setState(() => _unreadNotifs = 0);
        },
      ),
    );
  }

  String _saludo() {
    final hora = DateTime.now().hour;
    if (hora < 12) return 'Buenos días';
    if (hora < 18) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    // Hora Argentina (UTC-3) en frame UTC, independiente del timezone del device.
    final ahora = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    final finSemana = ahora.add(const Duration(days: 7));
    final clasesFiltradas = _categoriaSeleccionada == 'Todos'
        ? _proximasClases
        : _proximasClases.where((clase) {
            final estudio = clase['estudios'] as Map<String, dynamic>?;
            if (estudio == null) return false;
            // El estudio entra si CUALQUIERA de sus categorias matchea.
            final objetivo = _categoriaSeleccionada.toLowerCase();
            return Estudio.parseCategorias(
              estudio,
            ).any((c) => c.trim().toLowerCase() == objetivo);
          }).toList();
    final clasesEstaSemana = clasesFiltradas.where((clase) {
      // Las fechas en DB estan en hora Argentina sin marker; forzamos UTC con
      // 'Z' para comparar en el mismo frame que 'ahora'.
      final raw = clase['fecha']?.toString() ?? '';
      final fecha = DateTime.tryParse('${raw.replaceFirst(' ', 'T')}Z');
      if (fecha == null) return false;
      return !fecha.isBefore(ahora) && !fecha.isAfter(finSemana);
    }).toList();
    final estudiosFiltrados = _categoriaSeleccionada == 'Todos'
        ? _estudios
        : _estudios
              .where(
                (estudio) => estudio.tieneCategoria(_categoriaSeleccionada),
              )
              .toList();
    final estudiosCerca = _studioGeoService
        .sortByDistance(estudiosFiltrados, _locationState.position)
        .take(6)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _cargar,
        child: Consumer<AppProvider>(
          builder: (context, provider, _) {
            final usuario = provider.usuario;
            return LayoutBuilder(
              builder: (context, restricciones) {
                // Contener el ancho: sin esto, en un monitor de 1920 la
                // tarjeta ocupaba toda la pantalla. El +40 son los 20 px de
                // padding de cada lado, para que el CONTENIDO tope en 1200.
                final anchoCaja = restricciones.maxWidth < anchoMaxVidriera + 40
                    ? restricciones.maxWidth
                    : anchoMaxVidriera + 40;
                final columnas = columnasVidriera(anchoCaja - 40);
                return Center(
                  child: SizedBox(
                    width: anchoCaja,
                    child: CustomScrollView(
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                                text:
                                                    usuario?.nombre
                                                        .split(' ')
                                                        .first ??
                                                    'Bienvenida',
                                              ),
                                              const TextSpan(text: ' ✦'),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // El invitado no tiene notificaciones: se oculta la
                                  // campana en vez de abrirle un panel vacío.
                                  if (!esInvitado)
                                    Stack(
                                      alignment: Alignment.topRight,
                                      children: [
                                        IconButton(
                                          onPressed: _mostrarNotificaciones,
                                          icon: const Icon(
                                            Icons.notifications_outlined,
                                            color: AppColors.black,
                                          ),
                                        ),
                                        if (_unreadNotifs > 0)
                                          Positioned(
                                            top: 8,
                                            right: 8,
                                            child: Container(
                                              width: 9,
                                              height: 9,
                                              decoration: const BoxDecoration(
                                                color: AppColors.primary,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    // Invitado: el avatar abre el muro cerrable, no lo
                                    // manda a /login.
                                    onTap: () => esInvitado
                                        ? RegistroMuro.mostrar(
                                            context,
                                            motivo: MuroMotivo.perfil,
                                          )
                                        : context.go('/perfil'),
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
                            // Invitado: donde va la card de créditos (que no tiene) va
                            // la invitación a crear cuenta. El resto del home —clases
                            // de la semana, experiencias, estudios cerca— lo ve igual.
                            child: esInvitado
                                ? _InvitadoCard(
                                    onCrearCuenta: () =>
                                        context.push('/register'),
                                    onIngresar: () => context.push('/login'),
                                  )
                                : usuario == null || (usuario.creditos) > 0
                                ? _PlanCard(usuario: usuario)
                                : !_tieneHistorialCreditos
                                ? _NuevoUsuarioCard(
                                    onVerPacks: () =>
                                        context.push('/comprar-creditos'),
                                  )
                                : _SinCreditosCard(
                                    onComprar: () =>
                                        context.push('/comprar-creditos'),
                                    onVerReservas: () =>
                                        context.go('/mis-reservas'),
                                  ),
                          ),
                        ),
                        // ── Tu QR de hoy (reserva dentro de las próximas 24 h) ──────
                        if (_proximaReserva != null)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                              child: _ProximaReservaCard(
                                reserva: _proximaReserva!,
                                onVerQr: () {
                                  final qr =
                                      _proximaReserva!['codigo_qr']
                                          ?.toString() ??
                                      '';
                                  if (qr.isNotEmpty) {
                                    context.push(
                                      '/reserva-confirmada/${Uri.encodeComponent(qr)}',
                                    );
                                  }
                                },
                              ),
                            ),
                          ),
                        // ── Credits expiry banner ─────────────────────────────
                        if (!_bannerDismissed && usuario != null) ...[
                          SliverToBoxAdapter(
                            child: Builder(
                              builder: (ctx) {
                                final venc = usuario.creditosVencimiento;
                                if (venc == null)
                                  return const SizedBox.shrink();
                                final dias = venc
                                    .difference(DateTime.now())
                                    .inDays;
                                if (dias < 0 || dias > 7)
                                  return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    12,
                                    20,
                                    0,
                                  ),
                                  child: _CreditosExpiryBanner(
                                    dias: dias,
                                    creditos: usuario.creditos,
                                    onDismiss: _dismissBanner,
                                    onExplorar: () => context.go('/explorar'),
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
                                        padding: const EdgeInsets.only(
                                          right: 12,
                                        ),
                                        child: _CategoryChip(
                                          label: categoria,
                                          active:
                                              _categoriaSeleccionada ==
                                              categoria,
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
                        // ── Card estudio asociado (alumno directo) ──────────
                        if (provider.estudioAsociado != null)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                              child: _EstudioAsociadoCard(
                                estudio: provider.estudioAsociado!,
                                onTap: () => context.push(
                                  '/estudio/${provider.estudioAsociado!.id}',
                                ),
                                onVerClases: () => context.push(
                                  '/estudio/${provider.estudioAsociado!.id}',
                                ),
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
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        letterSpacing: 0.8,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                GestureDetector(
                                  onTap: () => context.go('/explorar'),
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
                                ? (estudiosCerca.isEmpty
                                      ? const _EmptyNearbyCard()
                                      : SizedBox(
                                          height: 204,
                                          child: ListView.builder(
                                            scrollDirection: Axis.horizontal,
                                            itemCount: estudiosCerca.length,
                                            itemBuilder: (context, index) {
                                              final nearby =
                                                  estudiosCerca[index];
                                              return SizedBox(
                                                width: 220,
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 14,
                                                      ),
                                                  child: _NearbyStudyCard(
                                                    estudio: nearby.estudio,
                                                    distanceLabel:
                                                        _studioGeoService
                                                            .formatDistance(
                                                              nearby.distanceKm,
                                                            ),
                                                    onTap: () => context.push(
                                                      '/estudio/${nearby.estudio.id}',
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ))
                                : _LocationPromptCard(
                                    locationState: _locationState,
                                    requesting: _requestingLocation,
                                    onPrimaryTap: _pedirUbicacion,
                                  ),
                          ),
                        ),
                        if (_sugerencias.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'PARA VOS ✨',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          letterSpacing: 0.8,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  GestureDetector(
                                    onTap: () => context.go('/explorar'),
                                    child: const Text(
                                      'Ver más',
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
                            child: SizedBox(
                              height: altoCarruselVidriera,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                itemCount: _sugerencias.length,
                                itemBuilder: (context, index) {
                                  final clase = _sugerencias[index];
                                  return SizedBox(
                                    width: 320,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 14),
                                      child: HomeNearbyClassCard(
                                        clase: clase,
                                        onTap: () => context.push(
                                          '/clase/${clase['id']}',
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'CLASES ESTA SEMANA',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        letterSpacing: 0.8,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                GestureDetector(
                                  onTap: () => context.go('/explorar'),
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
                                style: TextStyle(
                                  color: AppColors.grey,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          )
                        else
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: altoCarruselVidriera,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                itemCount: clasesEstaSemana.length,
                                itemBuilder: (context, index) {
                                  final clase = clasesEstaSemana[index];
                                  return SizedBox(
                                    width: 320,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 14),
                                      child: HomeNearbyClassCard(
                                        clase: clase,
                                        onTap: () => context.push(
                                          '/clase/${clase['id']}',
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        // ── Experiencias (workshops / eventos próximos) ──────────────
                        if (_experiencias.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                24,
                                20,
                                14,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'EXPERIENCIAS',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          letterSpacing: 0.8,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  // Acá había un "Ver todas" que iba a /explorar, y
                                  // /explorar excluye los workshops
                                  // (`getProximasClases` hace .neq('tipo','workshop')):
                                  // la alumna caía en una pantalla sin ninguna
                                  // experiencia. No existe pantalla de experiencias —
                                  // es la feature en diseño con categorías y buscador
                                  // propios (Tanda E). Mientras tanto el carrusel trae
                                  // hasta 20 y hay 1 workshop en toda la base, así que
                                  // ya las muestra todas y el link sobraba.
                                ],
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: 340,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                itemCount: _experiencias.length,
                                itemBuilder: (context, index) {
                                  final exp = _experiencias[index];
                                  return SizedBox(
                                    width: 300,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 14),
                                      child: _HomeExperienceCard(
                                        clase: exp,
                                        onTap: () =>
                                            context.push('/clase/${exp['id']}'),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'ESTUDIOS',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        letterSpacing: 0.8,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                GestureDetector(
                                  onTap: () => context.go('/explorar'),
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
                                style: TextStyle(
                                  color: AppColors.grey,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          )
                        else
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: 252,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                itemCount: estudiosFiltrados.length,
                                itemBuilder: (context, index) {
                                  final estudio = estudiosFiltrados[index];
                                  return SizedBox(
                                    width: 220,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 14),
                                      child: _HomeStudyCard(
                                        estudio: estudio,
                                        onTap: () => context.push(
                                          '/estudio/${estudio.id}',
                                        ),
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
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        letterSpacing: 0.8,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                GestureDetector(
                                  onTap: () => context.go('/explorar'),
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
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                12,
                                20,
                                20,
                              ),
                              child: Center(
                                child: Text(
                                  'No hay clases para esta categoría cerca tuyo.\nProbá con otra opción.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: AppColors.grey,
                                        height: 1.6,
                                      ),
                                ),
                              ),
                            ),
                          )
                        else
                          // Grilla de 1, 2 o 3 columnas según el ancho. Antes era una
                          // lista de una sola columna a cualquier ancho: es la que
                          // estiraba la tarjeta de lado a lado en desktop.
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                            sliver: SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columnas,
                                    crossAxisSpacing: gapGrilla,
                                    mainAxisSpacing: gapGrilla,
                                    // Alto explícito en vez de proporción: así
                                    // todas las tarjetas miden exactamente lo
                                    // mismo y los pies quedan alineados. Es la
                                    // foto 16:9 de esta columna más el texto.
                                    mainAxisExtent: altoCardVidriera(
                                      anchoCelda(anchoCaja - 40, columnas),
                                    ),
                                  ),
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final clase = clasesFiltradas[index];
                                return HomeNearbyClassCard(
                                  clase: clase,
                                  onTap: () =>
                                      context.push('/clase/${clase['id']}'),
                                );
                              }, childCount: clasesFiltradas.length),
                            ),
                          ),
                        const SliverToBoxAdapter(child: SizedBox(height: 28)),
                      ],
                    ),
                  ),
                );
              },
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

// ─── Próxima reserva / Tu QR de hoy ───────────────────────────────────────────

class _ProximaReservaCard extends StatelessWidget {
  final Map<String, dynamic> reserva;
  final VoidCallback onVerQr;
  const _ProximaReservaCard({required this.reserva, required this.onVerQr});

  @override
  Widget build(BuildContext context) {
    final clase = reserva['clases'] as Map<String, dynamic>?;
    final estudio = clase?['estudios'] as Map<String, dynamic>?;
    final nombre = clase?['nombre']?.toString() ?? 'Tu clase';
    final estudioNombre = estudio?['nombre']?.toString() ?? '';
    final fecha = DateTime.tryParse(clase?['fecha']?.toString() ?? '');
    final cuando = fecha != null ? _cuando(fecha) : '';

    return GestureDetector(
      onTap: onVerQr,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.qr_code_2_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tu próxima clase',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (cuando.isNotEmpty) cuando,
                      if (estudioNombre.isNotEmpty) estudioNombre,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              children: const [
                Icon(Icons.chevron_right_rounded, color: Colors.white),
                Text(
                  'Ver QR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _cuando(DateTime fecha) {
    const argOffset = Duration(hours: -3);
    final ahora = DateTime.now().toUtc().add(argOffset);
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final dia = DateTime(fecha.year, fecha.month, fecha.day);
    final diff = dia.difference(hoy).inDays;
    final hh = fecha.hour.toString().padLeft(2, '0');
    final mm = fecha.minute.toString().padLeft(2, '0');
    if (diff == 0) return 'Hoy $hh:$mm';
    if (diff == 1) return 'Mañana $hh:$mm';
    return '${fecha.day}/${fecha.month} $hh:$mm';
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

/// Reemplaza a [_PlanCard] cuando no hay sesión: en el lugar donde el usuario
/// logueado ve sus créditos, el invitado ve la invitación a crear cuenta.
/// Mismo formato (negra, radius 24, padding 22) para que el home no se
/// desarme visualmente.
class _InvitadoCard extends StatelessWidget {
  final VoidCallback onCrearCuenta;
  final VoidCallback onIngresar;

  const _InvitadoCard({required this.onCrearCuenta, required this.onIngresar});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Estás explorando como invitada',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Creá tu cuenta\ny reservá tu primera clase',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: onCrearCuenta,
                    child: const Text('Crear cuenta'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: TextButton(
                  onPressed: onIngresar,
                  child: const Text(
                    'Ingresar',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
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
                      style: TextStyle(color: Colors.white70, fontSize: 15),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
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

// ─── Notificaciones del estudio ──────────────────────────────────────────────

class _NotificacionesSheet extends StatefulWidget {
  final AvisoAlumnosService service;
  final VoidCallback onLeidas;

  const _NotificacionesSheet({required this.service, required this.onLeidas});

  @override
  State<_NotificacionesSheet> createState() => _NotificacionesSheetState();
}

class _NotificacionesSheetState extends State<_NotificacionesSheet> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final items = await widget.service.getNotificaciones();
    await widget.service.marcarTodasLeidas();
    widget.onLeidas();
    if (mounted)
      setState(() {
        _items = items;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
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
          const SizedBox(height: 16),
          const Text(
            'Notificaciones',
            style: TextStyle(
              color: AppColors.black,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'Sin notificaciones',
                  style: TextStyle(color: Color(0xFF8F877F)),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _items.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Color(0xFFF0EDE9)),
                itemBuilder: (_, i) {
                  final item = _items[i];
                  final titulo = item['titulo']?.toString() ?? '';
                  final mensaje = item['mensaje']?.toString() ?? '';
                  final leida = item['leida'] == true;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 5, right: 10),
                          decoration: BoxDecoration(
                            color: leida
                                ? Colors.transparent
                                : AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (titulo.isNotEmpty)
                                Text(
                                  titulo,
                                  style: const TextStyle(
                                    color: AppColors.black,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              const SizedBox(height: 2),
                              Text(
                                mensaje,
                                style: const TextStyle(
                                  color: Color(0xFF5F5953),
                                  fontSize: 13,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Estado: usuario nuevo (nunca compró) ─────────────────────────────────────

class _NuevoUsuarioCard extends StatelessWidget {
  final VoidCallback onVerPacks;

  const _NuevoUsuarioCard({required this.onVerPacks});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.star_rounded, color: Color(0xFFE8763A), size: 40),
          const SizedBox(height: 12),
          const Text(
            'Bienvenida a Aura. 🧡',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFF7F5F2),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Comprá tu primer pack y empezá a reservar pilates, yoga, cerámica y más en Buenos Aires.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF8F877F),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: onVerPacks,
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
              child: const Text('Ver packs de créditos'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Estado: se acabaron los créditos ────────────────────────────────────────

class _SinCreditosCard extends StatelessWidget {
  final VoidCallback onComprar;
  final VoidCallback onVerReservas;

  const _SinCreditosCard({
    required this.onComprar,
    required this.onVerReservas,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.account_balance_wallet_rounded,
            color: Color(0xFFE8763A),
            size: 40,
          ),
          const SizedBox(height: 12),
          const Text(
            'Te quedaste sin créditos',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFF7F5F2),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Recargá para seguir reservando tus clases favoritas.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF8F877F),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: onComprar,
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
              child: const Text('Comprar créditos'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: onVerReservas,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFF7F5F2),
                side: const BorderSide(color: Color(0xFFF7F5F2), width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Ver mis reservas futuras'),
            ),
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

  const _CategoryChip({required this.label, this.active = false, this.onTap});

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

class HomeNearbyClassCard extends StatelessWidget {
  final Map<String, dynamic> clase;
  final VoidCallback onTap;

  const HomeNearbyClassCard({
    super.key,
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
    final lugaresDisponibles = (clase['lugares_disponibles'] as num?) ?? 0;

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
                // PROPORCIÓN, no alto fijo: así la foto no puede volver a
                // aplanarse por más ancha que quede la tarjeta. Con alto fijo
                // 132, en un monitor de 1920 la lista vertical la dejaba de
                // 1900 × 132 (14:1) y hasta en el carrusel de 320 daba 2,4:1.
                child: AspectRatio(
                  aspectRatio: proporcionFotoVidriera,
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

/// Card grande para la sección "Experiencias" (workshops / eventos).
/// Imagen más alta, badge "EVENTO" naranja y organizadores clickeables.
class _HomeExperienceCard extends StatelessWidget {
  final Map<String, dynamic> clase;
  final VoidCallback onTap;

  const _HomeExperienceCard({required this.clase, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final estudio = clase['estudios'] as Map<String, dynamic>?;
    final fecha = clase['fecha'] != null
        ? DateTime.tryParse(clase['fecha'].toString())
        : null;
    final imageUrl = (clase['imagen_url'] ?? estudio?['foto_url'])?.toString();
    final organizadores = (clase['organizadores'] as List?) ?? const [];

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
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    child: SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: _HomeClassImage(imageUrl: imageUrl),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'EVENTO',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            (clase['nombre'] ?? 'Evento').toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.black,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
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
                    const SizedBox(height: 6),
                    Text(
                      estudio?['nombre']?.toString() ?? 'Estudio',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.grey,
                        fontSize: 13,
                      ),
                    ),
                    if (organizadores.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      OrganizadoresLinks(organizadores: organizadores),
                    ],
                    if (fecha != null) ...[
                      const SizedBox(height: 10),
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
    // 900 px de descarga para un hueco de hasta 390 (3 columnas dentro de
    // 1200): alcanza para que se vea nítida en pantallas retina sin bajarse
    // los megas del original.
    return FotoRed(url: imageUrl, ancho: 900, fallback: _fallback());
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

  const _HomeStudyCard({required this.estudio, required this.onTap});

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
                      if (estudio.categorias.isNotEmpty)
                        Text(
                          estudio.categoriasLabel.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      if (estudio.categorias.isNotEmpty)
                        const SizedBox(height: 4),
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
        style: TextStyle(color: AppColors.grey, fontSize: 13, height: 1.45),
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

  const _LocationPromptCard({
    required this.locationState,
    required this.requesting,
    required this.onPrimaryTap,
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
                child: FotoRed(
                  url: estudio.fotoUrl,
                  ancho: 800,
                  fallback: const SizedBox.shrink(),
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
                      horizontal: 10,
                      vertical: 4,
                    ),
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
                  if (estudio.barrio != null && estudio.barrio!.isNotEmpty) ...[
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
                        horizontal: 18,
                        vertical: 9,
                      ),
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
