// Los filtros de Explorar, traducidos a PostgREST.
//
// 17/9/2026: el chip de categoría y el buscador dejan de filtrarse en memoria
// y viajan a la base. Antes se pedían 20 clases cualesquiera ordenadas por
// fecha y recién ahí se descartaba lo que no era de la categoría: con Pilates
// (~15% del catálogo) de esas 20 quedaban 2 o 3, y para ver las 155 había que
// tocar "Cargar más" unas 50 veces.
//
// Son funciones PURAS —devuelven el string del `.or()`— para poder testearlas
// sin base. Tienen que dar exactamente lo mismo que `planVisible`, que sigue
// corriendo en memoria como segunda red (por eso el filtro de acá es igual de
// amplio, nunca más estricto).

/// Escapa lo que va adentro de un `or(...)` de PostgREST. Las comas separan
/// condiciones y los paréntesis las agrupan, así que un texto con comas
/// rompería la query entera.
String limpiarParaFiltro(String s) =>
    s.replaceAll(RegExp(r'[(),.*:"\\\\]'), ' ').trim();

/// El filtro de categoría: la clase la tiene en su lista, o en el campo
/// suelto, o —si no tiene ninguna propia— la hereda de su estudio.
///
/// Ese último caso es el que obliga a pasar [estudiosDeLaCategoria]: hay
/// clases sin categoría propia (17 de 1417 al 17/9) que sólo son de Pilates
/// porque su estudio lo es. Sin eso, filtrar las escondería.
String? filtroCategoriaPostgrest(String? categoria, List<int> estudiosDeLaCategoria) {
  final cat = limpiarParaFiltro(categoria ?? '');
  if (cat.isEmpty || cat == 'Todos') return null;

  final partes = <String>[
    'categoria.eq.$cat',
    'categorias.cs.{"$cat"}',
  ];
  if (estudiosDeLaCategoria.isNotEmpty) {
    final ids = estudiosDeLaCategoria.join(',');
    // Sólo las que NO tienen categoría propia heredan la del estudio: si no,
    // filtrar "Pilates" traería también el spinning de un estudio mixto.
    partes.add('and(categoria.is.null,estudio_id.in.($ids))');
  }
  return partes.join(',');
}

/// El filtro de texto: el nombre de la clase, o que el estudio matchee (por
/// nombre, barrio o categorías — eso se resuelve antes, en memoria, porque los
/// estudios ya están cargados enteros).
String? filtroTextoPostgrest(String? texto, List<int> estudiosDelTexto) {
  final q = limpiarParaFiltro(texto ?? '');
  if (q.isEmpty) return null;

  final partes = <String>['nombre.ilike.*$q*'];
  if (estudiosDelTexto.isNotEmpty) {
    partes.add('estudio_id.in.(${estudiosDelTexto.join(',')})');
  }
  return partes.join(',');
}
