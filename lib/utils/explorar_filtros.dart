import 'dart:math' as math;
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
/// Historia corta (auditoría del 4/9): eran `_estudiosFiltrados.take(2)`, o
/// sea los DOS PRIMEROS EN ORDEN ALFABÉTICO, siempre los mismos. Después
/// pasaron a ordenarse por cantidad de clases, que era honesto pero también
/// fijo: Tiwar y Citra todos los días.
///
/// Ahora se combinan las dos cosas que pidió Sofía:
///  · **sólo estudios con clases próximas** — no se destaca una vidriera vacía;
///  · **más chances al que tiene más oferta**, pero sin que gane siempre;
///  · **rotación por día**: cambia cada día y no se mueve dentro del mismo día.
///
/// Cómo: sorteo PONDERADO y determinístico (Efraimidis–Spirakis). A cada
/// estudio se le calcula `clave = u^(1/peso)`, con `u` entre 0 y 1 derivado del
/// día argentino y del id; se ordena por la clave y se toman los primeros. Como
/// `u` sale de un hash y no de un `Random()`, dos aperturas del mismo día dan
/// lo MISMO, y al día siguiente cambia solo: sin cron y sin guardar nada.
///
/// ⚠️ **El peso es un bonus CHICO, y eso es a propósito.** `u^(1/peso)` empuja
/// todo hacia 1 muy rápido: cualquier ventaja apreciable en el exponente vuelve
/// el sorteo determinista y la rotación queda de adorno. Medido con el reparto
/// real (Tiwar 312 clases … Barre 51), sobre 28 días y 4 lugares:
///
/// | peso | Tiwar | Citra | Yessi | Yoguica | Ambra | Barre |
/// |---|---|---|---|---|---|---|
/// | `clases` (crudo) | 28 | 28 | 28 | 27 | 1 | **0** |
/// | `log(1+clases)` | 27 | 27 | 28 | 25 | 4 | **1** |
/// | `1 + 0.15·proporción` | 27 | 26 | 20 | 19 | 10 | **10** |
///
/// Con el peso crudo los dos estudios más chicos NO SALÍAN NUNCA, que es lo
/// contrario de rotar. Con el bonus del 15% el que tiene más oferta sigue
/// apareciendo casi siempre y los chicos entran ~1 de cada 3 días.
///
/// [asociadoId] (el estudio del que sos alumna) va primero y ocupa un lugar.
List<Estudio> destacadosDelDia({
  required List<Estudio> estudios,
  required List<Map<String, dynamic>> clases,
  required DateTime hoy,
  int max = 4,
  int? asociadoId,
}) {
  final cuenta = clasesPorEstudio(clases);
  final dia = diaArgentinoDe(hoy);
  final tope = cuenta.values.fold<int>(0, (a, b) => b > a ? b : a);

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
      .where((e) => e.id != null && !usados.contains(e.id) && (cuenta[e.id] ?? 0) > 0)
      .toList();

  candidatos.sort((a, b) {
    final ka = _claveDelDia(dia, a.id!, cuenta[a.id] ?? 0, tope);
    final kb = _claveDelDia(dia, b.id!, cuenta[b.id] ?? 0, tope);
    if (ka != kb) return kb.compareTo(ka);
    // Desempate estable, para que el orden nunca dependa del azar del sort.
    return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
  });

  for (final e in candidatos) {
    if (elegidos.length >= max) break;
    elegidos.add(e);
  }
  return elegidos;
}

/// Cuántas clases próximas tiene cada estudio en el feed ya cargado.
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

/// Cuánto pesa la oferta en el sorteo: un 15% de ventaja como máximo, para el
/// que tiene tantas clases como el que más. Ver la tabla de [destacadosDelDia].
const double _bonusPorOferta = 0.15;

/// `u^(1/peso)`: la clave del sorteo ponderado. Más peso ⇒ más cerca de 1.
double _claveDelDia(String dia, int estudioId, int clases, int tope) {
  final u = _uniforme('$dia|$estudioId');
  final proporcion = tope > 0 ? (clases / tope).clamp(0.0, 1.0) : 0.0;
  final peso = 1 + _bonusPorOferta * proporcion;
  return math.pow(u, 1 / peso).toDouble();
}

/// Un número estable en (0, 1) a partir de un texto. FNV-1a de 32 bits: no es
/// criptográfico y no hace falta que lo sea — sólo tiene que dar SIEMPRE lo
/// mismo para el mismo texto, en cualquier dispositivo.
double _uniforme(String semilla) {
  var h = 0x811c9dc5;
  for (final unidad in semilla.codeUnits) {
    h ^= unidad;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  // +1 y /2^32+1 para que nunca dé exactamente 0 ni 1.
  return (h + 1) / 4294967297.0;
}
