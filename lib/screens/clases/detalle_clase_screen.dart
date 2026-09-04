import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/aura_tokens.dart';
import '../../widgets/texto_expandible.dart';
import '../../widgets/aura_skeleton.dart';
import '../../providers/app_provider.dart';
import '../../services/aura_gestion_service.dart';
import '../../services/clases_service.dart';
import '../../services/reservas_service.dart';
import '../../services/reviews_service.dart';
import '../../services/waitlist_service.dart';
import '../../utils/creditos_faltantes.dart';
import '../../utils/destino_post_login.dart';
import '../../widgets/registro_muro.dart';
import '../../utils/cierre_minutos.dart';
import '../../utils/grilla_responsive.dart';
import '../../utils/mapa_link.dart';
import '../../widgets/organizadores_links.dart';
import '../../widgets/study_review_sheet.dart';

class DetalleClaseScreen extends StatefulWidget {
  final int claseId;

  const DetalleClaseScreen({super.key, required this.claseId});

  @override
  State<DetalleClaseScreen> createState() => _DetalleClaseScreenState();
}

class _DetalleClaseScreenState extends State<DetalleClaseScreen> {
  final _clasesService = ClasesService();
  final _reservasService = ReservasService();
  final _reviewsService = ReviewsService();
  final _gestionService = AuraGestionService();
  final _waitlistService = WaitlistService();

  Map<String, dynamic>? _clase;
  bool _loading = true;
  bool _yaReservado = false;
  bool _reservando = false;
  bool _canReview = false;
  bool _esGratuita = false;
  bool _enListaEspera = false;
  bool _togglingWaitlist = false;
  int _waitlistCount = 0;

  /// Alto real del CTA flotante, medido después de cada frame. Arranca en el
  /// valor viejo (56 = botón suelto) y se corrige solo.
  final GlobalKey _ctaKey = GlobalKey();
  double _altoCTA = 56;

  /// Puesto exacto en la lista de espera (1 = la próxima). null = no anotada
  /// o la RPC falló; en ese caso se muestra el conteo, como antes.
  int? _miPosicionEspera;
  List<Map<String, dynamic>> _reviews = [];

