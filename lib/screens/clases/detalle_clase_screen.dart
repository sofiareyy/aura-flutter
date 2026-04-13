import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../services/aura_gestion_service.dart';
import '../../services/clases_service.dart';
import '../../services/reservas_service.dart';
import '../../services/reviews_service.dart';
import '../../services/waitlist_service.dart';
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
  List<Map<String, dynamic>> _reviews = [];

  @override
  void initState() {
    super.initState();
    _cargar();
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
      final estudioId = ((clase?['estudios'] as Map<String, dynamic>?)?['id'] as num?)
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
      final userEmail =
          Supabase.instance.client.auth.currentUser?.email ?? '';

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
      ]);

      final esGratuita = futures[0] as bool;
      final enListaEspera = futures[1] as bool;
      final waitlistCount = futures[2] as int;

      if (!mounted) return;
      setState(() {
        _clase = clase;
        _yaReservado = yaReservado;
        _canReview = canReview;
        _reviews = reviews;
        _esGratuita = esGratuita;
        _enListaEspera = enListaEspera;
        _waitlistCount = waitlistCount;
        _loading = false;
      });
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
    final cierreMinutos =
        (_clase!['reserva_cierre_minutos'] as num?)?.toInt() ?? 0;
    if (fecha != null &&
        ReservasService.reservaCerrada(fecha, cierreMinutos)) {
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

    final lugaresDisp =
        (_clase!['lugares_ disponibles'] ?? _clase!['lugares_disponibles'] ?? 0)
            as num;
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
      final conflicto = await _verificarConflicto(provider.userId, fecha, duracion);
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
  Future<String?> _verificarConflicto(String userId, DateTime fecha, int duracion) async {
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PaywallSheet(
        creditosNecesarios: creditosNecesarios,
        creditosActuales: creditosActuales,
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
        });
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Te quitaste de la lista de espera.'),
            backgroundColor: AppColors.blackSoft,
          ),
        );
      } else {
        await _waitlistService.join(widget.claseId, userId);
        if (!mounted) return;
        setState(() {
          _enListaEspera = true;
          _waitlistCount = _waitlistCount + 1;
        });
        messenger.showSnackBar(
          const SnackBar(
            content: Text('¡Anotado! Te avisamos si se libera un lugar.'),
            backgroundColor: AppColors.blackSoft,
            duration: Duration(seconds: 4),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
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
    final cierreMinutos =
        (clase['reserva_cierre_minutos'] as num?)?.toInt() ?? 0;
    final reservaCerrada = fecha != null &&
        ReservasService.reservaCerrada(fecha, cierreMinutos);
    final lugaresDisp =
        (clase['lugares_ disponibles'] ?? clase['lugares_disponibles'] ?? 0)
            as num;
    final creditos = (clase['creditos'] as num?)?.toInt() ?? 1;
    final creditosSaldo = context.watch<AppProvider>().usuario?.creditos ?? 0;
    final disponible = lugaresDisp > 0 && !_yaReservado && !reservaCerrada;
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

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: 300,
                width: double.infinity,
                child: Stack(
                  children: [
                    // Imagen hero — altura fija, recortada
                    Positioned.fill(
                      child: _HeroImage(
                        imageUrl: (clase['imagen_url'] ?? estudio?['foto_url'])
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
                          padding: const EdgeInsets.only(top: 10, left: 16),
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
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              categoria,
                              style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 12,
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
                                ? () => context.push('/estudio/${estudio!['id']}')
                                : null,
                            child: Text(
                              '$estudioNombre - $barrio',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 15,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white.withValues(alpha: 0.85),
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
            SliverToBoxAdapter(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Rating
                      Row(
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
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            reviewCount == 0
                                ? 'Sin reseñas todavía'
                                : '$reviewCount reseñas',
                            style: const TextStyle(
                              color: AppColors.grey,
                              fontSize: 13,
                            ),
                          ),
                        ],
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
                              onTap: () => context.push('/estudio/${estudio!['id']}'),
                            ),
                            _HeaderActionPill(
                              icon: Icons.map_outlined,
                              label: 'Ver en mapa',
                              onTap: () {
                                final uri = Uri(
                                  path: '/mapa',
                                  queryParameters: {
                                    if ((estudio?['categoria'] ?? '').toString().isNotEmpty)
                                      'categoria': estudio!['categoria'].toString(),
                                    if ((estudio?['nombre'] ?? '').toString().isNotEmpty)
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
                          borderRadius: BorderRadius.circular(20),
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
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Sos alumno/a de este estudio',
                                          style: TextStyle(
                                            color: Color(0xFFA7A09A),
                                            fontSize: 13,
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  RichText(
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '$creditos',
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 38,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const TextSpan(
                                          text: ' créditos',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
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
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 54,
                              margin: const EdgeInsets.symmetric(horizontal: 16),
                              color: const Color(0x26FFFFFF),
                            ),
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Tu saldo',
                                    style: TextStyle(
                                      color: Color(0xFFA7A09A),
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '$creditosSaldo créditos',
                                    style: const TextStyle(
                                      color: AppColors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Quedan ${creditosSaldo - creditos} tras reservar',
                                    style: const TextStyle(
                                      color: Color(0xFFA7A09A),
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () => _abrirGaleria(galleryUrls, initialIndex: index),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: SizedBox(
                                          width: 120,
                                          child: CachedNetworkImage(
                                            imageUrl: imageUrl,
                                            fit: BoxFit.cover,
                                            errorWidget: (_, __, ___) => Container(
                                              color: const Color(0xFFF3EEE8),
                                              child: const Icon(
                                                Icons.image_not_supported_outlined,
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
                      if ((clase['incluye']?.toString().trim() ?? '').isNotEmpty)
                        Column(
                          children: [
                            _SectionBlock(
                              title: 'Qué incluye',
                              child: Text(
                                clase['incluye'].toString(),
                                style: const TextStyle(
                                  color: Color(0xFF5E584F),
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                        ),
                      if ((clase['instructor']?.toString().trim() ?? '').isNotEmpty)
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
                                  _initials(clase['instructor']?.toString() ?? 'MR'),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    clase['instructor']?.toString() ?? '',
                                    style: const TextStyle(
                                      color: AppColors.black,
                                      fontSize: 16,
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
                                        fontSize: 13,
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
                      if ((clase['instructor']?.toString().trim() ?? '').isNotEmpty)
                        const SizedBox(height: 18),
                      _SectionBlock(
                        title: 'Política de cancelación',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            _PolicyItem(
                              'Cancelación gratuita hasta 12 horas antes de la clase.',
                            ),
                            _PolicyItem(
                              'Cancelaciones tardías o no-shows consumen los créditos completos.',
                            ),
                            _PolicyItem(
                              'Los créditos no son reembolsables una vez consumidos.',
                            ),
                          ],
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
                            fontSize: 15,
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
          child: lugaresDisp <= 0 && !_yaReservado && !reservaCerrada
              ? _WaitlistButton(
                  enListaEspera: _enListaEspera,
                  waitlistCount: _waitlistCount,
                  loading: _togglingWaitlist,
                  onTap: _toggleListaEspera,
                )
              : SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _yaReservado ? null : !disponible ? null : _irAConfirmar,
                    child: Text(
                      _yaReservado
                          ? 'Ya reservada'
                          : !disponible
                              ? (reservaCerrada ? 'Reservas cerradas' : 'Sin lugares')
                              : _esGratuita
                                  ? 'Reservar gratis'
                                  : 'Reservar · $creditos créditos',
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _abrirGaleria(List<String> imageUrls, {int initialIndex = 0}) async {
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
                  onPageChanged: (value) => setDialogState(() => currentIndex = value),
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
                      fontSize: 14,
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

  const _CircleAction({
    required this.icon,
    this.onTap,
  });

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

  const _InfoChipCard({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 164),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
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
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricPanel extends StatelessWidget {
  final String value;
  final String caption;
  final Color accent;

  const _MetricPanel({
    required this.value,
    required this.caption,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final isPrimary = accent == AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isPrimary
            ? Colors.white.withOpacity(0.03)
            : Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPrimary
              ? Colors.white.withOpacity(0.05)
              : Colors.white.withOpacity(0.03),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isPrimary)
            Text(
              caption == 'Tu saldo actual' ? 'Tu saldo' : caption,
              style: const TextStyle(
                color: Color(0xFFA7A09A),
                fontSize: 13,
              ),
            ),
          if (!isPrimary) const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: isPrimary ? 22 : 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (isPrimary) ...[
            const SizedBox(height: 6),
            Text(
              caption,
              style: const TextStyle(
                color: Color(0xFFA7A09A),
                fontSize: 13,
              ),
            ),
          ] else ...[
            const SizedBox(height: 6),
            const Text(
              'Quedan disponibles tras reservar',
              style: TextStyle(
                color: Color(0xFFA7A09A),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionBlock({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
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
              fontSize: 16,
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

class _CheckItem extends StatelessWidget {
  final String text;

  const _CheckItem(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 13, color: AppColors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF625C57),
                fontSize: 15,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaywallSheet extends StatelessWidget {
  final int creditosNecesarios;
  final int creditosActuales;
  const _PaywallSheet({required this.creditosNecesarios, required this.creditosActuales});

  @override
  Widget build(BuildContext context) {
    final faltan = creditosNecesarios - creditosActuales;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF7F5F2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: const Color(0xFFCCC5BD), borderRadius: BorderRadius.circular(99)),
          ),
          Container(
            width: 60, height: 60,
            decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
            child: const Icon(Icons.star_outline_rounded, color: AppColors.primary, size: 30),
          ),
          const SizedBox(height: 14),
          const Text(
            'Créditos insuficientes',
            style: TextStyle(color: AppColors.black, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Esta clase requiere $creditosNecesarios crédito${creditosNecesarios != 1 ? 's' : ''}.\n'
            'Tenés $creditosActuales — te faltan $faltan.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8F877F), fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                context.push('/comprar-creditos');
              },
              child: const Text('Comprar créditos'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: () {
                Navigator.pop(context);
                context.push('/comprar-creditos');
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
              child: const Text('Comprar créditos'),
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
          borderRadius: BorderRadius.circular(999),
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

class _WaitlistButton extends StatelessWidget {
  final bool enListaEspera;
  final int waitlistCount;
  final bool loading;
  final VoidCallback onTap;

  const _WaitlistButton({
    required this.enListaEspera,
    required this.waitlistCount,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (waitlistCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '$waitlistCount ${waitlistCount == 1 ? 'persona' : 'personas'} esperando un lugar',
              style: const TextStyle(color: AppColors.grey, fontSize: 12),
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
                fontSize: 15,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}



