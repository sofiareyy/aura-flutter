// Qué errores NO van a Sentry (20/10/2026).
//
// El primer día con Sentry prendido, los dos únicos errores que llegaron eran
// del crawler de Facebook entrando a la portada: mismo Trace ID, 19 segundos
// de diferencia, IP 2a03:2880:30ff:2:: (Meta). Ejecuta JS a medias y Flutter
// revienta en ese entorno recortado.
//
// No rompe nada —medido: el crawler se lleva el HTML y todas las meta tags en
// 3.122 bytes, sin necesitar que la app renderice— pero si no se filtra, el
// día que una usuaria tenga un crash de verdad va a estar enterrado.
//
// La regla de oro acá es la asimetría: perder el error de una persona real es
// MUCHO peor que dejar pasar el de un bot. Por eso la lista es explícita y no
// una heurística, y ante la duda no filtra.

import 'package:aura_app/utils/sentry_bots.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  group('se filtran', () {
    test('el que disparó esto: el crawler de Facebook', () {
      expect(
        esBot(
          'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)',
        ),
        isTrue,
      );
    });

    test('los demás que comparten links', () {
      for (final ua in [
        'WhatsApp/2.23.20.0',
        'Twitterbot/1.0',
        'LinkedInBot/1.0',
        'TelegramBot (like TwitterBot)',
        'Slackbot-LinkExpanding 1.0',
        'Discordbot/2.0',
        'meta-externalagent/1.1',
      ]) {
        expect(esBot(ua), isTrue, reason: ua);
      }
    });

    test('los buscadores', () {
      for (final ua in [
        'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)',
        'Mozilla/5.0 (compatible; bingbot/2.0)',
        'Mozilla/5.0 (Macintosh) AppleWebKit/537.36 (KHTML, like Gecko) Version/17 Safari/537.36 Applebot/0.1',
      ]) {
        expect(esBot(ua), isTrue, reason: ua);
      }
    });

    test('las herramientas de medición, y mis propias capturas', () {
      // Lighthouse y PageSpeed entran con HeadlessChrome, igual que las
      // mediciones que corro yo desde puppeteer.
      expect(esBot('Mozilla/5.0 HeadlessChrome/155.0.0.0'), isTrue);
      expect(esBot('Chrome-Lighthouse'), isTrue);
    });

    test('no importa cómo esté escrito', () {
      expect(esBot('FacebookExternalHit/1.1'), isTrue);
      expect(esBot('GOOGLEBOT'), isTrue);
    });
  });

  group('NO se filtran: las personas', () {
    test('un iPhone', () {
      expect(
        esBot(
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
        ),
        isFalse,
      );
    });

    test('un Android', () {
      expect(
        esBot(
          'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/155.0.0.0 Mobile Safari/537.36',
        ),
        isFalse,
      );
    });

    test('Chrome y Safari de escritorio', () {
      for (final ua in [
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.3 Safari/605.1.15',
      ]) {
        expect(esBot(ua), isFalse, reason: ua);
      }
    });

    test('la app nativa, que no tiene user agent de navegador', () {
      // En iOS y Android `userAgentActual()` devuelve null.
      expect(esBot(null), isFalse);
      expect(esBot(''), isFalse);
      expect(esBot('Dart/3.11 (dart:io)'), isFalse);
    });
  });

  // 24/10/2026: Meta rota de disfraz (Edge, Chrome Mobile...), así que se
  // filtra por DÓNDE nace el error, no por el navegador.
  group('filtro por origen del error', () {
    SentryEvent evento(List<String?> archivos) => SentryEvent(
      exceptions: [
        SentryException(
          type: 'StateError',
          value: 'Bad state',
          stackTrace: SentryStackTrace(
            frames: [for (final a in archivos) SentryStackFrame(absPath: a)],
          ),
        ),
      ],
    );

    test('el caso real: el stack nace en inject_content.js de Meta', () {
      final e = evento([
        'https://somosaurapass.com/main.dart.js',
        'https://somosaurapass.com/main.dart.js',
        'inject_content.js',
      ]);
      expect(filtrarEvento(e, esWeb: true), isNull);
    });

    test('iabjs:// y extensiones del navegador también se descartan', () {
      for (final a in [
        'iabjs://navigation_performance.js',
        'chrome-extension://abcdef/content.js',
        'moz-extension://123/inject.js',
        'safari-web-extension://x/script.js',
      ]) {
        expect(
          filtrarEvento(
            evento(['https://somosaurapass.com/main.dart.js', a]),
            esWeb: true,
          ),
          isNull,
          reason: a,
        );
      }
    });

    test('un error nuestro SIEMPRE pasa', () {
      for (final a in [
        'https://somosaurapass.com/main.dart.js',
        'https://www.gstatic.com/flutter-canvaskit/abc/canvaskit.js',
        'https://somosaurapass.com/flutter_bootstrap.js',
        'org-dartlang-sdk:///lib/async/future_impl.dart',
        'package:aura_app/screens/auth/landing_screen.dart',
      ]) {
        final e = evento(['inject_content.js', a]);
        expect(filtrarEvento(e, esWeb: true), same(e), reason: a);
      }
    });

    test('se saltean los frames nativos para llegar al archivo real', () {
      final e = evento([
        'inject_content.js',
        'https://somosaurapass.com/main.dart.js',
        '<anonymous>',
        'native',
      ]);
      expect(filtrarEvento(e, esWeb: true), same(e));
    });

    test('ante la duda no se descarta: sin stack o sin archivos', () {
      final sinStack = SentryEvent(
        exceptions: [SentryException(type: 'StateError', value: 'x')],
      );
      expect(filtrarEvento(sinStack, esWeb: true), same(sinStack));
      final sinExcepcion = SentryEvent();
      expect(filtrarEvento(sinExcepcion, esWeb: true), same(sinExcepcion));
      final soloNativos = evento(['<anonymous>', 'native', null]);
      expect(filtrarEvento(soloNativos, esWeb: true), same(soloNativos));
    });

    test('en iOS y Android no se filtra nada', () {
      final e = evento(['inject_content.js']);
      expect(filtrarEvento(e, esWeb: false), same(e));
    });

    test('el revisor de anuncios de Meta por user agent', () {
      expect(esBot('meta-externalads/1.1'), isTrue);
    });
  });

  group('"Script error." de otro dominio', () {
    test('exacto y sin stack: se descarta', () {
      final e = SentryEvent(
        exceptions: [SentryException(type: 'Error', value: 'Script error.')],
      );
      expect(filtrarEvento(e, esWeb: true), isNull);
      final comoMensaje = SentryEvent(
        message: SentryMessage('Script error.'),
      );
      expect(filtrarEvento(comoMensaje, esWeb: true), isNull);
    });

    test('con stack nuestro, o con otro mensaje: pasa', () {
      final conStack = SentryEvent(
        exceptions: [
          SentryException(
            type: 'Error',
            value: 'Script error.',
            stackTrace: SentryStackTrace(
              frames: [
                SentryStackFrame(
                  absPath: 'https://somosaurapass.com/main.dart.js',
                ),
              ],
            ),
          ),
        ],
      );
      expect(filtrarEvento(conStack, esWeb: true), same(conStack));
      final otro = SentryEvent(
        exceptions: [
          SentryException(type: 'Error', value: 'Script error. en Perfil'),
        ],
      );
      expect(filtrarEvento(otro, esWeb: true), same(otro));
    });
  });
}
