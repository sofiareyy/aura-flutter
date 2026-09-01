// Filtros de Explorar a nivel PLAN (clase o experiencia), no estudio.
//
// Etapa E3 del rediseño (1/9/2026): el chip de categoría y la búsqueda de
// texto dejan de mirar el perfil del estudio y pasan a mirar la clase misma.
// Antes, tocar "Gym / Funcional" no mostraba a Yessi con 70 clases de eso,
// porque su perfil declaraba "Fitness".
//
// Es una función PURA a propósito: el test la corre contra una foto de las
// clases reales de producción y exige los mismos conteos que da la SQL.

/// Con qué se busca un plan: sus `etiquetas` (etapa E4, todavía sin columna)
/// y, si no tiene, sus `categorias` de cobro. Ese fallback es la regla de oro
/// del diseño: cero migración, todo encontrable desde el día uno.
List<String> catsBusquedaDe(Map<String, dynamic> clase) {
  List<String> limpiar(dynamic raw) => raw is List
      ? raw
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList()
      : const [];
  final etiquetas = limpiar(clase['etiquetas']);
  if (etiquetas.isNotEmpty) return etiquetas;
  return limpiar(clase['categorias']);
}

bool _contieneCategoria(List<String> cats, String categoria) {
  final target = categoria.trim().toLowerCase();
  return cats.any((c) => c.toLowerCase() == target);
}

/// ¿Este plan pasa el chip de categoría y la búsqueda de texto?
///
/// - [categoria]: el chip activo ('Todos' = sin filtro). Matchea contra las
///   categorías/etiquetas DE LA CLASE, no del estudio.
/// - [query]: el texto del buscador. Matchea el nombre del plan y sus
///   categorías, y también el estudio (nombre, barrio, categorías): buscar
///   "Citra" tiene que seguir mostrando las clases de Citra.
bool planVisible(
  Map<String, dynamic> clase, {
  String categoria = 'Todos',
  String query = '',
}) {
  final cats = catsBusquedaDe(clase);
  if (categoria != 'Todos' && !_contieneCategoria(cats, categoria)) {
    return false;
  }

  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;

  final estudio = clase['estudios'] as Map<String, dynamic>?;
  List<String> catsEstudio(dynamic raw) => raw is List
      ? raw.map((e) => e?.toString() ?? '').toList()
      : const [];
  return (clase['nombre']?.toString().toLowerCase().contains(q) ?? false) ||
      cats.any((c) => c.toLowerCase().contains(q)) ||
      (estudio?['nombre']?.toString().toLowerCase().contains(q) ?? false) ||
      (estudio?['barrio']?.toString().toLowerCase().contains(q) ?? false) ||
      catsEstudio(estudio?['categorias'])
          .any((c) => c.toLowerCase().contains(q));
}

/// Filtro de tipo: 'todo' · 'clases' · 'experiencias'.
bool tipoVisible(Map<String, dynamic> clase, String tipoFiltro) {
  if (tipoFiltro == 'todo') return true;
  final esExperiencia = clase['tipo']?.toString() == 'workshop';
  return tipoFiltro == 'experiencias' ? esExperiencia : !esExperiencia;
}
