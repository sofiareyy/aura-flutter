import 'package:shared_preferences/shared_preferences.dart';

/// Los códigos que alguien escribió al REGISTRARSE (gift card y referido) y
/// que no se pudieron aplicar en el momento porque el registro quedó sin
/// sesión: mail pendiente de validar.
///
/// El agujero que tapa (10/9/2026): `_register()` canjeaba el regalo y
/// vinculaba el referido DESPUÉS del `return` de la rama "revisá tu mail". Con
/// la validación de mail apagada en Supabase nunca se notó, porque `signUp`
/// siempre devuelve sesión. El día que se prenda, los dos códigos se perderían
/// en silencio: la persona escribió su gift card, validó el mail, entró… y
/// nadie le acreditó nada.
///
/// No alcanza con mover el canje de lugar: `canjear_regalo` valida contra
/// `auth.uid()`, y sin sesión no hay uid. Hay que DIFERIR: se guardan acá y
/// los consume el primer login exitoso — el listener de `onAuthStateChange`
/// en `main.dart`, que corre para cualquier método de entrada.
///
/// **La regla de seguridad, en un solo lugar:** los códigos van atados al MAIL
/// con el que se escribieron, y al consumir sólo se devuelven si la sesión es
/// de ese mismo mail. Si alguien se registra en un celular y no confirma, y
/// después entra OTRA persona en ese mismo dispositivo, el código no puede
/// terminar acreditado en la cuenta equivocada: se descarta.
class CodigosPendientes {
  CodigosPendientes._();

  static const _claveMail = 'codigos_pendientes_mail';
  static const _claveRegalo = 'codigos_pendientes_regalo';
  static const _claveReferido = 'codigos_pendientes_referido';

  /// Trim + minúsculas. El mail de la sesión lo devuelve Supabase tal como se
  /// registró, pero el del formulario lo tipeó una persona: "Vale@Gmail.com "
  /// y "vale@gmail.com" tienen que ser la misma cuenta.
  static String normalizarMail(String? mail) =>
      (mail ?? '').trim().toLowerCase();

  /// Guarda los códigos atados al mail. Devuelve `true` si quedó algo guardado
  /// (para que el registro pueda avisar "tu código se aplica cuando entres").
  ///
  /// Sin mail o sin ningún código no guarda nada, y además BORRA lo que
  /// hubiera: un registro nuevo no tiene por qué heredar los códigos de un
  /// intento anterior que quedó a medias.
  static Future<bool> recordar({
    required String? mail,
    String? regalo,
    String? referido,
  }) async {
    final m = normalizarMail(mail);
    final r = (regalo ?? '').trim();
    final f = (referido ?? '').trim();
    final prefs = await SharedPreferences.getInstance();
    if (m.isEmpty || (r.isEmpty && f.isEmpty)) {
      await _borrar(prefs);
      return false;
    }
    await prefs.setString(_claveMail, m);
    if (r.isEmpty) {
      await prefs.remove(_claveRegalo);
    } else {
      await prefs.setString(_claveRegalo, r);
    }
    if (f.isEmpty) {
      await prefs.remove(_claveReferido);
    } else {
      await prefs.setString(_claveReferido, f);
    }
    return true;
  }

  /// Lee y BORRA (de un solo uso), igual que `DestinoPostLogin.tomar()`. Se
  /// borra SIEMPRE, coincida el mail o no: si no coincide, los códigos se
  /// descartan, no quedan esperando a que entre otra persona.
  ///
  /// Sólo tiene sentido llamarlo con una sesión establecida: `mailSesion` es
  /// el de esa sesión. Con `null` (una cuenta de Apple con mail oculto, por
  /// ejemplo) no hay contra qué comparar y se descarta.
  static Future<CodigosGuardados?> tomar(String? mailSesion) async {
    final prefs = await SharedPreferences.getInstance();
    final m = prefs.getString(_claveMail);
    final r = (prefs.getString(_claveRegalo) ?? '').trim();
    final f = (prefs.getString(_claveReferido) ?? '').trim();
    await _borrar(prefs);
    if (m == null || m.isEmpty) return null;
    if (m != normalizarMail(mailSesion)) return null;
    if (r.isEmpty && f.isEmpty) return null;
    return CodigosGuardados(
      regalo: r.isEmpty ? null : r,
      referido: f.isEmpty ? null : f,
    );
  }

  static Future<void> _borrar(SharedPreferences prefs) async {
    await prefs.remove(_claveMail);
    await prefs.remove(_claveRegalo);
    await prefs.remove(_claveReferido);
  }
}

/// Lo que devolvió [CodigosPendientes.tomar]: cada campo viene `null` si no
/// se había escrito. Nunca vienen los dos en `null` (en ese caso `tomar`
/// devuelve `null` directamente).
class CodigosGuardados {
  final String? regalo;
  final String? referido;

  const CodigosGuardados({this.regalo, this.referido});
}
