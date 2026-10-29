import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'analytics.dart';

/// Guarda en la base el clic de Meta con el que llegó la persona (29/10/2026).
///
/// aura-analytics.js lo guarda en el navegador apenas se abre la página. Acá
/// se lo asocia a la cuenta en cuanto hay sesión, para que los eventos de
/// servidor de la API de Conversiones (registro, inicio de checkout, compra)
/// puedan atribuirse al anuncio aunque la persona compre días después o desde
/// otra pestaña.
///
/// Sólo web (decisión: por ahora sólo compras web). Nunca lanza: medir no
/// puede romper un login.
class AtribucionMeta {
  AtribucionMeta._();

  /// Lo último que se mandó en esta carga, para no repetir la ida a la base en
  /// cada evento de sesión (el listener se dispara varias veces).
  static String? _enviado;

  static Future<void> sincronizar() async {
    if (!kIsWeb) return;
    try {
      final fbc = Analytics.fbc();
      if (fbc == null || fbc == _enviado) return;
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return;
      await client.rpc('guardar_fbc', params: {'p_fbc': fbc});
      _enviado = fbc;
    } catch (e) {
      debugPrint('[AtribucionMeta] no se pudo guardar el clic: $e');
    }
  }
}
