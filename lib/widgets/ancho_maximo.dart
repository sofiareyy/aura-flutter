import 'package:flutter/material.dart';

import '../utils/grilla_responsive.dart';

/// Centra y limita el ancho del contenido de una pantalla.
///
/// El problema (6/9/2026): Inicio, Explorar y las dos pantallas de detalle ya
/// topaban su ancho, pero **el resto de la app no**. En un monitor de 1920 una
/// lista de reservas o el perfil se estiraban de lado a lado: renglones de
/// texto de 1900 px que el ojo no puede seguir, y tarjetas deformadas.
///
/// Va **dentro** del `body` del Scaffold, no envolviendo al Scaffold: así la
/// AppBar y el color de fondo siguen ocupando la pantalla entera y sólo se
/// centra el contenido. En un teléfono no cambia nada, porque el ancho
/// disponible siempre es menor que el tope.
class AnchoMaximo extends StatelessWidget {
  final Widget child;

  /// El tope. Por defecto el de las pantallas de detalle (1100), que es el
  /// mismo que ya usaban Explorar y los detalles.
  final double max;

  const AnchoMaximo({
    super.key,
    required this.child,
    this.max = anchoMaxDetalle,
  });

  /// Para pantallas de un solo paso (formularios, un login, un checkout):
  /// más angostas, porque son una tarjeta con un botón y no una página para
  /// recorrer.
  const AnchoMaximo.formulario({super.key, required this.child})
    : max = anchoMaxFormulario;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: max),
        child: child,
      ),
    );
  }
}
