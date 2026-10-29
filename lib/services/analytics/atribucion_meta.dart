import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'analytics.dart';

/// Meta desde la app web (29/10/2026): el clic del anuncio y el registro.
///
/// 1. El clic. aura-analytics.js lo guarda en el navegador apenas se abre la
///    página; acá se lo asocia a la cuenta en cuanto hay sesión, para que los
///    eventos de servidor de la API de Conversiones (registro, inicio de
///    checkout, compra) puedan atribuirse al anuncio aunque la persona compre
///    días después o desde otra pestaña.
/// 2. El registro (CompleteRegistration). Va DESPUÉS del clic, así sale con
///    él. Lo decide el servidor (meta-capi-event): sólo cuentas de menos de 7
///    días, uno por cuenta, a la hora del alta. Acá sólo se evita pedirlo de
///    más: cuentas de menos de un día, una vez por carga.
///
/// Sólo web (decisión: por ahora sólo compras web). Nunca lanza: medir no
/// puede romper un login.
class AtribucionMeta {
  AtribucionMeta._();

  /// Lo último que se mandó en esta carga, para no repetir la ida a la base en
  /// cada evento de sesión (el listener se dispara varias veces).
  static String? _enviado;
  static String? _registroPedido;

  static Future<void> sincronizar() async {
    if (!kIsWeb) return;
    await _guardarClic();
    await _registro();
  }

  static Future<void> _guardarClic() async {
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

  static Future<void> _registro() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null || user.id == _registroPedido) return;
      final alta = DateTime.tryParse(user.createdAt);
      if (alta == null ||
          DateTime.now().toUtc().difference(alta.toUtc()) >
              const Duration(days: 1)) {
        return;
      }
      _registroPedido = user.id;
      await Supabase.instance.client.functions.invoke(
        'meta-capi-event',
        // Sin la URL de la página: tras entrar con Google lleva el código de
        // acceso. El servidor usa la del sitio.
        body: {'event_name': 'CompleteRegistration'},
      );
    } catch (e) {
      // Sin el token de Meta la función contesta 503 a propósito: el registro
      // quedó anotado y sale cuando se cargue. No es un error de la persona.
      debugPrint('[AtribucionMeta] registro: $e');
    }
  }
}
