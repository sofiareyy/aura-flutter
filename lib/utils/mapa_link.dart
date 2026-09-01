import 'package:url_launcher/url_launcher.dart';

/// Abrir una dirección en la app de mapas del teléfono.
///
/// Mismo criterio que el mail de confirmación de reserva: si hay coordenadas
/// se usan (son exactas y no dependen de cómo esté escrita la calle), y si no
/// se busca por texto. Google Maps resuelve en las dos plataformas y, en un
/// iPhone con la app instalada, iOS abre Google Maps; si no, cae al navegador.
String mapaUrl({String? direccion, double? lat, double? lng}) {
  if (lat != null && lng != null && (lat != 0 || lng != 0)) {
    return 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
  }
  final q = Uri.encodeComponent((direccion ?? '').trim());
  return 'https://www.google.com/maps/search/?api=1&query=$q';
}

/// Abre el mapa. Devuelve false si el sistema no pudo abrir nada, para que
/// quien llama decida si avisar (nunca debería fallar: es un https común).
Future<bool> abrirMapa({String? direccion, double? lat, double? lng}) async {
  if ((direccion == null || direccion.trim().isEmpty) &&
      (lat == null || lng == null)) {
    return false;
  }
  try {
    return await launchUrl(
      Uri.parse(mapaUrl(direccion: direccion, lat: lat, lng: lng)),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}
