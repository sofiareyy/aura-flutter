// El reparto de la sección "VOLVÉ A TUS ESTUDIOS" del Inicio.
//
// Qué resuelve (4/9/2026): la sección muestra las próximas clases de los
// estudios donde la usuaria YA reservó alguna vez. Medido contra producción
// con una cuenta real, la consulta cruda devolvía **ocho tarjetas casi
// idénticas** — "Citra barre · 18 cr" ocho veces, cambiando sólo la hora —
// porque quien reservó en un solo estudio recibe todo de ese estudio. Es el
// mismo problema de repetición que la auditoría marcó con las fotos.
//
// La regla: **hasta [max] clases, repartidas parejo entre los estudios**. El
// tope por estudio se calcula solo, así que el carrusel se ve lleno siempre y
// ninguno lo monopoliza cuando hay varios:
//
//   1 estudio  → 6 de ese          3 estudios → 2 de cada uno
//   2 estudios → 3 de cada uno     4 o más    → 2 de cada uno, hasta llegar a 6

/// El id del estudio de una clase, mirando el embed y el escalar.
int? _estudioDe(Map<String, dynamic> clase) {
  final embebido = clase['estudios'];
  if (embebido is Map) {
    final id = (embebido['id'] as num?)?.toInt();
    if (id != null) return id;
  }
  return (clase['estudio_id'] as num?)?.toInt();
}

/// Cuántas clases por estudio, para que entren [max] repartidas entre
/// [cantidadDeEstudios]. Nunca menos de 1.
int cupoPorEstudio(int cantidadDeEstudios, {int max = 6}) {
  if (cantidadDeEstudios <= 0) return 0;
  final cupo = (max + cantidadDeEstudios - 1) ~/ cantidadDeEstudios; // techo
  return cupo < 1 ? 1 : cupo;
}

/// Elige hasta [max] clases repartidas entre los estudios de [clases].
///
/// [clases] tiene que venir ORDENADA por fecha ascendente: se respeta ese
/// orden, así que lo que sale es siempre "lo más próximo primero".
///
/// Dos pasadas a propósito: la primera reparte parejo respetando el cupo, y la
/// segunda rellena con lo que quedó si sobraron lugares. Sin la segunda, dos
/// estudios donde uno tiene 1 sola clase dejarían el carrusel a la mitad
/// teniendo contenido para llenarlo.
/// [cupo] fija a mano el tope por estudio. Sin él se reparte parejo
/// (`cupoPorEstudio`), que es lo que quiere "Volvé a tus estudios": con un solo
/// estudio, sus 6. La vidriera del Inicio pasa un cupo fijo porque ahí la
/// prioridad es OTRA: mostrar lo que viene antes, sin que importe repetir
/// estudio, y el cupo es sólo una red para que no salgan 6 iguales.
List<Map<String, dynamic>> repartirEntreEstudios(
  List<Map<String, dynamic>> clases, {
  int max = 6,
  int? cupo,
}) {
  if (clases.isEmpty || max <= 0) return const [];

  final estudios = <int>{};
  for (final c in clases) {
    final id = _estudioDe(c);
    if (id != null) estudios.add(id);
  }
  if (estudios.isEmpty) return const [];

  final tope = cupo ?? cupoPorEstudio(estudios.length, max: max);
  final usadas = <int, int>{};
  final elegidas = <Map<String, dynamic>>[];
  final sobrantes = <Map<String, dynamic>>[];

  for (final c in clases) {
    if (elegidas.length >= max) break;
    final id = _estudioDe(c);
    if (id == null) continue;
    final ya = usadas[id] ?? 0;
    if (ya < tope) {
      elegidas.add(c);
      usadas[id] = ya + 1;
    } else {
      sobrantes.add(c);
    }
  }

  // El relleno IGNORA el tope a propósito: llenar la sección pesa más que
  // repartir. Si un estudio es el único que tiene clases, se muestran las
  // suyas antes que dejar el carrusel a medias. O sea que el tope ordena la
  // preferencia, no prohíbe repetir.
  for (final c in sobrantes) {
    if (elegidas.length >= max) break;
    elegidas.add(c);
  }

  // El relleno puede haber roto el orden por fecha: se reordena al final.
  elegidas.sort((a, b) {
    final fa = DateTime.tryParse(a['fecha']?.toString() ?? '');
    final fb = DateTime.tryParse(b['fecha']?.toString() ?? '');
    if (fa == null && fb == null) return 0;
    if (fa == null) return 1;
    if (fb == null) return -1;
    return fa.compareTo(fb);
  });
  return elegidas;
}
