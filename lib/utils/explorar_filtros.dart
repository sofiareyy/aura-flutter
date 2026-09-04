import '../models/estudio.dart';
import 'mes_argentino.dart';

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

/// E2, arreglo del 1/9: el feed se alimenta de DOS streams — las clases
/// paginadas y las experiencias completas de una (son decenas contra ~1000
/// clases: si compiten por la paginación, la experiencia del sábado queda en
/// la posición ~97 y nadie la ve; medido en producción). Acá se mezclan por
/// fecha, con dedup por id por si algún stream trae repetidos.
List<Map<String, dynamic>> mezclarFeed(
  List<Map<String, dynamic>> clases,
  List<Map<String, dynamic>> experiencias,
) {
  final vistos = <Object?>{};
  final out = <Map<String, dynamic>>[];
  for (final p in [...clases, ...experiencias]) {
    if (vistos.add(p['id'])) out.add(p);
  }
  out.sort((a, b) {
    final fa = DateTime.tryParse(a['fecha']?.toString() ?? '');
    final fb = DateTime.tryParse(b['fecha']?.toString() ?? '');
    if (fa == null && fb == null) return 0;
    if (fa == null) return 1;
    if (fb == null) return -1;
    return fa.compareTo(fb);
  });
  return out;
}

/// Las [max] experiencias más próximas de un feed YA FILTRADO (chip, búsqueda,
/// día, horario, créditos). Alimenta la sección "EXPERIENCIAS" de Explorar:
/// si el filtro Tipo está en "Clases", o no hay ninguna, devuelve vacío y la
/// sección se oculta sola.
List<Map<String, dynamic>> experienciasDestacadas(
  List<Map<String, dynamic>> feed, {
  int max = 3,
}) =>
    feed.where((p) => p['tipo']?.toString() == 'workshop').take(max).toList();

/// Los estudios de "DESTACADOS HOY", arriba de Explorar.
///
/// **La regla (decisión de Sofía, 4/9): TURNO PAREJO.** Todos los estudios con
/// clases próximas tienen exactamente la misma chance de salir y de ser
/// primeros. La cantidad de clases NO pondera: tener muchas clases no te hace
/// más atractivo, y un intento anterior que sí ponderaba dejaba a los estudios
/// chicos casi afuera (medido: con el peso crudo, los dos más chicos no salían
/// ni una vez en 28 días).
///
/// Cómo: una **rueda**. Los candidatos se ordenan por id —un orden estable, que
/// no cambia si alguien se renombra— y cada día la ventana de [max] avanza un
/// lugar:
///
/// ```
///  día 0 → [A B C D]      día 2 → [C D E F]
///  día 1 → [B C D E]      día 3 → [D E F A]
/// ```
///
/// De ahí salen las tres propiedades que se pidieron, y no por casualidad sino
/// por construcción:
///  · **el primero nunca se repite** dos días seguidos, y recorre a TODOS antes
///    de volver a empezar (es `candidatos[día % n]`);
///  · **todos aparecen lo mismo**: exactamente [max] días de cada `n`;
///  · **es estable dentro del día** y cambia solo al siguiente, porque el
///    índice sale del día argentino. Sin cron y sin guardar nada.
///
/// Sólo entran estudios con clases próximas: no se destaca una vidriera vacía.
/// [asociadoId] (el estudio del que sos alumna) va primero y ocupa un lugar.
List<Estudio> destacadosDelDia({
  required List<Estudio> estudios,
  required List<Map<String, dynamic>> clases,
  required DateTime hoy,
  int max = 4,
  int? asociadoId,
}) {
  final cuenta = clasesPorEstudio(clases);

  final elegidos = <Estudio>[];
  final usados = <int>{};

  // Tu propio estudio primero, tenga o no clases: es tuyo.
  if (asociadoId != null) {
    for (final e in estudios) {
      if (e.id == asociadoId) {
        elegidos.add(e);
        usados.add(asociadoId);
        break;
      }
    }
  }

  final candidatos = estudios
      .where((e) =>
          e.id != null && !usados.contains(e.id) && (cuenta[e.id] ?? 0) > 0)
      .toList()
    // Por id: estable de verdad. Por nombre, un renombre movería la rueda.
    ..sort((a, b) => a.id!.compareTo(b.id!));

  if (candidatos.isEmpty) return elegidos;

  final arranque = indiceDiaArgentino(hoy) % candidatos.length;
  for (var i = 0; i < candidatos.length; i++) {
    if (elegidos.length >= max) break;
    elegidos.add(candidatos[(arranque + i) % candidatos.length]);
  }
  return elegidos;
}

/// Cuántas clases próximas tiene cada estudio en el feed ya cargado.
///
/// Ya no decide el ORDEN (la rueda es pareja), pero sigue decidiendo QUIÉN
/// entra: un estudio sin clases no se destaca.
Map<int, int> clasesPorEstudio(List<Map<String, dynamic>> clases) {
  final cuenta = <int, int>{};
  for (final clase in clases) {
    final estudio = clase['estudios'];
    final id = estudio is Map ? (estudio['id'] as num?)?.toInt() : null;
    if (id == null) continue;
    cuenta[id] = (cuenta[id] ?? 0) + 1;
  }
  return cuenta;
}
