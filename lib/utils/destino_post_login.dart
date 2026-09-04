import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A dónde mandar a alguien DESPUÉS de loguearse, cuando venía de un lugar
/// concreto de la app.
///
/// El caso que resuelve (2/9/2026): una invitada mira una clase, toca
/// "reservar", el muro le ofrece entrar, se loguea… y caía en `/home`,
/// perdiendo justo la clase que la trajo. Con pauta paga esa persona es
/// alguien por quien se pagó: perderla en el último paso es caro.
///
/// El MISMO problema aparece después de PAGAR (4/9/2026): la usuaria llega al
/// checkout desde una clase concreta, paga, y el único botón era "Ir al
/// inicio". Tenía que volver a buscar a mano la clase que acababa de pagar,
/// con la plata ya puesta. Se resuelve con este mismo mecanismo — ver
/// [recordarCompra].
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

  // ── La vuelta del PAGO ────────────────────────────────────────────────

  /// Clave APARTE de la del login, a propósito.
  ///
  /// Las dos guardan "a dónde volver", pero las consume gente distinta: la
  /// del login la lee el callback de OAuth en `main.dart` y la de la compra
  /// la lee el checkout. Con una sola clave, un OAuth abandonado a mitad de
  /// camino dejaría una ruta guardada que después se comería el pago (o al
  /// revés), y la usuaria terminaría en un lugar que nadie pidió.
  static const _claveCompra = 'destino_post_compra';

  /// Guarda a dónde volver después de pagar. Igual que en OAuth, hace falta
  /// persistirlo: en web `launchUrl(..., '_self')` se lleva la pestaña a
  /// Mercado Pago y al volver la app arranca de cero, sin el `?volver=` de la
  /// ruta ni el estado del checkout.
  static Future<void> recordarCompra(String? ruta) async {
    final limpia = sanear(ruta);
    final prefs = await SharedPreferences.getInstance();
    if (limpia == null) {
      await prefs.remove(_claveCompra);
    } else {
      await prefs.setString(_claveCompra, limpia);
    }
  }

  /// Lee y BORRA el destino de la compra. De un solo uso, por lo mismo que
  /// [tomar]: una compra siguiente no tiene por qué terminar en la clase de
  /// la compra anterior.
  static Future<String?> tomarCompra() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_claveCompra);
    await prefs.remove(_claveCompra);
    return sanear(v);
  }

  /// La ruta donde está parada la persona AHORA, para poder volver acá.
  ///
  /// Vive en esta clase (y no en el muro, de donde salió) porque la usan los
  /// dos caminos: el muro del modo visita y el paywall de créditos.
  ///
  /// El `catch` no es decorativo: `showDialog` abre una ruta HERMANA en el
  /// Navigator, así que preguntar desde adentro de un diálogo tira `GoError`.
  /// Por eso se pregunta con el context de QUIEN abre, y `GoRouter.of` queda
  /// de respaldo porque funciona desde cualquier lado bajo el router.
  static String rutaActualDe(BuildContext context) {
    try {
      return GoRouterState.of(context).uri.toString();
    } catch (_) {
      return GoRouter.of(context)
          .routeInformationProvider
          .value
          .uri
          .toString();
    }
  }

  /// Pega `?volver=` a una ruta, si hay algo que recordar. Un solo lugar para
  /// no repetir el `Uri.encodeComponent` en cada pantalla.
  static String conVolver(String ruta, String? volver) {
    final limpia = sanear(volver);
    if (limpia == null) return ruta;
    final sep = ruta.contains('?') ? '&' : '?';
    return '$ruta$sep' 'volver=${Uri.encodeComponent(limpia)}';
  }
}
