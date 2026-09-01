import 'package:shared_preferences/shared_preferences.dart';

/// A dónde mandar a alguien DESPUÉS de loguearse, cuando venía de un lugar
/// concreto de la app.
///
/// El caso que resuelve (2/9/2026): una invitada mira una clase, toca
/// "reservar", el muro le ofrece entrar, se loguea… y caía en `/home`,
/// perdiendo justo la clase que la trajo. Con pauta paga esa persona es
/// alguien por quien se pagó: perderla en el último paso es caro.
///
/// **La regla de seguridad, en un solo lugar:** el destino sólo se respeta si
/// el rol no manda a otro lado. `AuthService.destinoInicial()` devuelve
/// `/home` únicamente para una usuaria sin accesos de estudio; un estudio, una
/// profe o un admin reciben SU ruta, y esa siempre gana. Así el `?volver=` no
/// puede sacar a nadie de su panel.
class DestinoPostLogin {
  DestinoPostLogin._();

  static const _clave = 'destino_post_login';

  /// Sólo rutas internas. Mismo filtro que el onboarding de créditos: sin esto
  /// un `?volver=https://…` armado a mano convertiría el login en un redirect
  /// abierto hacia afuera de Aura.
  static String? sanear(String? ruta) {
    if (ruta == null) return null;
    final r = ruta.trim();
    if (r.isEmpty) return null;
    if (!r.startsWith('/')) return null; // absoluta o esquema raro
    if (r.startsWith('//')) return null; // protocol-relative: sale del dominio
    return r;
  }

  /// El destino final: el del rol, salvo que sea el `/home` genérico y haya
  /// un lugar concreto al que volver.
  static String resolver(String destinoPorRol, String? volver) {
    if (destinoPorRol != '/home') return destinoPorRol;
    return sanear(volver) ?? destinoPorRol;
  }

  /// Guarda el destino para que sobreviva a la vuelta de OAuth (en web la
  /// página se recarga y en la app se sale al navegador: la pantalla de login
  /// se destruye y con ella el `?volver=` de su ruta).
  static Future<void> recordar(String? ruta) async {
    final limpia = sanear(ruta);
    final prefs = await SharedPreferences.getInstance();
    if (limpia == null) {
      await prefs.remove(_clave);
    } else {
      await prefs.setString(_clave, limpia);
    }
  }

  /// Lee y BORRA (de un solo uso): si no se consumiera, un login siguiente
  /// terminaría en una clase vieja sin que nadie lo haya pedido.
  static Future<String?> tomar() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_clave);
    await prefs.remove(_clave);
    return sanear(v);
  }
}
