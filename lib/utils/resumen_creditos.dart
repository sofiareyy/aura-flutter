/// Los textos de la tarjeta de "Mis créditos".
///
/// **Qué reemplaza** (9/9/2026): había un "Este mes ahorraste $X" calculado
/// contra una tabla de precios de mercado escrita a mano en el código (yoga
/// $30.000, pilates $20.000, gym $12.000) que **nadie podía defender**: no
/// tenía fuente ni fecha, y al contrastarla con los precios reales de los
/// estudios sobreestimaba alrededor del 50%. Se sacó por la misma razón por la
/// que se descartó el cartel de ahorro del paywall.
///
/// **Qué dice ahora.** Mira para adelante —lo que la usuaria puede hacer con
/// los créditos que tiene— y suma su recorrido histórico. Todo sale de datos
/// reales: nada inventado.
library;

import 'rango_clases_pack.dart';

/// El renglón principal: qué se puede hacer con el saldo.
///
/// Devuelve null si no hay saldo: ahí la tarjeta muestra el estado vacío.
String? textoSaldo({
  required int creditos,
  required List<int> preciosDeClase,
}) {
  if (creditos <= 0) return null;
  final rango = rangoDeClases(
    creditosDelPack: creditos,
    preciosDeClase: preciosDeClase,
  );
  // Sin precios cargados no se dice para cuánto alcanza, pero el saldo sí.
  if (rango == null) return null;
  // `rangoDeClases` devuelve "Para probar una clase" pensando en la tarjeta de
  // un pack; acá la frase es sobre lo que YA tiene.
  if (rango == 'Para probar una clase') return 'Te alcanza para una clase';
  return 'Te alcanza para ${rango[0].toLowerCase()}${rango.substring(1)}';
}

/// La oferta disponible, que es siempre cierta y no depende de lo que usó.
///
/// Null si hay uno solo o no se pudo contar: "elegí entre 1 estudio" no dice
/// nada.
String? textoOferta({required int? estudiosActivos}) {
  if (estudiosActivos == null || estudiosActivos < 2) return null;
  return 'Elegí entre $estudiosActivos estudios';
}

/// El recorrido, histórico y en chico.
///
/// **Los estudios se mencionan sólo si son 2 o más.** Con las dos alumnas que
/// hoy reservaron —las dos en un solo estudio— un "en 1 estudio" le diría en la
/// cara que fue a un solo lugar, que es lo contrario de lo que se quiere
/// comunicar. El texto crece con ella: cuando pruebe un segundo estudio, ahí sí
/// aparece.
String? textoRecorrido({required int clases, required int estudios}) {
  if (clases <= 0) return null;
  final c = clases == 1 ? '1 clase' : '$clases clases';
  if (estudios >= 2) return 'Llevás $c en $estudios estudios';
  return 'Llevás $c con Aura';
}

/// El estado vacío: nunca reservó.
///
/// Con créditos en la mano se lo recuerda, porque es lo que falta para que
/// reserve. Sin créditos, sólo la invitación.
({String titulo, String? bajada}) textoSinReservas({required int creditos}) {
  return (
    titulo: 'Reservá tu primera clase',
    bajada: creditos > 0
        ? 'Tenés ${creditos == 1 ? "1 crédito" : "$creditos créditos"} esperando'
        : null,
  );
}
