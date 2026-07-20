import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Selector de múltiples categorías para un estudio (FEATURE 5).
///
/// Un estudio puede ser Pilates + Barre + Yoga a la vez, así que reemplaza al
/// dropdown de selección única. Se usa tanto en el backoffice de Aura como en
/// el panel del estudio.
class CategoriasChecklist extends StatelessWidget {
  /// Catálogo disponible. Puede venir con 'Todos' adelante (es el formato que
  /// devuelve `EstudiosService.getCategorias`); se filtra acá.
  final List<String> disponibles;

  final List<String> seleccionadas;

  /// `(categoria, quedaMarcada)`.
  final void Function(String categoria, bool marcada) onToggle;

  final String label;

  const CategoriasChecklist({
    super.key,
    required this.disponibles,
    required this.seleccionadas,
    required this.onToggle,
    this.label = 'Categorías',
  });

  @override
  Widget build(BuildContext context) {
    final opciones =
        disponibles.where((c) => c.isNotEmpty && c != 'Todos').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.grey,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: opciones.map((cat) {
            final marcada = seleccionadas.contains(cat);
            return FilterChip(
              label: Text(cat),
              selected: marcada,
              onSelected: (value) => onToggle(cat, value),
              showCheckmark: true,
              selectedColor: AppColors.primary.withValues(alpha: 0.15),
              checkmarkColor: AppColors.primary,
              labelStyle: TextStyle(
                color: marcada ? AppColors.primary : AppColors.black,
                fontSize: 13,
                fontWeight: marcada ? FontWeight.w600 : FontWeight.w400,
              ),
              side: BorderSide(
                color: marcada
                    ? AppColors.primary
                    : const Color(0xFFEDE7E1),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            );
          }).toList(),
        ),
        if (seleccionadas.isEmpty) ...[
          const SizedBox(height: 6),
          const Text(
            'Elegí al menos una.',
            style: TextStyle(color: AppColors.grey, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
