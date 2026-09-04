import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/aura_tokens.dart';

/// Un texto largo que se muestra recortado con un "Ver más".
///
/// El caso que lo pidió (4/9/2026): un estudio mandó una descripción larga y en
/// la app quedaba una pared de texto. Medido contra producción, no es un caso
/// aislado ni el peor: la descripción de Yoguica tiene **986 caracteres y 13
/// saltos de línea**, y la del workshop "Rito del Útero Munay Ki" tiene
/// **1484** — arriba de 35 renglones en un teléfono.
///
/// Dos decisiones que hacen que esto no moleste cuando no hace falta:
///
///  - **El "Ver más" aparece SÓLO si el texto realmente no entra.** Se mide con
///    un `TextPainter` contra el ancho real disponible, no se adivina por
///    cantidad de caracteres. Las descripciones cortas —que son la mayoría: 4
///    de los 12 estudios activos tienen menos de 160— se ven enteras y sin
///    ningún adorno, igual que antes.
///  - **Una vez abierto se puede volver a cerrar** ("Ver menos"): si alguien
///    expandió los 1484 caracteres del workshop, tiene que poder plegarlo sin
///    salir y volver a entrar.
class TextoExpandible extends StatefulWidget {
  final String texto;
  final TextStyle? estilo;

  /// Cuántos renglones se ven plegado. Sofía pidió "3 o 4"; 4 deja respirar sin
  /// dejar de ser un resumen.
  final int renglones;

  const TextoExpandible(
    this.texto, {
    super.key,
    this.estilo,
    this.renglones = 4,
  });

  @override
  State<TextoExpandible> createState() => _TextoExpandibleState();
}

class _TextoExpandibleState extends State<TextoExpandible> {
  bool _abierto = false;

  @override
  Widget build(BuildContext context) {
    final estilo =
        widget.estilo ??
        const TextStyle(
          fontSize: AuraTipo.cuerpo,
          color: AppColors.textoSecundario,
          height: 1.5,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        // ¿Entra en `renglones`? Se mide el texto real contra el ancho real.
        final painter = TextPainter(
          text: TextSpan(text: widget.texto, style: estilo),
          maxLines: widget.renglones,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final desborda = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.texto,
              style: estilo,
              maxLines: _abierto || !desborda ? null : widget.renglones,
              overflow: _abierto || !desborda
                  ? TextOverflow.clip
                  : TextOverflow.ellipsis,
            ),
            if (desborda)
              Padding(
                padding: const EdgeInsets.only(top: AuraEspacio.s),
                child: GestureDetector(
                  onTap: () => setState(() => _abierto = !_abierto),
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    _abierto ? 'Ver menos' : 'Ver más',
                    style: const TextStyle(
                      // El mismo naranja legible que el "Ver todo" de las
                      // secciones. `primary` como texto da 2,96:1.
                      color: AppColors.primaryTexto,
                      fontSize: AuraTipo.secundario,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