  // Lista de espera promovida -> pre_confirmada del usuario en esta clase.
  // Si esta seteada, el bloque de "Reservar" se reemplaza por la card
  // de confirmacion con countdown.
  Map<String, dynamic>? _preReserva;
  DateTime? _preReservaExpiresAt;
  Duration _preReservaRemaining = Duration.zero;
  Timer? _preReservaTimer;
  bool _confirmandoPreReserva = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _preReservaTimer?.cancel();
    super.dispose();
  }

  void _iniciarCountdownPreReserva() {
    _preReservaTimer?.cancel();
    final expiresAt = _preReservaExpiresAt;
    if (expiresAt == null) {
      _preReservaRemaining = Duration.zero;
      return;
    }
    void tick() {
      final remaining = expiresAt.toLocal().difference(DateTime.now());
      if (!mounted) return;
      if (remaining.isNegative || remaining.inSeconds <= 0) {
        setState(() {
          _preReservaRemaining = Duration.zero;
          _preReserva = null;
          _preReservaExpiresAt = null;
        });
        _preReservaTimer?.cancel();
        // Refrescar la pantalla (lugares + waitlist) por si quedo otra
        // pre-reserva activa o cambio el estado.
        _cargar();
      } else {
        setState(() => _preReservaRemaining = remaining);
      }
    }

    tick();
    _preReservaTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => tick(),
    );
  }

  String _formatPreReservaCountdown(Duration d) {
    final mins = d.inMinutes.toString().padLeft(2, '0');
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Future<void> _confirmarPreReserva() async {
    final preReserva = _preReserva;
    if (preReserva == null || _confirmandoPreReserva) return;
    final reservaId = (preReserva['id'] as num?)?.toInt();
    if (reservaId == null) return;
    final provider = context.read<AppProvider>();
    final userId = provider.userId;
    if (userId.isEmpty) return;
    final creditos = _esGratuita
        ? 0
        : ((_clase?['creditos'] as num?)?.toInt() ?? 0);

    setState(() => _confirmandoPreReserva = true);
    try {
      final reserva = await _reservasService.confirmarPreReserva(
        reservaId: reservaId,
        userId: userId,
        creditos: creditos,
      );
      await provider.refrescarUsuario();
      if (!mounted) return;
      _preReservaTimer?.cancel();
      // Navegar al ticket QR
      final codigoQr =
          reserva['codigo_qr']?.toString() ??
          preReserva['codigo_qr']?.toString() ??
          '';
      if (codigoQr.isNotEmpty) {
        context.push('/reserva-confirmada/${Uri.encodeComponent(codigoQr)}');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
      await _cargar();
    } finally {
      if (mounted) setState(() => _confirmandoPreReserva = false);
    }
  }

  Future<void> _rechazarPreReserva() async {
    final preReserva = _preReserva;
    if (preReserva == null || _confirmandoPreReserva) return;
    final reservaId = (preReserva['id'] as num?)?.toInt();
    if (reservaId == null) return;
    setState(() => _confirmandoPreReserva = true);
    try {
      await _reservasService.rechazarPreReserva(reservaId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Liberaste tu lugar. Le va a llegar al siguiente.'),
          backgroundColor: AppColors.blackSoft,
        ),
      );
      _preReservaTimer?.cancel();
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _confirmandoPreReserva = false);
    }
  }

  Future<void> _cargar() async {
    final provider = context.read<AppProvider>();
    try {
      final clase = await _clasesService.getClase(widget.claseId);
      bool yaReservado = false;

      if (clase != null && provider.userId.isNotEmpty) {
        yaReservado = await _reservasService.tieneReserva(
          provider.userId,
          widget.claseId,
        );
      }
      final estudioId =
          ((clase?['estudios'] as Map<String, dynamic>?)?['id'] as num?)
              ?.toInt();
      final reviews = estudioId != null
          ? await _reviewsService.getReviewsForStudy(estudioId)
          : <Map<String, dynamic>>[];
      final canReview = estudioId != null && provider.userId.isNotEmpty
          ? await _reviewsService.canReviewStudy(
              estudioId: estudioId,
              claseId: widget.claseId,
            )
          : false;

      // Verificar si la reserva es gratuita (alumno directo)
      final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';

      final futures = await Future.wait([
        userEmail.isNotEmpty
            ? _gestionService.reservaEsGratuita(
                claseId: widget.claseId,
                userEmail: userEmail,
              )
            : Future.value(false),
        provider.userId.isNotEmpty
            ? _waitlistService.isOnWaitlist(widget.claseId, provider.userId)
            : Future.value(false),
        _waitlistService.getCount(widget.claseId),
        provider.userId.isNotEmpty
            ? _waitlistService.getMiPosicion(widget.claseId)
            : Future.value(null),
      ]);

      final esGratuita = futures[0] as bool;
      final enListaEspera = futures[1] as bool;
      final waitlistCount = futures[2] as int;
      final miPos = futures[3] as ({int posicion, int total})?;

      // Buscar pre_confirmada activa del usuario para esta clase
      Map<String, dynamic>? preReserva;
      DateTime? expiresAt;
      if (provider.userId.isNotEmpty) {
        try {
          final pre = await Supabase.instance.client
              .from('reservas')
              .select('id, codigo_qr, creditos_usados, expires_at')
              .eq('usuario_id', provider.userId)
              .eq('clase_id', widget.claseId)
              .eq('estado', 'pre_confirmada')
              .gt('expires_at', DateTime.now().toUtc().toIso8601String())
              .maybeSingle();
          if (pre != null) {
            preReserva = Map<String, dynamic>.from(pre);
            expiresAt = DateTime.tryParse(pre['expires_at']?.toString() ?? '');
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _clase = clase;
        _yaReservado = yaReservado;
        _canReview = canReview;
        _reviews = reviews;
        _esGratuita = esGratuita;
        _enListaEspera = enListaEspera;
        _waitlistCount = waitlistCount;
        _miPosicionEspera = miPos?.posicion;
        _preReserva = preReserva;
        _preReservaExpiresAt = expiresAt;
        _loading = false;
      });
      _iniciarCountdownPreReserva();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo cargar la clase'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _irAConfirmar() async {
    if (_yaReservado || _reservando || _clase == null) return;

    final fecha = DateTime.tryParse(_clase!['fecha']?.toString() ?? '');
    final cierreMinutos = CierreMinutos.reserva(_clase);
    if (fecha != null && ReservasService.reservaCerrada(fecha, cierreMinutos)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cierreMinutos > 0
                ? 'Las reservas se cierran ${ReservasService.labelCierreReserva(cierreMinutos)}.'
                : 'Las reservas ya están cerradas para esta clase.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final lugaresDisp = (_clase!['lugares_disponibles'] ?? 0) as num;
    if (lugaresDisp <= 0) return;

    final provider = context.read<AppProvider>();
    final creditos = (_clase!['creditos'] as num?)?.toInt() ?? 1;
    final saldo = provider.usuario?.creditos ?? 0;

    if (!_esGratuita && saldo < creditos) {
      if (!mounted) return;
      _mostrarPaywall(creditos, saldo);
      return;
    }

    // Validar superposicion horaria
    final duracion = (_clase!['duracion_min'] as num?)?.toInt() ?? 60;
    if (fecha != null && provider.userId.isNotEmpty) {
      setState(() => _reservando = true);
      final conflicto = await _verificarConflicto(
        provider.userId,
        fecha,
        duracion,
      );
      if (!mounted) return;
      setState(() => _reservando = false);
      if (conflicto != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ya tenes "$conflicto" reservada en ese horario.'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    context.push('/confirmar-reserva/${widget.claseId}');
  }

  /// Devuelve el nombre de la clase conflictiva, o null si no hay conflicto.
  Future<String?> _verificarConflicto(
    String userId,
    DateTime fecha,
    int duracion,
  ) async {
    try {
      final reservas = await _reservasService.getReservasUsuario(userId);
      final finNueva = fecha.add(Duration(minutes: duracion));
      for (final r in reservas) {
        if ((r['estado'] as String?) == 'cancelada') continue;
        final clase = r['clases'] as Map<String, dynamic>?;
        if (clase == null) continue;
        final fExistente = DateTime.tryParse(clase['fecha']?.toString() ?? '');
        if (fExistente == null) continue;
        final durExistente = (clase['duracion_min'] as num?)?.toInt() ?? 60;
        final finExistente = fExistente.add(Duration(minutes: durExistente));
        if (fecha.isBefore(finExistente) && finNueva.isAfter(fExistente)) {
          return clase['nombre']?.toString() ?? 'otra clase';
        }
      }
      return null;
    } catch (_) {
      return null; // No bloquear por error de red
    }
  }

  void _mostrarPaywall(int creditosNecesarios, int creditosActuales) {
    // La ruta se captura ACÁ, con el context de la página: adentro del sheet
    // (ruta hermana en el Navigator) `GoRouterState.of` tira GoError. Mismo
    // motivo que en el muro del modo visita.
    final volver = DestinoPostLogin.rutaActualDe(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PaywallSheet(
        creditosNecesarios: creditosNecesarios,
        creditosActuales: creditosActuales,
        volver: volver,
      ),
    );
  }

  Future<void> _dejarResena() async {
    final clase = _clase;
    final estudio = clase?['estudios'] as Map<String, dynamic>?;
    final estudioId = (estudio?['id'] as num?)?.toInt();
    if (clase == null || estudioId == null) return;

    final saved = await StudyReviewSheet.show(
      context,
      estudioId: estudioId,
      estudioNombre: estudio?['nombre']?.toString() ?? 'Estudio',
      claseId: widget.claseId,
      experienciaLabel: clase['nombre']?.toString(),
    );

    if (saved == true && mounted) {
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gracias por compartir tu experiencia.'),
          backgroundColor: AppColors.blackSoft,
        ),
      );
    }
  }

  Future<void> _toggleListaEspera() async {
    final userId = context.read<AppProvider>().userId;
    if (userId.isEmpty || _togglingWaitlist) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _togglingWaitlist = true);
    try {
      if (_enListaEspera) {
        await _waitlistService.leave(widget.claseId, userId);
        if (!mounted) return;
        setState(() {
          _enListaEspera = false;
          _waitlistCount = (_waitlistCount - 1).clamp(0, 9999);
          _miPosicionEspera = null;
        });
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Te quitaste de la lista de espera.'),
            backgroundColor: AppColors.blackSoft,
          ),
        );
      } else {
        await _waitlistService.join(widget.claseId, userId);
        // El puesto lo decide la base por orden de llegada: si dos se anotan
        // a la vez, contar en el cliente daría el mismo número a las dos.
        final pos = await _waitlistService.getMiPosicion(widget.claseId);
        if (!mounted) return;
        setState(() {
          _enListaEspera = true;
          _waitlistCount = pos?.total ?? (_waitlistCount + 1);
          _miPosicionEspera = pos?.posicion;
        });
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              pos == null
                  ? '¡Anotada! Te avisamos si se libera un lugar.'
                  : 'Listo, sos la N° ${pos.posicion} en la lista de espera. '
                        'Te avisamos si se libera un lugar.',
            ),
            backgroundColor: AppColors.blackSoft,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo actualizar la lista de espera.'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _togglingWaitlist = false);
    }
  }

  /// Comparte la clase con el link a su página web.
  ///
  /// Reemplaza al "invitar amigas" por mail, que pedía escribir la dirección
  /// de la otra persona: nadie se la sabe de memoria y era uno a uno. Esto
  /// abre el compartir nativo del teléfono, así el link se puede pegar en una
  /// historia, un grupo de WhatsApp o donde sea.
  Future<void> _compartirClase() async {
    final clase = _clase;
    if (clase == null) return;

    final nombre = clase['nombre']?.toString().trim() ?? 'una clase';
    final estudio = (clase['estudios'] as Map<String, dynamic>?)?['nombre']
        ?.toString()
        .trim();
    final fecha = DateTime.tryParse(clase['fecha']?.toString() ?? '');

    final partes = <String>[
      estudio != null && estudio.isNotEmpty ? '$nombre en $estudio' : nombre,
      if (fecha != null)
        DateFormat("EEEE d 'de' MMMM 'a las' HH:mm", 'es').format(fecha),
      'Reservá en Aura 🧡',
      AppConstants.linkDeClase(widget.claseId),
    ];

    final texto = partes.join('\n');
    // Web Share API no existe en todos lados (Safari viejo, Chrome en Linux,
    // y NUNCA en http://localhost) y share_plus LANZA cuando falta: el botón
    // quedaba mudo. Fallback: copiar al portapapeles con aviso — nadie se va
    // sin el link.
    try {
      await Share.share(texto);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: texto));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link copiado: pegalo donde quieras 🧡')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _medirCTA());
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          // Antes: un spinner solo en el medio de una pantalla vacía. Ahora la
          // silueta de lo que viene, con el alto real de la foto.
          //
          // Los otros dos spinners de esta pantalla SÍ se dejan: son de 18 y 20
          // px y viven DENTRO de un botón mientras se manda la reserva. Ahí un
          // spinner es lo correcto; una silueta sería mentir sobre lo que pasa.
          ? LayoutBuilder(
              builder: (context, r) => SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AuraSkeleton(
                      height: altoHero(r.maxWidth),
                      borderRadius: BorderRadius.zero,
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AuraEspacio.margen),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AuraSkeleton(height: 26, width: 240),
                          const SizedBox(height: AuraEspacio.m),
                          AuraSkeleton.renglon(),
                          const SizedBox(height: AuraEspacio.s),
                          AuraSkeleton.renglon(
                            ancho: (r.maxWidth - AuraEspacio.margen * 2) * 0.55,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          : _clase == null
          ? const Center(child: Text('Clase no encontrada'))
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final clase = _clase!;
    final estudio = clase['estudios'] as Map<String, dynamic>?;
    final fecha = clase['fecha'] != null
        ? DateTime.tryParse(clase['fecha'].toString())
        : null;
    final cierreMinutos = CierreMinutos.reserva(clase);
    final reservaCerrada =
        fecha != null && ReservasService.reservaCerrada(fecha, cierreMinutos);
    final lugaresDisp = (clase['lugares_disponibles'] ?? 0) as num;
    final creditos = (clase['creditos'] as num?)?.toInt() ?? 1;
    final creditosSaldo = context.watch<AppProvider>().usuario?.creditos ?? 0;
    final disponible = lugaresDisp > 0 && !_yaReservado && !reservaCerrada;

    // El CTA flota sobre el scroll (Positioned), así que el contenido tiene
    // que reservarle lugar o le queda tapado. El padding estaba fijo en 120,
    // que alcanza para el botón suelto (56) pero NO para las dos variantes
    // altas: la de lista de espera (cartel de "no se te cobran créditos" +
    // puesto + botón) y la tarjeta de pre-reserva con countdown. Por eso el
    // final de la pantalla quedaba tapado.
    // Se mide el alto real en vez de estimarlo por variante: así vale también
    // para la variante que se agregue mañana, y para cuando un texto pase a
    // dos renglones en pantalla angosta.
    final espacioParaCTA =
        MediaQuery.of(context).padding.bottom + 16 + _altoCTA + 16;
    final barrio = estudio?['barrio']?.toString() ?? 'Palermo';
    final estudioNombre = estudio?['nombre']?.toString() ?? 'Aura Studio';
    final categoria = estudio?['categoria']?.toString().toUpperCase() ?? 'YOGA';
    final galleryUrls = ((clase['galeria_urls'] as List?) ?? const [])
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList();
    final avgRating = _reviews.isEmpty
        ? ((estudio?['rating'] as num?)?.toDouble() ?? 0)
        : _reviews
                  .map((review) => (review['rating'] as num?)?.toDouble() ?? 0)
                  .reduce((a, b) => a + b) /
              _reviews.length;
    final reviewCount = _reviews.length;

    // Contener el ancho: el hero tenía alto fijo 300 y ancho libre, así que en
    // un monitor quedaba de 1920 x 300 (6,4:1, una franja). Ahora es 2:1 con
    // piso de 300, o sea que en teléfono queda igual que antes. La galería no
    // se toca: sigue abriendo las fotos enteras.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: anchoMaxDetalle),
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: LayoutBuilder(
                    builder: (context, restricciones) => SizedBox(
                      height: altoHero(restricciones.maxWidth),
                      width: double.infinity,
                      child: Stack(
                        children: [
                          // Imagen hero — altura fija, recortada
                          Positioned.fill(
                            child: _HeroImage(
                              imageUrl:
                                  (clase['imagen_url'] ?? estudio?['foto_url'])
                                      ?.toString(),
                              imageMode: clase['imagen_ajuste']?.toString(),
                            ),
                          ),
                          // Gradiente: cubre el 40% inferior con negro opaco
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  stops: const [0.0, 0.4, 1.0],
                                  colors: [
                                    Color(0xE6000000), // #000 alpha 0.9
                                    Colors.transparent,
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Flecha volver — esquina superior izquierda
                          Positioned(
                            top: 0,
                            left: 0,
                            child: SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: 10,
                                  left: 16,
                                ),
                                child: _CircleAction(
                                  icon: Icons.arrow_back,
                                  onTap: () => context.pop(),
                                ),
                              ),
                            ),
                          ),
                          // Badge + título + estudio — esquina inferior
                          Positioned(
                            left: 20,
                            right: 20,
                            bottom: 16,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(AuraRadio.pastilla),
                                  ),
                                  child: Text(
                                    categoria,
                                    style: const TextStyle(
                                      color: AppColors.white,
                                      fontSize: AuraTipo.secundario,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  clase['nombre']?.toString() ?? 'Clase',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    height: 1.15,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap: estudio?['id'] != null
                                      ? () => context.push(
                                          '/estudio/${estudio!['id']}',
                                        )
                                      : null,
                                  child: Text(
                                    '$estudioNombre - $barrio',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.85,
                                      ),
                                      fontSize: AuraTipo.cuerpo,
                                      decoration: TextDecoration.underline,
                                      decorationColor: Colors.white.withValues(
                                        alpha: 0.85,
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
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, espacioParaCTA),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Rating: tocarlo abre todas las reseñas del estudio.
                        // Antes era texto muerto, y son justo lo que se mira
                        // para decidir si reservar esta clase.
                        InkWell(
                          onTap: (reviewCount == 0 || estudio?['id'] == null)
                              ? null
                              : () => context.push(
                                  '/estudio/${estudio!['id']}/resenas'
                                  '?nombre=${Uri.encodeComponent(estudio['nombre']?.toString() ?? '')}',
                                ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: Color(0xFFF5A623),
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                avgRating > 0
                                    ? avgRating.toStringAsFixed(1)
                                    : 'Nuevo',
                                style: const TextStyle(
                                  color: AppColors.black,
                                  fontSize: AuraTipo.cuerpo,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                reviewCount == 0
                                    ? 'Sin reseñas todavía'
                                    : '$reviewCount reseñas',
                                style: TextStyle(
                                  color: reviewCount == 0
                                      ? AppColors.grey
                                      : AppColors.primary,
                                  fontSize: AuraTipo.secundario,
                                  fontWeight: reviewCount == 0
                                      ? FontWeight.w400
                                      : FontWeight.w600,
                                ),
                              ),
                              if (reviewCount > 0)
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                  color: AppColors.primary,
                                ),
                            ],
                          ),
                        ),
                        if (estudio?['id'] != null) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _HeaderActionPill(
                                icon: Icons.storefront_outlined,
                                label: 'Ver estudio',
                                onTap: () =>
                                    context.push('/estudio/${estudio!['id']}'),
                              ),
                              _HeaderActionPill(
                                icon: Icons.map_outlined,
                                label: 'Ver en mapa',
                                onTap: () {
                                  final uri = Uri(
                                    path: '/mapa',
                                    queryParameters: {
                                      if ((estudio?['categoria'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        'categoria': estudio!['categoria']
                                            .toString(),
                                      if ((estudio?['nombre'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        'q': estudio!['nombre'].toString(),
                                    },
                                  );
                                  context.push(uri.toString());
                                },
                              ),
                              if (_canReview)
                                _HeaderActionPill(
                                  icon: Icons.star_outline_rounded,
                                  label: 'Dejar reseña',
                                  onTap: _dejarResena,
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _InfoChipCard(
                              icon: Icons.calendar_today_outlined,
                              label: fecha != null
                                  ? DateFormat('EEE d MMM', 'es').format(fecha)
                                  : 'Fecha',
                            ),
                            _InfoChipCard(
                              icon: Icons.alarm_outlined,
                              label: clase['duracion_min'] != null
                                  ? '${clase['duracion_min']} min'
                                  : '60 min',
                            ),
                            _InfoChipCard(
                              icon: Icons.place_outlined,
                              label: clase['sala']?.toString() ?? 'Sala 2',
                            ),
                            _InfoChipCard(
                              icon: Icons.people_outline_rounded,
                              label: '$lugaresDisp plazas',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                          decoration: BoxDecoration(
                            color: AppColors.blackSoft,
                            borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x12000000),
                                blurRadius: 18,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: _esGratuita
                              ? Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF1E3A1E),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check_circle_outline_rounded,
                                        color: Color(0xFF66BB6A),
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Reserva gratuita',
                                            style: TextStyle(
                                              color: Color(0xFF66BB6A),
                                              fontSize: AuraTipo.titulo,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            'Sos alumno/a de este estudio',
                                            style: TextStyle(
                                              color: Color(0xFFA7A09A),
                                              fontSize: AuraTipo.secundario,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 7,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Precio 0 = "esta clase es gratis para
                                          // todas", que NO es lo mismo que
                                          // `_esGratuita` ("vos ya le pagás a este
                                          // estudio", modo gestión, por usuaria). Hoy
                                          // no pueden coexistir en una pantalla, pero
                                          // son cosas distintas: no unificarlas.
                                          if (creditos == 0)
                                            const Text(
                                              'Gratis',
                                              style: TextStyle(
                                                color: AppColors.primary,
                                                fontSize: 38,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            )
                                          else
                                            RichText(
                                              text: TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text: '$creditos',
                                                    style: const TextStyle(
                                                      color: AppColors.primary,
                                                      fontSize: 38,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  const TextSpan(
                                                    text: ' créditos',
                                                    style: TextStyle(
                                                      color: AppColors.primary,
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          const SizedBox(height: 6),
                                          const Text(
                                            'Precio de esta clase',
                                            style: TextStyle(
                                              color: Color(0xFFA7A09A),
                                              fontSize: AuraTipo.cuerpo,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // "Tu saldo" — solo logueado. El invitado ve el
                                    // precio (izquierda) pero no tiene saldo.
                                    if (Supabase
                                            .instance
                                            .client
                                            .auth
                                            .currentUser !=
                                        null) ...[
                                      Container(
                                        width: 1,
                                        height: 54,
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        color: const Color(0x26FFFFFF),
                                      ),
                                      Expanded(
                                        flex: 4,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Tu saldo',
                                              style: TextStyle(
                                                color: Color(0xFFA7A09A),
                                                fontSize: AuraTipo.cuerpo,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              '$creditosSaldo créditos',
                                              style: const TextStyle(
                                                color: AppColors.white,
                                                fontSize: AuraTipo.cuerpo,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              // Antes: 'Quedan ${creditosSaldo - creditos}',
                                              // una resta cruda que con saldo 0
                                              // mostraba "Quedan -8 tras reservar".
                                              textoSaldoTrasReservar(
                                                saldo: creditosSaldo,
                                                precio: creditos,
                                              ),
                                              style: const TextStyle(
                                                color: Color(0xFFA7A09A),
                                                fontSize: AuraTipo.secundario,
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                        ),

                        const SizedBox(height: 18),
                        if (galleryUrls.isNotEmpty)
                          Column(
                            children: [
                              _SectionBlock(
                                title: 'Galería',
                                child: SizedBox(
                                  height: 92,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: galleryUrls.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 10),
                                    itemBuilder: (context, index) {
                                      final imageUrl = galleryUrls[index];
                                      return InkWell(
                                        borderRadius: BorderRadius.circular(AuraRadio.boton),
                                        onTap: () => _abrirGaleria(
                                          galleryUrls,
                                          initialIndex: index,
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          child: SizedBox(
                                            width: 120,
                                            child: CachedNetworkImage(
                                              imageUrl: imageUrl,
                                              fit: BoxFit.cover,
                                              errorWidget: (_, __, ___) =>
                                                  Container(
                                                    color: const Color(
                                                      0xFFF3EEE8,
                                                    ),
                                                    child: const Icon(
                                                      Icons
                                                          .image_not_supported_outlined,
                                                      color: AppColors.grey,
                                                    ),
                                                  ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                            ],
                          ),
                        if ((clase['descripcion']?.toString().trim() ?? '')
                            .isNotEmpty)
                          Column(
                            children: [
                              _SectionBlock(
                                title: 'Sobre el evento',
                                // La descripción más larga de producción es la
                                // de un workshop: 1484 caracteres, más de 35
                                // renglones en un teléfono.
                                child: TextoExpandible(
                                  clase['descripcion'].toString(),
                                  estilo: const TextStyle(
                                    color: Color(0xFF5E584F),
                                    fontSize: AuraTipo.cuerpo,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                            ],
                          ),
                        // Organizadores de la experiencia, con su @ clickeable.
                        // Home y explorar ya los mostraban; acá faltaban, así que
                        // al abrir el detalle desaparecían los créditos de quien
                        // la daba. Mismo widget, mismo comportamiento.
                        if (((clase['organizadores'] as List?) ?? const [])
                            .isNotEmpty)
                          Column(
                            children: [
                              _SectionBlock(
                                title: 'Quién la da',
                                child: OrganizadoresLinks(
                                  organizadores:
                                      (clase['organizadores'] as List?) ??
                                      const [],
                                ),
                              ),
                              const SizedBox(height: 18),
                            ],
                          ),
                        if ((clase['direccion']?.toString().trim() ?? '')
                            .isNotEmpty)
                          Column(
                            children: [
                              _SectionBlock(
                                title: 'Dónde',
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.location_on_outlined,
                                      size: 18,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    // La dirección abre el mapa: nadie quiere
                                    // copiarla a mano para saber cómo llegar.
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => abrirMapa(
                                          direccion: clase['direccion']
                                              ?.toString(),
                                        ),
                                        child: Text(
                                          clase['direccion'].toString(),
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontSize: AuraTipo.cuerpo,
                                            height: 1.5,
                                            decoration:
                                                TextDecoration.underline,
                                            decorationColor: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                            ],
                          ),
                        if ((clase['incluye']?.toString().trim() ?? '')
                            .isNotEmpty)
                          Column(
                            children: [
                              _SectionBlock(
                                title: 'Qué incluye',
                                child: Text(
                                  clase['incluye'].toString(),
                                  style: const TextStyle(
                                    color: Color(0xFF5E584F),
                                    fontSize: AuraTipo.cuerpo,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                            ],
                          ),
                        if ((clase['instructor']?.toString().trim() ?? '')
                            .isNotEmpty)
                          _SectionBlock(
                            title: 'Instructor',
                            child: Row(
                              children: [
                                Container(
                                  width: 58,
                                  height: 58,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      _initials(
                                        clase['instructor']?.toString() ?? 'MR',
                                      ),
                                      style: const TextStyle(
                                        color: AppColors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        clase['instructor']?.toString() ?? '',
                                        style: const TextStyle(
                                          color: AppColors.black,
                                          fontSize: AuraTipo.titulo,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if ((clase['instructor_descripcion']
                                                  ?.toString()
                                                  .trim() ??
                                              '')
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          clase['instructor_descripcion']
                                              .toString(),
                                          style: const TextStyle(
                                            color: Color(0xFF8F877F),
                                            fontSize: AuraTipo.secundario,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if ((clase['instructor']?.toString().trim() ?? '')
                            .isNotEmpty)
                          const SizedBox(height: 18),
                        _SectionBlock(
                          title: 'Política de cancelación',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // La ventana la define el estudio (o la clase);
                              // no hardcodeamos 12 hs. Ver CierreMinutos.
                              _PolicyItem(
                                'Cancelación gratuita hasta '
                                '${CierreMinutos.formatDuracion(CierreMinutos.cancelacion(clase))}'
                                ' antes de la clase.',
                              ),
                              if (cierreMinutos > 0)
                                _PolicyItem(
                                  'Las reservas cierran '
                                  '${CierreMinutos.formatDuracion(cierreMinutos)}'
                                  ' antes de que empiece.',
                                ),
                              const _PolicyItem(
                                'Cancelaciones tardías o no-shows consumen los créditos completos.',
                              ),
                              const _PolicyItem(
                                'Los créditos no son reembolsables una vez consumidos.',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _compartirClase,
                          icon: const Icon(Icons.ios_share_rounded, size: 18),
                          // Las experiencias (workshops) no son "clases": el
                          // botón las nombra como lo que son.
                          label: Text(
                            clase['tipo']?.toString() == 'workshop'
                                ? 'Compartir esta experiencia'
                                : 'Compartir esta clase',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AuraRadio.boton),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _SectionBlock(
                          title: 'Reservas',
                          child: Text(
                            reservaCerrada
                                ? (cierreMinutos > 0
                                      ? 'Las reservas ya están cerradas. Este estudio permite agendar ${ReservasService.labelCierreReserva(cierreMinutos)}.'
                                      : 'Las reservas ya están cerradas para esta clase.')
                                : 'Podés reservar ${ReservasService.labelCierreReserva(cierreMinutos)}.',
                            style: const TextStyle(
                              color: AppColors.grey,
                              fontSize: AuraTipo.cuerpo,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: MediaQuery.of(context).padding.bottom + 16,
              child: KeyedSubtree(
                key: _ctaKey,
                child: _buildBottomAction(
                  lugaresDisp: lugaresDisp.toInt(),
                  reservaCerrada: reservaCerrada,
                  disponible: disponible,
                  creditos: creditos,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mide el CTA ya dibujado y, si cambió de alto, vuelve a construir para
  /// que el scroll le reserve exactamente ese lugar. La comparación con
  /// tolerancia corta el ciclo: sin eso, cada setState pediría otro frame
  /// para siempre.
  void _medirCTA() {
    final ctx = _ctaKey.currentContext;
    final alto = ctx?.size?.height;
    if (alto == null || !mounted) return;
    if ((alto - _altoCTA).abs() > 0.5) {
      setState(() => _altoCTA = alto);
    }
  }

  Widget _buildBottomAction({
    required int lugaresDisp,
    required bool reservaCerrada,
    required bool disponible,
    required int creditos,
  }) {
    // Invitado: no puede reservar ni anotarse a lista de espera sin cuenta.
    // El muro es un pop-up cerrable (no navega): si lo cierra, sigue viendo
    // esta misma clase. El precio se ve igual en la card de arriba.
    if (Supabase.instance.client.auth.currentUser == null) {
      // Sin lugares -> el CTA honesto es la lista de espera, no "reservar".
      final esWaitlist = lugaresDisp <= 0 && !reservaCerrada;
      return SizedBox(
        height: 56,
        child: ElevatedButton(
          onPressed: () => RegistroMuro.mostrar(
            context,
            motivo: esWaitlist ? MuroMotivo.listaEspera : MuroMotivo.reservar,
          ),
          child: Text(
            esWaitlist
                ? 'Registrate para anotarte'
                : 'Registrate para reservar',
          ),
        ),
      );
    }

    // 1) Pre-confirmada activa -> card de confirmacion con countdown.
    if (_preReserva != null && _preReservaRemaining.inSeconds > 0) {
      return _PreReservaConfirmCard(
        remaining: _preReservaRemaining,
        formatTime: _formatPreReservaCountdown,
        creditos: _esGratuita ? 0 : creditos,
        esGratuita: _esGratuita,
        loading: _confirmandoPreReserva,
        onConfirmar: _confirmarPreReserva,
        onRechazar: _rechazarPreReserva,
      );
    }

    // 2) Sin lugares y NO reservado y reserva abierta -> waitlist (con
    //    mensaje de "no se cobran creditos hasta confirmar").
    if (lugaresDisp <= 0 && !_yaReservado && !reservaCerrada) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFDF0E8),
              borderRadius: BorderRadius.circular(AuraRadio.boton),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: const Text(
              'No se te cobran créditos hasta que confirmes tu lugar.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: AuraTipo.secundario,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _WaitlistButton(
            enListaEspera: _enListaEspera,
            waitlistCount: _waitlistCount,
            miPosicion: _miPosicionEspera,
            loading: _togglingWaitlist,
            onTap: _toggleListaEspera,
          ),
        ],
      );
    }

    // 3) Camino normal: boton "Reservar" / "Ya reservada" / "Sin lugares".
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: _yaReservado
            ? null
            : !disponible
            ? null
            : _irAConfirmar,
        child: Text(
          _yaReservado
              ? 'Ya reservada'
              : !disponible
              ? (reservaCerrada ? 'Reservas cerradas' : 'Sin lugares')
              : (_esGratuita || creditos == 0)
              ? 'Reservar gratis'
              : 'Reservar · $creditos créditos',
        ),
      ),
    );
  }

  Future<void> _abrirGaleria(
    List<String> imageUrls, {
    int initialIndex = 0,
  }) async {
    if (imageUrls.isEmpty) return;
    final controller = PageController(initialPage: initialIndex);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var currentIndex = initialIndex;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => Dialog.fullscreen(
            backgroundColor: Colors.black,
            child: Stack(
              children: [
                PageView.builder(
                  controller: controller,
                  itemCount: imageUrls.length,
                  onPageChanged: (value) =>
                      setDialogState(() => currentIndex = value),
                  itemBuilder: (_, index) => InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: CachedNetworkImage(
                        imageUrl: imageUrls[index],
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) => const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white70,
                          size: 42,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(dialogContext).padding.top + 12,
                  left: 16,
                  child: IconButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black45,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(dialogContext).padding.top + 20,
                  right: 20,
                  child: Text(
                    '${currentIndex + 1}/${imageUrls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: AuraTipo.cuerpo,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _initials(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'MR';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _HeroImage extends StatelessWidget {
  final String? imageUrl;
  final String? imageMode;

  const _HeroImage({this.imageUrl, this.imageMode});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      final useContain = imageMode == 'contain';
      return Container(
        color: const Color(0xFF151412),
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          fit: useContain ? BoxFit.contain : BoxFit.cover,
          alignment: Alignment.center,
          errorWidget: (_, __, ___) => _placeholder(),
          placeholder: (_, __) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFF708B8E),
      child: const Center(
        child: Icon(
          Icons.self_improvement_rounded,
          size: 86,
          color: Colors.white70,
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _CircleAction({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _InfoChipCard extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChipCard({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 164),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 16),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF625C57),
                fontSize: AuraTipo.secundario,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionBlock({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: AppColors.black,
              fontSize: AuraTipo.titulo,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _PaywallSheet extends StatelessWidget {
  final int creditosNecesarios;
  final int creditosActuales;

  /// La clase desde la que se abrió el paywall. Viaja hasta el checkout para
  /// que, después de pagar, la usuaria vuelva ACÁ y pueda reservar — en vez
  /// de caer en /home y tener que buscar de nuevo la clase que ya pagó.
  final String volver;

  const _PaywallSheet({
    required this.creditosNecesarios,
    required this.creditosActuales,
    required this.volver,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF7F5F2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFCCC5BD),
              borderRadius: BorderRadius.circular(AuraRadio.pastilla),
            ),
          ),
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.star_outline_rounded,
              color: AppColors.primary,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            tituloPaywall(
              saldo: creditosActuales,
              precio: creditosNecesarios,
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.black,
              fontSize: AuraTipo.titulo,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            // A quien todavía no compró se le explica QUÉ es un crédito: para
            // alguien que llega de la pauta, "créditos insuficientes" no
            // significa nada. Ver utils/creditos_faltantes.dart.
            mensajePaywall(
              saldo: creditosActuales,
              precio: creditosNecesarios,
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF8F877F),
              fontSize: AuraTipo.cuerpo,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          // UNA sola acción principal. Antes había dos botones con el mismo
          // texto y el mismo destino, uno lleno y otro con borde: se veían
          // como opciones distintas y no lo eran (4/9/2026).
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                context.push(
                  DestinoPostLogin.conVolver('/comprar-creditos', volver),
                );
              },
              child: const Text('Comprar créditos'),
            ),
          ),
          const SizedBox(height: 4),
          // La salida, discreta y explícita: la hoja se podía cerrar
          // arrastrándola, pero nada en pantalla lo decía.
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8F877F),
              minimumSize: const Size(double.infinity, 44),
            ),
            child: const Text(
              'Ahora no',
              style: TextStyle(fontSize: AuraTipo.cuerpo, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeaderActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AuraRadio.pastilla),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: AppColors.black),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.black,
                fontSize: AuraTipo.secundario,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreReservaConfirmCard extends StatelessWidget {
  final Duration remaining;
  final String Function(Duration) formatTime;
  final int creditos;
  final bool esGratuita;
  final bool loading;
  final VoidCallback onConfirmar;
  final VoidCallback onRechazar;

  const _PreReservaConfirmCard({
    required this.remaining,
    required this.formatTime,
    required this.creditos,
    required this.esGratuita,
    required this.loading,
    required this.onConfirmar,
    required this.onRechazar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF0E8),
        borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
        border: Border.all(color: AppColors.primary, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.timer_rounded,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      color: AppColors.black,
                      fontSize: AuraTipo.cuerpo,
                      fontWeight: FontWeight.w600,
                    ),
                    children: [
                      const TextSpan(text: 'Tenés '),
                      TextSpan(
                        text: formatTime(remaining),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: AuraTipo.titulo,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Courier',
                        ),
                      ),
                      const TextSpan(text: ' para confirmar tu lugar'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: loading ? null : onConfirmar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AuraRadio.boton),
                ),
              ),
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      (esGratuita || creditos == 0)
                          ? 'Confirmar (gratis)'
                          : 'Confirmar y pagar · $creditos cr',
                      style: const TextStyle(
                        fontSize: AuraTipo.cuerpo,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton(
              onPressed: loading ? null : onRechazar,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8F877F),
              ),
              child: const Text(
                'No me interesa',
                style: TextStyle(fontSize: AuraTipo.cuerpo, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitlistButton extends StatelessWidget {
  final bool enListaEspera;
  final int waitlistCount;

  /// Puesto exacto (1 = la próxima). null = no anotada, o la RPC no respondió.
  final int? miPosicion;
  final bool loading;
  final VoidCallback onTap;

  const _WaitlistButton({
    required this.enListaEspera,
    required this.waitlistCount,
    required this.miPosicion,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Anotada: el puesto exacto, que es lo único que le sirve saber
        // ("soy la 2 de 5" decide si espera o busca otra clase). Sin puesto
        // —no anotada, o la RPC no respondió— se muestra el conteo de antes.
        if (enListaEspera && miPosicion != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              miPosicion == 1
                  ? 'Sos la próxima: N° 1 de $waitlistCount en la lista'
                  : 'Sos la N° $miPosicion de $waitlistCount en la lista',
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: AuraTipo.secundario,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          )
        else if (waitlistCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '$waitlistCount ${waitlistCount == 1 ? 'persona' : 'personas'} esperando un lugar',
              style: const TextStyle(color: AppColors.grey, fontSize: AuraTipo.secundario),
              textAlign: TextAlign.center,
            ),
          ),
        SizedBox(
          height: 56,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: loading ? null : onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: enListaEspera
                  ? const Color(0xFFE65100)
                  : AppColors.primary,
              side: BorderSide(
                color: enListaEspera
                    ? const Color(0xFFE65100)
                    : AppColors.primary,
              ),
              backgroundColor: enListaEspera
                  ? const Color(0xFFFFF3E0)
                  : Colors.transparent,
            ),
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : Icon(
                    enListaEspera
                        ? Icons.notifications_off_outlined
                        : Icons.notifications_active_outlined,
                    size: 20,
                  ),
            label: Text(
              enListaEspera
                  ? 'Salir de la lista de espera'
                  : 'Anotarme a la lista de espera',
            ),
          ),
        ),
      ],
    );
  }
}

class _PolicyItem extends StatelessWidget {
  final String text;

  const _PolicyItem(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 6, color: Color(0xFF8F877F)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF6D6660),
                fontSize: AuraTipo.cuerpo,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// SOLO PARA TESTS: expone la hoja del paywall para poder medirla sin levantar
/// la pantalla de detalle entera (que necesita Supabase y el router). Mismo
/// criterio que `debugResultCard` y `debugHorariosPorDiaEditor`.
@visibleForTesting
Widget debugPaywallSheet({
  required int creditosNecesarios,
  required int creditosActuales,
  String volver = '/clase/1',
}) => _PaywallSheet(
  creditosNecesarios: creditosNecesarios,
  creditosActuales: creditosActuales,
  volver: volver,
);
