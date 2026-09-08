/// Cuándo mostrar el onboarding de créditos.
///
/// **El problema** (9/9/2026): de 79 alumnas registradas sólo 4 compraron. El
/// onboarding que explica qué son los créditos se disparaba **sólo desde el
/// registro con mail**, y de las 79 cuentas **28 entraron con Apple y 24 con
/// Google**: el 66% nunca vio la explicación y llegaba al muro de pago sin
/// saber qué estaba comprando.
///
/// Esta función decide, y es pura para poder probarla sin levantar la app.
library;

/// La ruta del onboarding, una sola vez para que no se escriba a mano.
const String kRutaOnboardingCreditos = '/creditos-onboarding';

/// ¿Hay que interponer el onboarding antes de [destino]?
///
/// Dos condiciones, las dos necesarias:
///
///  - **[yaLoVio] es false.** Se guarda en `SharedPreferences` cuando lo
///    termina, así que se muestra una vez por dispositivo.
///  - **El destino es de alumna.** Un estudio o una profe van a su panel: no
///    compran créditos y el onboarding no les dice nada. Se reconoce porque
///    `resolver` sólo devuelve rutas distintas de `/home` para esos roles, o
///    una ruta interna guardada (la clase que estaba mirando).
bool debeVerOnboarding({required String destino, required bool yaLoVio}) {
  if (yaLoVio) return false;
  return esDestinoDeAlumna(destino);
}

/// Los destinos que corresponden a una alumna. Todo lo que empieza con
/// `/estudio` (salvo el detalle público) o `/seleccionar-acceso` es del otro
/// lado del producto.
bool esDestinoDeAlumna(String destino) {
  if (destino.startsWith('/seleccionar-acceso')) return false;
  if (!destino.startsWith('/estudio')) return true;
  // `/estudio/<id>` es la ficha pública que una alumna sí puede estar
  // mirando; `/estudio/dashboard`, `/estudio/clases`, etc. son el panel.
  final resto = destino.substring('/estudio'.length);
  if (resto.startsWith('/')) {
    final seg = resto.substring(1).split(RegExp(r'[/?]')).first;
    return int.tryParse(seg) != null;
  }
  return false;
}

/// El onboarding con el destino original colgado en `?volver=`, para que al
/// terminar la deje donde iba (la clase que la trajo, o `/home`).
String rutaOnboardingCon(String destino) =>
    '$kRutaOnboardingCreditos?volver=${Uri.encodeComponent(destino)}';
