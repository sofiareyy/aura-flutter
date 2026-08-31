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

  /// Servicios de precio fijo del estudio: `{categoría → créditos}`. Las que
  /// están acá se dibujan con el precio adentro (`Sauna · 14 cr`) y un ícono,
  /// para que el estudio vea ANTES de elegir que ese precio no es por franja.
  /// Vacío (el default) ⇒ los chips se ven exactamente como siempre.
  final Map<String, int> precios;

  const CategoriasChecklist({
    super.key,
    required this.disponibles,
    required this.seleccionadas,
    required this.onToggle,
    this.label = 'Categorías',
    this.precios = const {},
  });

  /// Texto del chip: la categoría, o `categoría · N cr` si es un servicio.
  String etiquetaDe(String cat) {
    final precio = precios[cat];
    return precio == null ? cat : '$cat · $precio cr';
  }

  /// Aplica un toggle sobre [seleccionadas] respetando la REGLA A (30/8):
  /// un servicio de precio fijo es la ÚNICA categoría de la clase.
  ///
  /// - Tildar un servicio destilda todo lo demás.
  /// - Tildar una común con un servicio tildado destilda el servicio.
  /// - Tope de [max] categorías (espejo del trigger `sync_categorias_clase`).
  ///
  /// La base rechaza la mezcla de todos modos (`servicio_precio_fijo`); esto
  /// es la UX para que el estudio nunca vea ese error.
  static void aplicarToggle(
    List<String> seleccionadas,
    String categoria,
    bool marcada, {
    required Map<String, int> precios,
    int max = 5,
  }) {
    if (!marcada) {
      seleccionadas.remove(categoria);
      return;
    }
    if (precios.containsKey(categoria)) {
      // Un servicio va solo.
      seleccionadas.clear();
    } else {
      // Una común echa al servicio que hubiera.
      seleccionadas.removeWhere(precios.containsKey);
      if (seleccionadas.length >= max) return;
    }
    if (!seleccionadas.contains(categoria)) seleccionadas.add(categoria);
  }

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
            final esServicio = precios.containsKey(cat);
            return FilterChip(
              label: Text(etiquetaDe(cat)),
              // El ícono de etiqueta de precio distingue al servicio del
              // resto aun sin leer el número. Sólo cuando NO está marcado:
              // marcado ya lleva el tilde adelante.
              avatar: esServicio && !marcada
                  ? const Icon(Icons.sell_outlined,
                      size: 16, color: AppColors.primary)
                  : null,
              selected: marcada,
              onSelected: (value) => onToggle(cat, value),
              showCheckmark: true,
              selectedColor: AppColors.primary.withValues(alpha: 0.15),
              checkmarkColor: AppColors.primary,
              labelStyle: TextStyle(
                color: marcada || esServicio
                    ? AppColors.primary
                    : AppColors.black,
                fontSize: 13,
                fontWeight:
                    marcada || esServicio ? FontWeight.w600 : FontWeight.w400,
              ),
              side: BorderSide(
                color: marcada || esServicio
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
