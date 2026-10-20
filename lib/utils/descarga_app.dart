// Los botones de descarga de la portada (16/10/2026).
//
// Android salió a producción el 15/10, así que por primera vez las dos
// tiendas existen y la portada puede ofrecer las dos. Antes no se ofrecía
// ninguna en Android, para no mandar a nadie a una ficha que no estaba.
//
// La regla: se destaca la tienda del aparato desde el que están mirando, y la
// otra queda igual de disponible pero sin peso visual. En una compu no hay
// aparato que adivinar, así que van las dos iguales.
//
// Dentro de la app nativa no se muestra nada: ya la tienen instalada. Es el
// mismo criterio que `RegistroMuro.descargaPara`.

import 'package:flutter/foundation.dart' show TargetPlatform;

import '../core/constants/app_constants.dart';

enum Tienda { appStore, googlePlay }

class BotonTienda {
  final Tienda tienda;
  final String url;

  /// El nombre que se muestra.
  final String etiqueta;

  /// Si es la tienda del aparato desde el que están mirando. En una compu
  /// son las dos.
  final bool destacado;

  const BotonTienda({
    required this.tienda,
    required this.url,
    required this.etiqueta,
    required this.destacado,
  });
}

const _appStore = BotonTienda(
  tienda: Tienda.appStore,
  url: AppConstants.appStoreUrlLanding,
  etiqueta: 'App Store',
  destacado: true,
);
const _play = BotonTienda(
  tienda: Tienda.googlePlay,
  url: AppConstants.playStoreUrlLanding,
  etiqueta: 'Google Play',
  destacado: true,
);

BotonTienda _sinDestacar(BotonTienda b) => BotonTienda(
  tienda: b.tienda,
  url: b.url,
  etiqueta: b.etiqueta,
  destacado: false,
);

/// Qué tiendas mostrar en la portada, y cuál destacar.
///
/// Devuelve la destacada PRIMERO: el orden de la lista es el orden en que se
/// dibujan, así que en un iPhone App Store queda a la izquierda y en un
/// Android queda Google Play.
List<BotonTienda> tiendasParaLanding(
  TargetPlatform plataforma, {
  required bool esWeb,
  bool androidPublicado = AppConstants.androidPublicado,
}) {
  if (!esWeb) return const []; // ya está adentro de la app

  // Mientras Android no estuviera publicado, su botón no existía. Queda la
  // condición para que apagar el flag vuelva a esconderlo sin tocar nada más.
  if (!androidPublicado) {
    return plataforma == TargetPlatform.android ? const [] : const [_appStore];
  }

  return switch (plataforma) {
    TargetPlatform.iOS => [_appStore, _sinDestacar(_play)],
    TargetPlatform.android => [_play, _sinDestacar(_appStore)],
    // Compu: no hay aparato que adivinar, van las dos iguales.
    _ => const [_appStore, _play],
  };
}
