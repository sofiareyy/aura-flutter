import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/theme/app_theme.dart';

class ClaseCard extends StatelessWidget {
  final Map<String, dynamic> clase;
  final VoidCallback onTap;
  final bool showEstudio;

  const ClaseCard({
    super.key,
    required this.clase,
    required this.onTap,
    this.showEstudio = true,
  });

  @override
  Widget build(BuildContext context) {
    final fecha = clase['fecha'] != null
        ? DateTime.tryParse(clase['fecha'].toString())
        : null;
    final estudio = clase['estudios'] as Map<String, dynamic>?;
    final imageUrl = (clase['imagen_url'] ?? estudio?['foto_url'])?.toString();
    final lugaresDisp =
        (clase['lugares_ disponibles'] ?? clase['lugares_disponibles'] ?? 0)
            as num;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _ClaseImage(imageUrl: imageUrl),
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: Container(
                            margin: const EdgeInsets.all(6),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  fecha != null ? DateFormat('dd').format(fecha) : '--',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                    height: 1,
                                  ),
                                ),
                                Text(
                                  fecha != null
                                      ? DateFormat('MMM', 'es').format(fecha).toUpperCase()
                                      : '--',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                    height: 1.1,
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
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clase['nombre'] ?? 'Clase',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.black,
                        ),
                      ),
                      if (showEstudio && estudio != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          estudio['nombre'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.grey,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (fecha != null) ...[
                            const Icon(Icons.access_time_rounded,
                                size: 13, color: AppColors.grey),
                            const SizedBox(width: 3),
                            Text(
                              DateFormat('HH:mm').format(fecha),
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.grey),
                            ),
                            const SizedBox(width: 10),
                          ],
                          if (clase['duracion_min'] != null) ...[
                            const Icon(Icons.timer_outlined,
                                size: 13, color: AppColors.grey),
                            const SizedBox(width: 3),
                            Text(
                              '${clase['duracion_min']} min',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.grey),
                            ),
                            const SizedBox(width: 10),
                          ],
                          if (lugaresDisp > 0)
                            Text(
                              '$lugaresDisp lugares',
                              style: TextStyle(
                                fontSize: 12,
                                color: lugaresDisp < 5
                                    ? AppColors.error
                                    : AppColors.success,
                                fontWeight: FontWeight.w500,
                              ),
                            )
                          else
                            const Text(
                              'Completa',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (clase['creditos'] != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Text(
                      '${clase['creditos']} cr',
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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

class _ClaseImage extends StatelessWidget {
  final String? imageUrl;

  const _ClaseImage({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imageUrl!,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _fallback(),
        placeholder: (_, __) => _fallback(),
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
          colors: [Color(0xFFD4AE76), Color(0xFFEFE2D0)],
        ),
      ),
    );
  }
}
