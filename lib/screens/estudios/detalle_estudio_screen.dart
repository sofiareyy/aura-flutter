import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../models/estudio.dart';
import '../../providers/app_provider.dart';
import '../../services/estudios_service.dart';
import '../../services/favoritos_service.dart';
import '../../services/reviews_service.dart';
import '../../widgets/clase_card.dart';
import '../../widgets/study_review_sheet.dart';

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
  List<Map<String, dynamic>> _clases = [];
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;
  bool _esFavorito = false;
  bool _canReview = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final estudio = await _service.getEstudio(widget.estudioId);
    final clasesRaw = estudio != null && estudio.id != null
        ? await _service.getClasesDeEstudio(estudio.id!)
        : <Map<String, dynamic>>[];

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
    final userId = context.read<AppProvider>().userId;
    final esFavorito = estudio?.id != null && userId.isNotEmpty
        ? await _favoritosService.esFavorito(userId, estudio!.id!)
        : false;
    final reviews = estudio?.id != null
        ? await _reviewsService.getReviewsForStudy(estudio!.id!)
        : <Map<String, dynamic>>[];
    final canReview = estudio?.id != null && userId.isNotEmpty
        ? await _reviewsService.canReviewStudy(estudioId: estudio!.id!)
        : false;

    if (mounted) {
      setState(() {
        _estudio = estudio;
        _clases = clases;
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

  Widget _buildContent() {
    final e = _estudio!;
    final avgRating = _reviews.isEmpty
        ? e.rating
        : _reviews
                .map((item) => (item['rating'] as num?)?.toDouble() ?? 0)
                .reduce((a, b) => a + b) /
            _reviews.length;
    final galleryUrls = <String>{
      if ((e.fotoUrl ?? '').trim().isNotEmpty) e.fotoUrl!.trim(),
      ..._clases
          .map((item) => item['imagen_url']?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty),
      ..._clases
          .expand((item) => ((item['galeria_urls'] as List?) ?? const [])
              .map((entry) => entry.toString().trim()))
          .where((item) => item.isNotEmpty),
    }.toList();
    return CustomScrollView(
      slivers: [
        // Header image
        SliverAppBar(
          expandedHeight: 260,
          pinned: true,
          backgroundColor: AppColors.background,
          leading: Padding(
            padding: const EdgeInsets.all(8),
            child: CircleAvatar(
              backgroundColor: AppColors.white.withOpacity(0.9),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.black, size: 20),
                onPressed: () => context.pop(),
              ),
            ),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: e.fotoUrl != null
                ? CachedNetworkImage(
                    imageUrl: e.fotoUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: AppColors.lightGrey),
                    errorWidget: (_, __, ___) =>
                        Container(color: AppColors.lightGrey),
                  )
                : Container(
                    color: AppColors.primaryLight,
                    child: const Center(
                      child: Icon(Icons.fitness_center_rounded,
                          color: AppColors.primary, size: 48),
                    ),
                  ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name & category
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.nombre,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: _toggleFavorito,
                      icon: Icon(
                        _esFavorito
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: _esFavorito
                            ? AppColors.primary
                            : AppColors.grey,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        e.categoria,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Rating & location
                Row(
                  children: [
                    if (avgRating != null) ...[
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
                          '(${_reviews.length})',
                          style: const TextStyle(
                            color: AppColors.grey,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(width: 12),
                    ],
                    if (e.barrio != null) ...[
                      const Icon(Icons.location_on_outlined,
                          color: AppColors.grey, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        e.barrio!,
                        style: const TextStyle(
                            color: AppColors.grey, fontSize: 14),
                      ),
                    ],
                  ],
                ),

                if (e.descripcion != null) ...[
                  const SizedBox(height: 16),
                  Text(e.descripcion!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.grey)),
                ],

                if (e.direccion != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.place_outlined,
                          color: AppColors.grey, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(e.direccion!,
                            style: const TextStyle(
                                color: AppColors.grey, fontSize: 13)),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 20),

                // Social links
                if (e.instagram != null ||
                    e.whatsapp != null ||
                    e.web != null)
                  Row(
                    children: [
                      if (e.instagram != null)
                        _SocialButton(
                          icon: Icons.photo_camera_outlined,
                          label: 'Instagram',
                          onTap: () => _launchInstagram(e.instagram!),
                        ),
                      if (e.whatsapp != null) ...[
                        const SizedBox(width: 8),
                        _SocialButton(
                          icon: Icons.chat_outlined,
                          label: 'WhatsApp',
                          onTap: () => _launchWhatsApp(e.whatsapp!),
                        ),
                      ],
                      if (e.web != null) ...[
                        const SizedBox(width: 8),
                        _SocialButton(
                          icon: Icons.language_outlined,
                          label: 'Web',
                          onTap: () => _launchUrl(e.web!),
                        ),
                      ],
                    ],
                  ),

                if (galleryUrls.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _GallerySection(
                    imageUrls: galleryUrls,
                    onTapImage: (index) => _abrirGaleria(galleryUrls, initialIndex: index),
                  ),
                ],
                const SizedBox(height: 28),
                _ReviewsSection(
                  reviews: _reviews,
                  canReview: _canReview,
                  onReviewTap: () => _abrirResena(),
                ),
                const SizedBox(height: 28),
                Text('Clases disponibles',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),

        if (_clases.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Center(
                child: Text('No hay clases disponibles',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.grey)),
              ),
            ),
          )
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
              childCount: _clases.length,
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
                  child: CachedNetworkImage(
                    imageUrl: imageUrls[index],
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
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
  final bool canReview;
  final VoidCallback onReviewTap;

  const _ReviewsSection({
    required this.reviews,
    required this.canReview,
    required this.onReviewTap,
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
                  'Reseñas del estudio',
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
          else
            ...reviews.take(4).map(
                  (review) => Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _ReviewCard(review: review),
                  ),
                ),
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

