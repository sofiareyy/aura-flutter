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

import 'sentry_bots_stub.dart'
    if (dart.library.js_interop) 'sentry_bots_web.dart'
    as plataforma;

/// Los que se conocen. Todos en minúscula; la comparación también.
const List<String> kAgentesDeBots = [
  'facebookexternalhit', // el que disparó esto
  'facebookcatalog',
  'meta-externalagent',
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
