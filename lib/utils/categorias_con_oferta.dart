// Qué chips de categoría mostrar en el Inicio.
//
// El problema (auditoría del 4/9): los chips salían del CATÁLOGO completo, que
// tiene 13 categorías, y las secciones del Inicio muestran clases. Seis de esos
// 13 no tenían ninguna clase: tocar Cerámica, Danza, Recovery, Running club,
// Spa o GRATIS dejaba la pantalla en "No encontramos clases para esta semana en
// esta categoría". Un chip que lleva a un vacío es un callejón, y encima
// "GRATIS" está desactivada en la base y se colaba igual porque la consulta del
// catálogo no mira `activa`.
//
// La regla, que se cumple por construcción: **un chip aparece sólo si hay al
// menos una clase cargada que caiga bajo él**. Se calcula sobre las clases que
// el Inicio YA tiene en memoria, no sobre la base, justamente para que la
// promesa del chip y lo que se ve después no puedan separarse.

import '../models/estudio.dart';

/// La etiqueta que no filtra nada. Siempre primera y siempre presente.
const String kCategoriaTodos = 'Todos';

/// Las categorías del [catalogo] que tienen al menos una clase en [clases],
/// en el mismo orden que venían. `Todos` siempre queda primero.
///
/// [clases] son las filas del feed del Inicio, con el estudio embebido en
/// `clase['estudios']`: el filtro de las secciones es por las categorías del
/// ESTUDIO, así que acá se mira lo mismo y no otra cosa.
List<String> categoriasConOferta({
  required List<String> catalogo,
  required List<Map<String, dynamic>> clases,
}) {
  final conClases = <String>{};
  for (final clase in clases) {
    final estudio = clase['estudios'];
    if (estudio is! Map) continue;
    for (final c in Estudio.parseCategorias(
      Map<String, dynamic>.from(estudio),
    )) {
      final limpia = c.trim();
      if (limpia.isNotEmpty) conClases.add(limpia.toLowerCase());
    }
  }

  final out = <String>[kCategoriaTodos];
  for (final cat in catalogo) {
    final limpia = cat.trim();
    if (limpia.isEmpty) continue;
    if (limpia == kCategoriaTodos) continue; // ya está primero
    if (conClases.contains(limpia.toLowerCase())) out.add(limpia);
  }
  return out;
}

/// La categoría elegida sigue siendo válida entre las [visibles].
///
/// Importa cuando la lista se recalcula: si alguien tenía elegida una
/// categoría que se quedó sin clases, hay que devolverla a `Todos` en vez de
/// dejarla mirando un vacío con un chip que ya no está.
String categoriaValida(String elegida, List<String> visibles) =>
    visibles.contains(elegida) ? elegida : kCategoriaTodos;
