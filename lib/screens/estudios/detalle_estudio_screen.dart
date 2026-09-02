import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../utils/mapa_link.dart';
import '../../models/estudio.dart';
import '../../providers/app_provider.dart';
import '../../services/estudios_service.dart';
import '../../services/favoritos_service.dart';
import '../../services/reviews_service.dart';
import '../../widgets/clase_card.dart';
import '../../widgets/study_review_sheet.dart';
import '../../widgets/registro_muro.dart';

class DetalleEstudioScreen extends StatefulWidget {
  final int estudioId;
  const DetalleEstudioScreen({super.key, required this.estudioId});

  @override
  State<DetalleEstudioScreen> createState() => _DetalleEstudioScreenState();
}

class _DetalleEstudioScreenState extends State<DetalleEstudioScreen> {
  final _service = EstudiosService();
  final _favoritosService = FavoritosService();
  final _reviewsService = ReviewsService();
  Estudio? _estudio;
  static const int _clasesPreview = 5;
  static const int _reviewsPreview = 2;

  List<Map<String, dynamic>> _clases = [];
  /// Experiencias / workshops. Van en su propia sección: mezcladas con las
  /// clases quedaban detrás del preview de 5 y no se veían nunca.
  List<Map<String, dynamic>> _experiencias = [];
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;
  bool _esFavorito = false;
  bool _canReview = false;
  bool _verTodasLasClases = false;

  /// ¿Se muestra el bloque "CLASES DISPONIBLES"?
  ///
  /// Sí cuando hay clases. Y también cuando no hay NADA, para que el estudio
  /// vacío avise que no tiene nada.
  ///
  /// No cuando hay solo experiencias: ahí el título y el "no hay clases
  /// disponibles" quedaban como un cartel negativo al lado de las
  /// experiencias que el estudio sí publicó.
  bool get _mostrarBloqueClases =>
      _clases.isNotEmpty || _experiencias.isEmpty;

  @override
  void initState() {
    super.initState();
    _registrarVista().ignore();
    _cargar();
  }

  /// Registra una vista del perfil para las métricas del estudio (FIX 4).
  /// Fire-and-forget: nunca bloquea ni rompe la pantalla.
  Future<void> _registrarVista() async {
    try {
      final client = Supabase.instance.client;
      await client.from('estudio_vistas').insert({
        'estudio_id': widget.estudioId,
        'usuario_id': client.auth.currentUser?.id,
      });
    } catch (_) {}
  }

  Future<void> _cargar() async {
    final userId = context.read<AppProvider>().userId;
    // Abrir un estudio hacía 6 idas y vueltas EN SERIE. Medido el 24/8: el
    // servidor tarda 53 ms en el panel más pesado (Citra, 368 clases), pero
    // cada ida y vuelta a Supabase mide entre 150 ms y 1,6 s — muy variable.
    // Seis en serie son ~2 s, y con dos muestras lentas se va a 4 y pico. Por
    // eso "antes era más rápido" dependía del momento, no del código.
    // Sólo `getEstudio` tiene que ir primero (las otras necesitan su id); las
    // cinco que siguen no dependen entre sí, así que pasan de sumarse a costar
    // lo que la más lenta.
    final estudio = await _service.getEstudio(widget.estudioId);
    final estudioId = estudio?.id;

    final resultados = await Future.wait([
      estudioId != null
          ? _service.getClasesDeEstudio(estudioId)
          : Future.value(<Map<String, dynamic>>[]),
      estudioId != null
          ? _service.getExperienciasDeEstudio(estudioId)
          : Future.value(<Map<String, dynamic>>[]),
      estudioId != null && userId.isNotEmpty
          ? _favoritosService.esFavorito(userId, estudioId)
          : Future.value(false),
      estudioId != null
          ? _reviewsService.getReviewsForStudy(estudioId)
          : Future.value(<Map<String, dynamic>>[]),
      estudioId != null && userId.isNotEmpty
          ? _reviewsService.canReviewStudy(estudioId: estudioId)
          : Future.value(false),
    ]);
    final clasesRaw = resultados[0] as List<Map<String, dynamic>>;
    final experienciasRaw = resultados[1] as List<Map<String, dynamic>>;
    final esFavorito = resultados[2] as bool;
    final reviews = resultados[3] as List<Map<String, dynamic>>;
    final canReview = resultados[4] as bool;

    // Adjuntar datos del estudio a cada clase para que ClaseCard muestre imagen
    final estudioMap = estudio != null
        ? {
            'id': estudio.id,
            'nombre': estudio.nombre,
            'foto_url': estudio.fotoUrl,
            'barrio': estudio.barrio,
            'categoria': estudio.categoria,
          }
        : null;
    final clases = estudioMap != null
        ? clasesRaw.map((c) => {...c, 'estudios': estudioMap}).toList()
        : clasesRaw;
    final experiencias = estudioMap != null
        ? experienciasRaw.map((c) => {...c, 'estudios': estudioMap}).toList()
        : experienciasRaw;

    if (mounted) {
      setState(() {
        _estudio = estudio;
        _clases = clases;
        _experiencias = experiencias;
        _esFavorito = esFavorito;
        _reviews = reviews;
        _canReview = canReview;
        _loading = false;
      });
    }
  }

