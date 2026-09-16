// Compartir un texto desde la app, con el portapapeles como red de seguridad.
//
// El bug (relevado el 16/9/2026): el código anterior llamaba a `Share.share` y
// copiaba al portapapeles sólo si la llamada LANZABA. Pero share_plus 10.1.4
// no lanza cuando el navegador no tiene la Web Share API: se traga el error,
// abre un `mailto:` silencioso y devuelve OK
// (share_plus-10.1.4/lib/src/share_plus_web.dart:91-125), y encima
// url_launcher_web devuelve `true` para `mailto:` casi siempre. Resultado: el
// `catch` nunca corría, el portapapeles era código muerto y el botón quedaba
// mudo en Firefox, en Chrome sobre Linux, en Safari viejo y en localhost.
//
// Acá se pregunta ANTES si se puede compartir, y si no se puede se copia.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'compartir_stub.dart'
    if (dart.library.js_interop) 'compartir_web.dart' as plataforma;

/// El texto que se comparte de una clase. Función pura para poder testearlo.
String textoCompartirClase({
  required String nombre,
  String? estudio,
  String? cuando,
  required String link,
}) {
  final partes = <String>[
    estudio != null && estudio.trim().isNotEmpty
        ? '$nombre en ${estudio.trim()}'
        : nombre,
    if (cuando != null && cuando.trim().isNotEmpty) cuando.trim(),
    'Reservá en Aura 🧡',
    link,
  ];
  return partes.join('\n');
}

/// El rectángulo del widget que disparó el compartir. En iPad y en Mac el menú
/// es un globo anclado a algo: sin esto, share_plus tira `PlatformException`.
Rect? origenDe(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Abre el menú de compartir. `false` si este dispositivo no puede compartir
/// (ahí hay que caer al portapapeles).
Future<bool> compartirTexto(String texto, {Rect? origen}) async {
  if (!plataforma.hayCompartirNativo()) return false;
  try {
    await Share.share(texto, sharePositionOrigin: origen);
    return true;
  } catch (_) {
    return false;
  }
}

/// Comparte y, si no se puede, copia al portapapeles y lo avisa. Nadie se
/// queda sin el link.
Future<void> compartirOCopiar(
  BuildContext context,
  String texto, {
  String avisoCopiado = 'Link copiado: pegalo donde quieras 🧡',
}) async {
  final origen = origenDe(context);
  if (await compartirTexto(texto, origen: origen)) return;

  await Clipboard.setData(ClipboardData(text: texto));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(avisoCopiado)),
  );
}
