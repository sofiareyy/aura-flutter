import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme/app_theme.dart';
import '../models/estudio.dart';

class EstudioCard extends StatelessWidget {
  final Estudio estudio;
  final VoidCallback onTap;
  final bool featured;

  const EstudioCard({
    super.key,
    required this.estudio,
    required this.onTap,
    this.featured = false,
  });

  @override
  Widget build(BuildContext context) {
    if (featured) return _buildFeatured();
    return _buildCompact();
  }

  Widget _buildFeatured() {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 260,
        height: 180,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppColors.lightGrey,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildImage(),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: _buildCategoriaBadge(),
              ),
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      estudio.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (estudio.barrio != null) ...[
                          const Icon(Icons.location_on_outlined,
                              color: AppColors.white, size: 12),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              estudio.barrio!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.white, fontSize: 11),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (estudio.rating != null) ...[
                          const Icon(Icons.star_rounded,
                              color: AppColors.warning, size: 12),
                          const SizedBox(width: 2),
                          Text(
                            estudio.rating!.toStringAsFixed(1),
                            style: const TextStyle(
                                color: AppColors.white, fontSize: 11),
                          ),
                        ],
                      ],
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

  Widget _buildCompact() {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 70,
                height: 70,
                child: _buildImage(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    estudio.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (estudio.barrio != null)
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            color: AppColors.grey, size: 13),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            estudio.barrio!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.grey, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  if (estudio.rating != null)
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: AppColors.warning, size: 13),
                        const SizedBox(width: 2),
                        Text(
                          estudio.rating!.toStringAsFixed(1),
                          style: const TextStyle(
                              color: AppColors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            _buildCategoriaBadge(),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (estudio.fotoUrl != null && estudio.fotoUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: estudio.fotoUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: AppColors.lightGrey),
        errorWidget: (_, __, ___) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.primaryLight,
      child: const Center(
        child: Icon(Icons.fitness_center_rounded,
            color: AppColors.primary, size: 24),
      ),
    );
  }

  Widget _buildCategoriaBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        estudio.categoria,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