  Future<void> _abrirResena({String? experienciaLabel, int? claseId}) async {
    final estudio = _estudio;
    if (estudio?.id == null) return;
    final saved = await StudyReviewSheet.show(
      context,
      estudioId: estudio!.id!,
      estudioNombre: estudio.nombre,
      claseId: claseId,
      experienciaLabel: experienciaLabel,
    );
    if (saved == true) {
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tu reseña quedó guardada.'),
          backgroundColor: AppColors.blackSoft,
        ),
      );
    }
  }

  Future<void> _toggleFavorito() async {
    final estudioId = _estudio?.id;
    final userId = context.read<AppProvider>().userId;
    if (estudioId == null || userId.isEmpty) return;

    final nuevoValor = !_esFavorito;
    setState(() => _esFavorito = nuevoValor);
    try {
      await _favoritosService.toggleFavorito(
        usuarioId: userId,
        estudioId: estudioId,
        favorito: nuevoValor,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nuevoValor
                ? 'Estudio agregado a favoritos.'
                : 'Estudio quitado de favoritos.',
          ),
          backgroundColor: AppColors.blackSoft,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _esFavorito = !nuevoValor);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _estudio == null
              ? const Center(child: Text('Estudio no encontrado'))
              : _buildContent(),
    );
  }

  void _verTodasLasResenas() {
    final e = _estudio;
    if (e?.id == null) return;
    context.push(
      '/estudio/${e!.id}/resenas?nombre=${Uri.encodeComponent(e.nombre)}',
    );
  }

  Widget _buildContent() {
    final e = _estudio!;
    final avgRating = _reviews.isEmpty
        ? e.rating
        : _reviews
                .map((item) => (item['rating'] as num?)?.toDouble() ?? 0)
                .reduce((a, b) => a + b) /
            _reviews.length;
    // Galería del estudio: solo las fotos del lugar (foto principal + fotos
    // que el estudio cargó para mostrar el espacio). Las galerías de cada
    // clase se ven en la pantalla de detalle de esa clase.
    final galleryUrls = <String>{
      if ((e.fotoUrl ?? '').trim().isNotEmpty) e.fotoUrl!.trim(),
      ...e.galeriaUrls
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty),
    }.toList();

    return CustomScrollView(
      slivers: [
        // Hero fijo 300px
        SliverToBoxAdapter(child: _buildHero()),

        // Cuerpo
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rating: tocarlo abre TODAS las reseñas. Antes era texto
                // muerto, y las reseñas ayudan a decidir la reserva.
                if (avgRating != null)
                  InkWell(
                    onTap: _reviews.isEmpty ? null : _verTodasLasResenas,
                    child: Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: AppColors.warning, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          avgRating.toStringAsFixed(1),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        if (_reviews.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${_reviews.length} reseñas',
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              size: 16, color: AppColors.primary),
                        ],
                      ],
                    ),
                  ),

                // Descripción
                if (e.descripcion?.isNotEmpty == true) ...[
                  const SizedBox(height: 16),
                  Text(
                    e.descripcion!,
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.grey, height: 1.5),
                  ),
                ],

                // Dirección con pin naranja
                if (e.direccion?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.place_rounded,
                          color: AppColors.primary, size: 16),
                      const SizedBox(width: 6),
                      // Tocar la dirección abre el mapa. Acá SÍ hay lat/lng
                      // del estudio, así que la ubicación es exacta y no
                      // depende de cómo esté escrita la calle.
                      Expanded(
                        child: InkWell(
                          onTap: () => abrirMapa(
                            direccion: e.direccion,
                            lat: e.lat,
                            lng: e.lng,
                          ),
                          child: Text(
                            e.direccion!,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // Botones sociales (solo si tienen datos)
                if (_hasSocial(e)) ...[
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (e.instagram?.isNotEmpty == true)
                        _SocialButton(
                          icon: Icons.photo_camera_outlined,
                          label: 'Instagram',
                          onTap: () => _launchInstagram(e.instagram!),
                        ),
                      if (e.whatsapp?.isNotEmpty == true)
                        _SocialButton(
                          icon: Icons.chat_outlined,
                          label: 'WhatsApp',
                          onTap: () => _launchWhatsApp(e.whatsapp!),
                        ),
                      if (e.web?.isNotEmpty == true)
                        _SocialButton(
                          icon: Icons.language_outlined,
                          label: 'Web',
                          onTap: () => _launchUrl(e.web!),
                        ),
                    ],
                  ),
                ],

                // Galería arriba (si hay fotos)
                if (galleryUrls.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _GallerySection(
                    imageUrls: galleryUrls,
                    onTapImage: (index) =>
                        _abrirGaleria(galleryUrls, initialIndex: index),
                  ),
                ],

                // ── Experiencias / eventos ──────────────────────────────
                // Sección propia, ANTES de las clases: son pocas, puntuales y
                // se publican con anticipación. Mezcladas con la grilla
                // semanal quedaban detrás del preview y no se veían.
                if (_experiencias.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  const Text(
                    'EXPERIENCIAS',
                    style: TextStyle(
                      color: Color(0xFF8F877F),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._experiencias.map(
                    (exp) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ClaseCard(
                        clase: exp,
                        showEstudio: false,
                        onTap: () => context.push('/clase/${exp['id']}'),
                      ),
                    ),
                  ),
                ],

                // Encabezado clases + Ver más.
                // Si el estudio no tiene clases regulares pero sí experiencias,
                // no mostramos ni el título ni el "no hay clases": quedaba un
                // cartel negativo justo al lado de las experiencias que sí
                // tiene. El vacío real (ni clases ni experiencias) sí se avisa.
                if (_mostrarBloqueClases) ...[
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'CLASES DISPONIBLES',
                          style: TextStyle(
                            color: Color(0xFF8F877F),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      if (_clases.length > _clasesPreview)
                        GestureDetector(
                          onTap: () => setState(
                            () => _verTodasLasClases = !_verTodasLasClases,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Text(
                              _verTodasLasClases ? 'Ver menos' : 'Ver más',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),

        // Cards de clases (preview o todas). El mensaje de vacío solo sale
        // cuando el estudio no tiene NADA que mostrar; si tiene experiencias,
        // el bloque entero se oculta (ver _mostrarBloqueClases).
        if (_clases.isEmpty)
          _mostrarBloqueClases
              ? const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'No hay clases disponibles por ahora.',
                      style: TextStyle(color: AppColors.grey, fontSize: 14),
                    ),
                  ),
                )
              : const SliverToBoxAdapter(child: SizedBox.shrink())
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClaseCard(
                  clase: _clases[i],
                  showEstudio: false,
                  onTap: () => context.push('/clase/${_clases[i]['id']}'),
                ),
              ),
              childCount: _verTodasLasClases
                  ? _clases.length
                  : (_clases.length > _clasesPreview
                      ? _clasesPreview
                      : _clases.length),
            ),
          ),

        // Reseñas al final
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
            child: _ReviewsSection(
              // El bloque del perfil NO cambia: siguen apareciendo acá las
              // primeras reseñas, como siempre. Lo único distinto es que
              // "Ver más" ahora NAVEGA a la pantalla completa en vez de
              // expandir inline — con 100 reseñas expandir es inusable.
              reviews: _reviews.take(_reviewsPreview).toList(),
              totalCount: _reviews.length,
              expandido: false,
              canReview: _canReview,
              onReviewTap: () => _abrirResena(),
              onToggleExpand: _reviews.length > _reviewsPreview
                  ? _verTodasLasResenas
                  : null,
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _buildHero() {
    final e = _estudio!;
    return SizedBox(
      height: 300,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Foto
          e.fotoUrl?.isNotEmpty == true
              ? _RemoteImage(
                  url: e.fotoUrl!,
                  fit: BoxFit.cover,
                  placeholder: Container(color: const Color(0xFFEDE7E1)),
                  errorWidget: Container(
                    color: AppColors.primaryLight,
                    child: const Icon(Icons.fitness_center_rounded,
                        color: AppColors.primary, size: 48),
                  ),
                )
              : Container(
                  color: AppColors.primaryLight,
                  child: const Center(
                    child: Icon(Icons.fitness_center_rounded,
                        color: AppColors.primary, size: 48),
                  ),
                ),

          // Gradiente negro → transparente (bottom → top)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Color(0xD9000000), // negro 0.85
                  Color(0x4D000000), // negro 0.3
                  Colors.transparent,
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // Categoría + nombre + barrio (abajo izquierda)
          Positioned(
            left: 16,
            right: 60,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    e.categoria,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  e.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (e.barrio?.isNotEmpty == true)
                  Text(
                    e.barrio!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),

          // Flecha de volver (arriba izquierda)
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 10, left: 16),
                child: _EstudioCircleAction(
                  icon: Icons.arrow_back,
                  onTap: () => context.pop(),
                ),
              ),
            ),
          ),

          // Favorito (arriba derecha). Al invitado TAMBIEN se le muestra —
          // si lo ocultamos, no sabe que la función existe. Al tocarlo abre
          // el muro cerrable en vez de guardar.
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 10, right: 16),
                child: _EstudioCircleAction(
                  icon: _esFavorito
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  onTap: Supabase.instance.client.auth.currentUser == null
                      ? () => RegistroMuro.mostrar(
                            context,
                            motivo: MuroMotivo.favorito,
                          )
                      : _toggleFavorito,
                  iconColor:
                      _esFavorito ? AppColors.primary : Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasSocial(Estudio e) =>
      (e.instagram?.isNotEmpty == true) ||
      (e.whatsapp?.isNotEmpty == true) ||
      (e.web?.isNotEmpty == true);

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
                      child: _RemoteImage(
                        url: imageUrls[index],
                        fit: BoxFit.contain,
                        errorWidget: const Icon(
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

  Future<void> _launchInstagram(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      await _launchUrl(trimmed);
      return;
    }

    final handle = trimmed.replaceFirst('@', '');
    await _launchUrl('https://instagram.com/$handle');
  }

  Future<void> _launchWhatsApp(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      await _launchUrl(trimmed);
      return;
    }

    final phone = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    await _launchUrl('https://wa.me/$phone');
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    final launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el enlace'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

class _EstudioCircleAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color iconColor;

  const _EstudioCircleAction({
    required this.icon,
    this.onTap,
    this.iconColor = Colors.white,
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
        child: Icon(icon, color: iconColor, size: 20),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SocialButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(color: AppColors.lightGrey),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppColors.black),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _GallerySection extends StatelessWidget {
  final List<String> imageUrls;
  final ValueChanged<int> onTapImage;

  const _GallerySection({
    required this.imageUrls,
    required this.onTapImage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Galería del estudio', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: imageUrls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) => InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onTapImage(index),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 124,
                  child: _RemoteImage(
                    url: imageUrls[index],
                    fit: BoxFit.cover,
                    errorWidget: Container(
                      color: const Color(0xFFF3EEE8),
                      child: const Icon(Icons.image_not_supported_outlined, color: AppColors.grey),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewsSection extends StatelessWidget {
  final List<Map<String, dynamic>> reviews;
  final int totalCount;
  final bool expandido;
  final bool canReview;
  final VoidCallback onReviewTap;
  final VoidCallback? onToggleExpand;

  const _ReviewsSection({
    required this.reviews,
    required this.totalCount,
    required this.expandido,
    required this.canReview,
    required this.onReviewTap,
    this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  totalCount > 0 ? 'Reseñas ($totalCount)' : 'Reseñas del estudio',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (canReview)
                TextButton(
                  onPressed: onReviewTap,
                  child: const Text('Dejar reseña'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (reviews.isEmpty)
            Text(
              canReview
                  ? 'Todavía no hay opiniones. Podés ser la primera persona en reseñar este estudio.'
                  : 'Las reseñas se habilitan cuando ya viviste una experiencia en este estudio.',
              style: const TextStyle(
                color: AppColors.grey,
                fontSize: 14,
                height: 1.5,
              ),
            )
          else ...[
            ...reviews.map(
              (review) => Padding(
                padding: const EdgeInsets.only(top: 14),
                child: _ReviewCard(review: review),
              ),
            ),
            if (onToggleExpand != null) ...[
              const SizedBox(height: 12),
              Center(
                child: GestureDetector(
                  onTap: onToggleExpand,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    child: Text(
                      expandido
                          ? 'Ver menos'
                          // Navega a la pantalla completa: con muchas reseñas
                          // expandir inline no sirve.
                          : 'Ver las $totalCount reseñas',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;

  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final usuario = review['usuarios'] as Map<String, dynamic>?;
    final nombre = usuario?['nombre']?.toString().trim();
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final experiencia = review['experiencia_label']?.toString().trim() ?? '';
    final comentario = review['comentario']?.toString().trim() ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8F5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primaryLight,
                child: Text(
                  (nombre?.isNotEmpty == true ? nombre![0] : 'A').toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre?.isNotEmpty == true ? nombre! : 'Usuario Aura',
                      style: const TextStyle(
                        color: AppColors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (experiencia.isNotEmpty)
                      Text(
                        'Experiencia: $experiencia',
                        style: const TextStyle(
                          color: AppColors.grey,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                children: List.generate(
                  5,
                  (index) => Icon(
                    index < rating ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          if (comentario.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              comentario,
              style: const TextStyle(
                color: Color(0xFF5E5853),
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Imagen remota que en web usa Image.network (evita issues con
/// CachedNetworkImage en navegadores) y en mobile usa CachedNetworkImage
/// para tener cache local.
class _RemoteImage extends StatelessWidget {
  final String url;
  final BoxFit? fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const _RemoteImage({
    required this.url,
    this.fit,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(
        url,
        fit: fit,
        loadingBuilder: (ctx, child, progress) =>
            progress == null ? child : (placeholder ?? const SizedBox.shrink()),
        errorBuilder: (ctx, _, __) =>
            errorWidget ?? const SizedBox.shrink(),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      placeholder: placeholder == null ? null : (_, __) => placeholder!,
      errorWidget:
          errorWidget == null ? null : (_, __, ___) => errorWidget!,
    );
  }
}

