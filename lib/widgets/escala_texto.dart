import 'package:flutter/material.dart';

/// El tope del escalado de texto de toda la app.
///
/// **Por qué existe** (9/9/2026): la mamá de Sofía tiene la letra del sistema
/// agrandada, y con ese ajuste la app se rompía: los textos se salían de las
/// tarjetas. Medido renderizando los widgets reales, la tarjeta de clase
/// empezaba a desbordar con **x1.05** — el primer clic de "letra más grande",
/// sin entrar siquiera a Accesibilidad.
///
/// **Qué hace y qué NO hace.** La app sigue respetando el ajuste del sistema:
/// si la usuaria agranda la letra, la letra crece. Lo único que hace este tope
/// es no dejar que crezca más allá de 1,5x. iOS llega hasta ~3,1x, y a esa
/// escala una sola tarjeta mediría más que la pantalla entera: técnicamente no
/// se rompe, pero es inusable.
///
/// **No reemplaza al arreglo de fondo.** Las tarjetas también pasaron de alto
/// FIJO a alto MÍNIMO, para que crezcan con el texto en vez de cortarlo. El
/// tope es el techo; los altos flexibles son lo que hace que hasta ese techo
/// nada se desborde.
const double kMaxEscalaTexto = 1.5;

/// Aplica [kMaxEscalaTexto] a todo lo que cuelgue debajo.
///
/// Va una sola vez, en el `builder` del MaterialApp: no hay que acordarse de
/// ponerlo pantalla por pantalla, y una pantalla nueva lo hereda sola.
class EscalaTextoAcotada extends StatelessWidget {
  final Widget child;

  const EscalaTextoAcotada({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      // `clamp` respeta lo que pidió la usuaria hasta el tope. Con la letra en
      // normal (1.0) esto no cambia absolutamente nada.
      data: mq.copyWith(
        textScaler: mq.textScaler.clamp(maxScaleFactor: kMaxEscalaTexto),
      ),
      child: child,
    );
  }
}
