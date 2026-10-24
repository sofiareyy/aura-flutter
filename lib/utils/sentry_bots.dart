// Los errores de los crawlers no van a Sentry (20/10/2026).
//
// EL CASO QUE LO PIDIÓ. El primer día con Sentry prendido llegaron dos
// errores "unhandled, fatal" de la portada: `StateError: Bad state: Future
// already completed` y un `Illegal invocation` minificado. Los dos
// compartían Trace ID, con 19 segundos de diferencia, y la IP
// `2a03:2880:30ff:2::` es de **Meta**: era el crawler de Facebook entrando a
// la web, no una usuaria.
//
// El crawler ejecuta JS a medias y Flutter revienta en ese entorno recortado.
// No rompe nada: medido, el crawler se lleva el HTML y todas las meta tags en
// 3.122 bytes sin necesitar que la app renderice, así que la vista previa del
// link sale igual.
//
// POR QUÉ FILTRARLO IGUAL. Porque entierra lo real. Si el bot entra seguido,
// el dashboard se llena de esto y el día que una usuaria tenga un crash de
// verdad va a estar sepultado entre ruido — además de gastar la cuota del
// plan gratis.
//
// Se filtra por user agent y sólo en web: en iOS y Android no hay crawlers.

import 'package:sentry_flutter/sentry_flutter.dart';

import 'sentry_bots_stub.dart'
    if (dart.library.js_interop) 'sentry_bots_web.dart'
    as plataforma;

/// Los que se conocen. Todos en minúscula; la comparación también.
const List<String> kAgentesDeBots = [
  'facebookexternalhit', // el que disparó esto
  'facebookcatalog',
  'meta-externalagent',
  'meta-externalads', // el que revisa los anuncios
  'twitterbot',
  'whatsapp',
  'linkedinbot',
  'telegrambot',
  'slackbot',
  'discordbot',
  'googlebot',
  'bingbot',
  'applebot',
  'yandexbot',
  'duckduckbot',
  'baiduspider',
  'petalbot',
  'ahrefsbot',
  'semrushbot',
  'headlesschrome', // Lighthouse, PageSpeed y mis propias mediciones
  'lighthouse',
  'chrome-lighthouse',
  'bot/',
  'crawler',
  'spider',
];

/// ¿Este user agent es un crawler?
///
/// Ante la duda, NO filtra: perder el error de una usuaria real es mucho peor
/// que dejar pasar el de un bot. Por eso la lista es explícita y no una
/// heurística.
bool esBot(String? userAgent) {
  if (userAgent == null || userAgent.isEmpty) return false;
  final ua = userAgent.toLowerCase();
  return kAgentesDeBots.any(ua.contains);
}

/// ¿El error que está por mandarse lo tuvo un crawler?
///
/// En iOS y Android devuelve siempre false: no hay user agent que mirar y no
/// hay crawlers. La decisión vive acá y no en `main.dart` para poder
/// probarla.
bool errorDeBot() => esBot(plataforma.userAgentActual());

// ── Filtro por ORIGEN del error (24/10/2026) ─────────────────────────────────
//
// El filtro por user agent no alcanza: el revisor de anuncios de Meta entra
// desde 2a03:2880 (sus datacenters) disfrazado de Edge, de Chrome Mobile o de
// lo que toque, con los UTMs de la campaña. Lo que no puede disfrazar es DÓNDE
// nace el error: el último evento trajo el stack arrancando en
// `inject_content.js`, un script que inyecta Meta, no código nuestro.
//
// Regla: se mira el archivo del frame donde se produjo el error (el más
// interno). Si es nuestro, va a Sentry. Si es de otro (scripts inyectados,
// `iabjs://`, extensiones del navegador), se descarta y se cuenta.
//
// Misma asimetría que arriba: SIN stack, o sin archivo identificable, NO se
// descarta. Sólo se tira lo que se puede probar que no es nuestro.

/// Nuestros archivos: la app compilada, el motor de Flutter y nuestros
/// scripts. Se compara por nombre de archivo, no por dominio: un script
/// inyectado puede figurar con la URL de la página.
const List<String> kArchivosNuestros = [
  'main.dart.js',
  'main.dart.mjs',
  'main.dart.wasm',
  'flutter.js',
  'flutter_bootstrap.js',
  'flutter_service_worker.js',
  'canvaskit', // motor de render de Flutter web (canvaskit.js / .wasm)
  'skwasm',
  'aura-analytics.js',
  'org-dartlang-sdk', // frames de Dart ya simbolizados
  'package:',
  'dart:',
];

/// Marcas que no son un archivo: código nativo del navegador o funciones
/// anónimas. Se saltean para llegar al primer frame con archivo de verdad.
const List<String> _sinArchivo = ['', '<anonymous>', 'native', '[native code]'];

/// El archivo donde nació el error, o null si no se puede saber.
///
/// Sentry ordena los frames del más viejo al más nuevo: el que tiró el error
/// es el ÚLTIMO.
String? archivoDeOrigen(List<String?> archivosDelStack) {
  for (final a in archivosDelStack.reversed) {
    final limpio = a?.trim() ?? '';
    if (_sinArchivo.contains(limpio.toLowerCase())) continue;
    return limpio;
  }
  return null;
}

/// ¿Este archivo es de otro? null o desconocido → false (no se descarta).
bool esArchivoAjeno(String? archivo) {
  if (archivo == null || archivo.isEmpty) return false;
  final a = archivo.toLowerCase();
  return !kArchivosNuestros.any(a.contains);
}

/// Los archivos del stack del error principal del evento, en el orden de
/// Sentry (del más viejo al más nuevo).
List<String?> archivosDelEvento(SentryEvent event) {
  final excepciones = event.exceptions;
  if (excepciones == null || excepciones.isEmpty) return const [];
  final frames = excepciones.last.stackTrace?.frames ?? const [];
  return [for (final f in frames) f.absPath ?? f.fileName];
}

/// La decisión completa, para `beforeSend`. Devuelve el evento, o null si se
/// descarta (y en ese caso lo cuenta).
///
/// Sólo en web: en iOS y Android los frames son `package:` y no hay scripts
/// inyectados.
SentryEvent? filtrarEvento(SentryEvent event, {required bool esWeb}) {
  if (!esWeb) return event;
  if (errorDeBot()) {
    plataforma.registrarDescarte('user_agent', '');
    return null;
  }
  final origen = archivoDeOrigen(archivosDelEvento(event));
  if (esArchivoAjeno(origen)) {
    plataforma.registrarDescarte('origen_ajeno', origen!);
    return null;
  }
  return event;
}
