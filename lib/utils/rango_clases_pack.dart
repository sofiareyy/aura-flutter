/// Cuántas clases rinde un pack, dicho de forma honesta.
///
/// **Por qué** (9/9/2026): la tarjeta de un pack decía sólo "Pack Esencial · 50
/// créditos · $50.000". Un usuario nuevo no tiene forma de saber si eso le
/// alcanza para la clase que quiere, y tiene que hacer una división mental
/// justo en el momento de pagar.
///
/// **Por qué un RANGO y no un número.** Las clases no valen todas lo mismo: en
/// producción van de 11 a 18 créditos según el estudio y el horario. Prometer
/// "5 clases" sería falso la mitad de las veces. El rango sale de los precios
/// REALES que haya cargados, así que si mañana entra un estudio más caro, el
/// texto se corrige solo.
library;

/// El texto que va en la tarjeta del pack.
///
/// [creditosDelPack] es lo que compra; [preciosDeClase] son los créditos de las
/// clases disponibles de verdad. Devuelve null si no hay con qué calcular: sin
/// datos no se inventa un número.
String? rangoDeClases({
  required int creditosDelPack,
  required List<int> preciosDeClase,
}) {
  final precios = preciosDeClase.where((p) => p > 0).toList();
  if (precios.isEmpty || creditosDelPack <= 0) return null;

  precios.sort();
  final masBarata = precios.first;
  final masCara = precios.last;

  final minimo = creditosDelPack ~/ masCara;
  final maximo = creditosDelPack ~/ masBarata;

  // Ni para la más barata: no alcanza para ninguna clase entera.
  if (maximo == 0) return null;

  // Con la más cara no llega, con la más barata sí: no se promete un piso que
  // no siempre se cumple.
  if (minimo == 0) {
    return maximo == 1 ? 'Para probar una clase' : 'Hasta $maximo clases';
  }

  // El pack chico da exactamente una: se dice cálido, no seco.
  if (minimo == 1 && maximo == 1) return 'Para probar una clase';

  if (minimo == maximo) return '$minimo clases';
  return 'Entre $minimo y $maximo clases';
}
