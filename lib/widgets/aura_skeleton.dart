// El esqueleto de carga de Aura.
//
// Sale de `AuraShimmerBox`, que ya existía en el sistema del estudio y sólo
// usaban 3 lugares de una pantalla de gestión. La auditoría de diseño encontró
// que la alumna nunca lo veía: sus 9 pantallas tenían 18 spinners sueltos y
// CERO esqueletos, y en el Inicio dos secciones directamente DESAPARECÍAN
// mientras cargaban y reaparecían de golpe.
//
// Por qué importa para vender: un círculo girando en un hueco no dice nada; una
// silueta con la forma de lo que viene dice "ya está llegando" y hace que la
// app se sienta rápida y cuidada. Es de lo que más rápido separa "pro" de
// "amateur", y el componente ya estaba escrito.

import 'package:flutter/material.dart';

import '../core/theme/aura_tokens.dart';

/// Una pieza gris que late, con la forma del contenido que va a llegar.
class AuraSkeleton extends StatefulWidget {
  final double height;
  final double? width;
  final BorderRadius borderRadius;

  const AuraSkeleton({
    super.key,
    required this.height,
    this.width,
    BorderRadius? borderRadius,
  }) : borderRadius =
           borderRadius ??
           const BorderRadius.all(Radius.circular(AuraRadio.chip));

  /// Un renglón de texto. [ancho] como fracción del ancho disponible, para que
  /// las líneas no queden todas iguales y parezca un párrafo de verdad.
  factory AuraSkeleton.renglon({double alto = 12, double? ancho}) =>
      AuraSkeleton(
        height: alto,
        width: ancho,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      );

  @override
  State<AuraSkeleton> createState() => _AuraSkeletonState();
}

class _AuraSkeletonState extends State<AuraSkeleton>
    with SingleTickerProviderStateMixin {
  // Los mismos tonos y el mismo ritmo que ya usaba el sistema del estudio.
  static const Color _base = Color(0xFFF0EDE8);
  static const Color _brillo = Color(0xFFE8E5E0);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(-1 + (2 * _controller.value), 0),
            end: Alignment(1 + (2 * _controller.value), 0),
            colors: const [_base, _brillo, _base],
            stops: const [0.1, 0.3, 0.4],
          ).createShader(bounds),
          blendMode: BlendMode.srcATop,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: _base,
              borderRadius: widget.borderRadius,
            ),
          ),
        );
      },
    );
  }
}

/// La silueta de una tarjeta de la vidriera: foto arriba, dos renglones abajo.
///
/// Es la forma que tiene `HomeNearbyClassCard`, para que al llegar el contenido
/// no salte nada de lugar.
class AuraSkeletonTarjetaVidriera extends StatelessWidget {
  final double ancho;
  final double altoFoto;

  const AuraSkeletonTarjetaVidriera({
    super.key,
    this.ancho = 320,
    this.altoFoto = 180,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ancho,
      margin: const EdgeInsets.only(right: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AuraRadio.rTarjeta,
        border: Border.all(color: const Color(0x248A8A8A)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuraSkeleton(
            height: altoFoto,
            width: double.infinity,
            borderRadius: BorderRadius.zero,
          ),
          Padding(
            padding: const EdgeInsets.all(AuraEspacio.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AuraSkeleton.renglon(alto: 10, ancho: ancho * 0.28),
                const SizedBox(height: AuraEspacio.s),
                AuraSkeleton.renglon(alto: 15, ancho: ancho * 0.62),
                const SizedBox(height: AuraEspacio.s),
                AuraSkeleton.renglon(alto: 12, ancho: ancho * 0.45),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Una fila de siluetas de tarjeta, para los carruseles horizontales.
class AuraSkeletonCarrusel extends StatelessWidget {
  final double alto;
  final double anchoTarjeta;
  final double altoFoto;
  final int cantidad;

  const AuraSkeletonCarrusel({
    super.key,
    required this.alto,
    this.anchoTarjeta = 320,
    this.altoFoto = 180,
    this.cantidad = 3,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: alto,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(left: AuraEspacio.margen),
        itemCount: cantidad,
        itemBuilder: (context, index) => AuraSkeletonTarjetaVidriera(
          ancho: anchoTarjeta,
          altoFoto: altoFoto,
        ),
      ),
    );
  }
}
