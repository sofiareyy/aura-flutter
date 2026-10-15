// La vidriera "MÁS CLASES" del Inicio: una clase por estudio, con la rueda
// del día (15/10/2026).
//
// EL PROBLEMA, MEDIDO
//
// La vidriera mostraba "las N más próximas por fecha", con un tope blando de
// 3 por estudio. Medido con la oferta real del 14/10: las ~21 tarjetas del
// Inicio cubrían **desde las 07:00 hasta las 10:00 de la mañana siguiente**,
// de 293 clases repartidas en 18 estudios.
//
// O sea: la portada no llegaba al mediodía. Un estudio que abre a la tarde
// quedaba invisible aunque tuviera la grilla entera cargada. El caso que lo
// destapó: Pura Spot, con 86 clases publicadas, no aparecía nunca porque su
// primera clase es a las 17:00 — era la 17ª de 18 ordenando por "próxima
// clase de cada estudio".
//
// Y no se arreglaba repartiendo mejor. Simulado con los datos reales:
//
//   tope 3 por estudio (lo que había)  ->  9 estudios, llega hasta las 09:00
//   tope 2                             -> 10 estudios, llega hasta las 09:00
//   tope 1                             -> 13 estudios, llega hasta las 11:00
//
// Bajar el tope mejora la variedad pero no alcanza: con 12 tarjetas entran
// los 12 estudios que abren más temprano, y listo. El problema no era el
// volumen de nadie, era que ordenar por hora premia siempre a los mismos.
//
// LA REGLA
//
// Se muestra la PRÓXIMA clase de CADA estudio, y el orden sale de la misma
// rueda que los DESTACADOS de Explorar (`destacadosDelDia`): candidatos
// ordenados por id, arranque en `indiceDiaArgentino % n`, y se recorre en
// círculo. Dos reglas distintas de rotación en la misma app serían una de
// más.
//
// Consecuencia buscada: la vidriera deja de ser "qué puedo tomar ahora" —eso
// es Explorar, y "CLASES ESTA SEMANA" acá arriba, que queda cronológica a
// propósito— y pasa a ser una vidriera de verdad, donde todos los estudios
// pasan por el frente.

import 'mes_argentino.dart';

/// El id de estudio de una clase, venga suelto o dentro del embed.
int? estudioDeClase(Map<String, dynamic> clase) {
  final directo = (clase['estudio_id'] as num?)?.toInt();
  if (directo != null) return directo;
  final estudio = clase['estudios'] as Map<String, dynamic>?;
  return (estudio?['id'] as num?)?.toInt();
}

/// La próxima clase de cada estudio, en el orden de la rueda del día.
///
/// [clases] tiene que venir **ordenada por fecha**: se toma la primera de
/// cada estudio, así que el orden de entrada decide cuál es "la próxima".
///
/// [max] acota cuántas entran; null = todos los estudios, que es lo que usa
/// el Inicio. Con la rueda, acotar ya no deja a nadie afuera para siempre:
/// mañana arranca en el siguiente y le toca a otro.
List<Map<String, dynamic>> vidrieraDelDia({
  required List<Map<String, dynamic>> clases,
  required DateTime hoy,
  int? max,
}) {
  final proximaPorEstudio = <int, Map<String, dynamic>>{};
  for (final c in clases) {
    final id = estudioDeClase(c);
    if (id == null) continue;
    proximaPorEstudio.putIfAbsent(id, () => c);
  }
  if (proximaPorEstudio.isEmpty) return const [];

  // Por id y no por fecha: la rueda tiene que ser estable día a día. Si el
  // orden dependiera del horario, cambiaría cada vez que un estudio mueve una
  // clase y la rotación dejaría de ser pareja. Es el mismo criterio que
  // `destacadosDelDia`, que ordena por id por la misma razón.
  final ids = proximaPorEstudio.keys.toList()..sort();
  final cuantas = max == null ? ids.length : (max < 0 ? 0 : max);
  if (cuantas == 0) return const [];

  final arranque = indiceDiaArgentino(hoy) % ids.length;
  final elegidas = <Map<String, dynamic>>[];
  for (var i = 0; i < ids.length && elegidas.length < cuantas; i++) {
    elegidas.add(proximaPorEstudio[ids[(arranque + i) % ids.length]]!);
  }
  return elegidas;
}

/// Lo que se agrega con cada toque de "Ver más clases": el resto del catálogo
/// por fecha, salteando lo que la vidriera ya mostró.
///
/// La vidriera reparte; el "ver más" vuelve a ser cronológico, que es lo que
/// se espera de un "mostrame más".
List<Map<String, dynamic>> masClasesDespuesDe(
  List<Map<String, dynamic>> clases,
  List<Map<String, dynamic>> yaMostradas, {
  required int cuantas,
}) {
  if (cuantas <= 0) return const [];
  final vistas = yaMostradas
      .map((c) => (c['id'] as num?)?.toInt())
      .whereType<int>()
      .toSet();
  final resto = <Map<String, dynamic>>[];
  for (final c in clases) {
    if (resto.length >= cuantas) break;
    final id = (c['id'] as num?)?.toInt();
    if (id == null || vistas.contains(id)) continue;
    resto.add(c);
  }
  return resto;
}
