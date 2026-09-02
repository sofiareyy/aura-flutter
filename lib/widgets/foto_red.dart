import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../utils/foto_url.dart';

/// Una foto de Storage servida en la medida que la tarjeta necesita.
///
/// Siempre con [BoxFit.cover]: RECORTA manteniendo la proporción, nunca
/// deforma. Una foto vertical de celular o una cuadrada entran igual en un
/// marco 16:9 o 3:2 —se ve la franja central— y no hay franjas blancas.
/// Es lo que permite que un estudio suba la foto como la tenga, sin editarla.
///
/// La red de seguridad: si la versión liviana falla —el endpoint de
/// transformaciones está documentado como feature de Pro y la organización
/// está en free— reintenta la URL ORIGINAL antes de rendirse al [fallback].
/// Peor caso: la app queda como antes de este cambio, nunca sin foto.
class FotoRed extends StatelessWidget {
  final String? url;

  /// Ancho de descarga en píxeles. ~2× el hueco en pantalla, para retina.
  final int ancho;

  /// Qué mostrar mientras carga y si no hay foto (o falla todo).
  final Widget fallback;

  const FotoRed({
    super.key,
    required this.url,
    required this.ancho,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final original = url;
    if (original == null || original.isEmpty) return fallback;

    final liviana = fotoOptimizada(original, ancho: ancho);
    if (liviana == null || liviana == original) return _crudo(original);

    return CachedNetworkImage(
      imageUrl: liviana,
      httpHeaders: headersFoto,
      fit: BoxFit.cover,
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => _crudo(original),
    );
  }

  Widget _crudo(String u) => CachedNetworkImage(
    imageUrl: u,
    fit: BoxFit.cover,
    placeholder: (_, __) => fallback,
    errorWidget: (_, __, ___) => fallback,
  );
}
