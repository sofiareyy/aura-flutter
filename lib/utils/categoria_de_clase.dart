/// La categoría que se le muestra a la alumna para UNA CLASE.
///
/// **El bug que resuelve** (9/9/2026): siete pantallas leían la categoría del
/// ESTUDIO para etiquetar una clase. Con Rock Studios —que es Spinning *y*
/// Pilates— toda tarjeta suya decía "SPINNING · PILATES", así que **RockFormer,
/// que es de pilates, aparecía como spinning**. La alumna reservaba creyendo
/// que iba a otra cosa.
///
/// El mismo error estaba en el filtro de chips del Inicio: filtraba por las
/// categorías del estudio, así que con el chip en "Pilates" salían las clases
/// de RockCycle.
///
/// **La regla:** para una CLASE manda la clase. El estudio es sólo el último
/// recurso, para datos viejos que no tengan la categoría cargada.
library;

import '../models/estudio.dart';

/// Todas las categorías de la clase, en orden.
///
/// Prioridad: el array de la clase → su escalar → el del estudio. Nunca
/// inventa: si no hay nada, devuelve vacío.
List<String> categoriasDeClase(Map<String, dynamic> clase) {
  List<String> limpiar(dynamic raw) => raw is List
      ? raw
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList()
      : const [];

  final delArray = limpiar(clase['categorias']);
  if (delArray.isNotEmpty) return delArray;

  final escalar = clase['categoria']?.toString().trim() ?? '';
  if (escalar.isNotEmpty) return [escalar];

  // Último recurso: el perfil del estudio. Sirve para clases viejas cargadas
  // antes de que existiera `clases.categorias`.
  final estudio = clase['estudios'];
  if (estudio is Map) {
    return Estudio.parseCategorias(
      Map<String, dynamic>.from(estudio),
    ).map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
  }
  return const [];
}

/// La categoría PRINCIPAL, para el badge de una tarjeta: una sola.
///
/// Devuelve cadena vacía si no hay ninguna. **Nunca un valor por defecto**: el
/// detalle de clase escribía `'YOGA'` literal cuando faltaba el dato, así que
/// una clase de spinning podía anunciarse como yoga.
String categoriaDeClase(Map<String, dynamic> clase) {
  final cats = categoriasDeClase(clase);
  return cats.isEmpty ? '' : cats.first;
}

/// ¿Esta clase entra en el chip [categoria]? 'Todos' deja pasar todo.
///
/// Compara contra las categorías de la CLASE, no del estudio.
bool claseEsDeCategoria(Map<String, dynamic> clase, String categoria) {
  final objetivo = categoria.trim().toLowerCase();
  if (objetivo.isEmpty || objetivo == 'todos') return true;
  return categoriasDeClase(clase).any((c) => c.toLowerCase() == objetivo);
}
