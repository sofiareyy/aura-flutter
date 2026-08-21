import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Force-update: decide si la versión instalada quedó por debajo de la mínima
/// que exige el servidor, y hay que mandar a la pantalla de actualización.
///
/// La versión mínima vive en `configuracion_global` (lectura pública, escritura
/// solo admins), en las claves `min_build_ios` / `min_build_android`, como el
/// **build number** entero. Comparar enteros es a prueba de balas; parsear el
/// string de versión ("1.0.6") es frágil.
///
/// **Fail-open por construcción**: SOLO devuelve `true` (bloquear) cuando pudo
/// leer con éxito una mínima y el build instalado es menor. Cualquier duda
/// —web, error de red, fila ausente, valor ilegible, build no parseable— cae en
/// `false`, para que una caída del servidor jamás deje a todo el mundo trabado.
class VersionGate {
  const VersionGate._();

  /// Tope de tiempo del chequeo. El splash lo espera con `await`, así que este
  /// timeout es lo que garantiza que una red LENTA (no caída, colgada) no
  /// demore el arranque: al vencer, devuelve `false` (no bloquea) y la app
  /// sigue. Con la red caída ni se llega acá (la query falla antes).
  static const Duration _timeout = Duration(seconds: 4);

  static Future<bool> hayQueActualizar() async {
    // La web nunca se fuerza a actualizar: se sirve siempre la última desde
    // somosaurapass.com. Guarda #1.
    if (kIsWeb) return false;

    try {
      return await _chequear().timeout(_timeout, onTimeout: () => false);
    } catch (_) {
      // Red caída, timeout, cualquier error: NO bloquear a nadie.
      return false;
    }
  }

  static Future<bool> _chequear() async {
    final info = await PackageInfo.fromPlatform();
    final instalado = int.tryParse(info.buildNumber.trim());
    if (instalado == null) return false; // build no parseable → no bloquea

    final clave = Platform.isIOS ? 'min_build_ios' : 'min_build_android';
    final res = await Supabase.instance.client
        .from('configuracion_global')
        .select('valor')
        .eq('clave', clave)
        .maybeSingle();

    final minimo = int.tryParse(res?['valor']?.toString().trim() ?? '');
    if (minimo == null) return false; // fila ausente/ilegible → no bloquea

    return instalado < minimo;
  }
}
