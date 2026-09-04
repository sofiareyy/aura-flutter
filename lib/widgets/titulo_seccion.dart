import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/aura_tokens.dart';

/// El encabezado de una sección, uno solo para toda la app.
///
/// Nació en el Inicio (4/9/2026), donde las 7 secciones traían cada una su
/// propio padding de arriba (0, 22, 24, 26) y su propio estilo de texto. Se
/// mudó acá cuando Explorar necesitó los mismos tres encabezados: tenía el
/// título en #403A35 sin tracking y el "Ver todo" en `primary`, o sea el mismo
/// gris y el mismo problema de contraste que el Inicio ya había resuelto.
///
/// Si un tercer lugar necesita un encabezado de sección, usa éste.
class TituloSeccion extends StatelessWidget {
  final String titulo;

  /// El texto del link de la derecha. Sin él, no se dibuja.
  final String? accion;
  final VoidCallback? onAccion;

  /// La primera sección después de otra cosa necesita el aire de separación;
  /// una que va pegada a la anterior, no.
  final bool separar;

  /// Si la pantalla ya pone el margen lateral (Explorar lo pone en el padding
  /// del ListView), el encabezado no tiene que volver a ponerlo o queda con
  /// doble sangría.
  final bool margenLateral;

  const TituloSeccion(
    this.titulo, {
    super.key,
    this.accion,
    this.onAccion,
    this.separar = true,
    this.margenLateral = true,
  });

  @override
  Widget build(BuildContext context) {
    final lateral = margenLateral ? AuraEspacio.margen : 0.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        lateral,
        separar ? AuraEspacio.seccion : 0,
        lateral,
        AuraEspacio.tituloAContenido,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              titulo,
              style: AuraTipo.estiloEtiqueta.copyWith(
                color: AppColors.textoSecundario,
              ),
            ),
          ),
          if (accion != null)
            GestureDetector(
              onTap: onAccion,
              child: Text(
                accion!,
                style: const TextStyle(
                  // `primary` como texto da 2,96:1 y no se leía.
                  color: AppColors.primaryTexto,
                  fontWeight: FontWeight.w600,
                  fontSize: AuraTipo.secundario,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
