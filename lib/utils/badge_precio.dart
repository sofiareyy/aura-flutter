// Cuándo una clase muestra "🏷️ PRECIO REDUCIDO" (14/10/2026).
//
// Es la SEGUNDA corrección de este cartel, y conviene leer las dos juntas
// porque el error fue el mismo dos veces: dar por cierto un dato que el
// estudio declara, en vez de mirar lo que el estudio hace.
//
//   26/8 — Miraba el NOMBRE de la franja: salía con `tipo_precio` 'normal' o
//          'valle'. Eso lo ponía en 823 de 997 clases (83%), incluso en los
//          tres estudios de precio único, y en la franja 'normal' que en
//          promedio es la MÁS cara.
//
//   14/10 — Pasó a comparar contra `estudios.creditos_max`. Pero esa columna
//          no es un techo observado: es la CONFIGURACIÓN de precios
//          (`tipo_precio='rango'` ⇒ valle cobra `creditos_min`, el resto
//          `creditos_max`). Un estudio puede declarar un rango y no
//          realizarlo nunca, y es lo que pasaba:
//
//            Rock Studios Palermo   declara 16–18   cobra 16 en 252 clases
//            Rock Studios Recoleta  declara 16–18   cobra 16 en 193 clases
//            Delta Heat Yoga        declara 14–17   cobra 14 en  42 clases
//
//          Los tres tienen todas sus clases en franja `valle`: nunca marcaron
//          un horario como pico, así que el techo no se aplica a nada. El
//          cartel salía en el 100% de sus clases prometiendo una rebaja
//          contra un precio que no se cobra nunca. 487 clases, el 46% de
//          todos los carteles.
//
// Ahora se compara contra el rango que el estudio REALMENTE publica, que
// calcula la vista `estudios_rango_publicado` (ver
// `supabase/RANGO_PUBLICADO_2026-10-14.sql`). Del lado del servidor y no
// sobre las clases cargadas, a propósito: si se calculara con lo que vino en
// la página, la misma clase mostraría o no el cartel según cuánto hubieras
// scrolleado.
//
// Medido al 14/10: de 1.051 clases con cartel se pasa a 564.

/// El rango de precios que un estudio tiene publicado hoy.
class RangoPublicado {
  final int min;
  final int max;

  const RangoPublicado(this.min, this.max);

  /// Un estudio "tiene rango" sólo si de verdad cobra precios distintos. Con
  /// un precio único no hay nada reducido que anunciar.
  bool get hayRango => max > min;
}

/// ¿Esta clase cuesta menos que lo más caro que cobra su propio estudio?
///
/// [rango] es el del estudio de ESTA clase; null cuando no se pudo traer
/// (estudio sin clases futuras), y ahí no se muestra nada: ante la duda, no
/// se promete una rebaja.
bool esPrecioReducido({
  required int? creditos,
  required String? tipoPrecio,
  required RangoPublicado? rango,
}) {
  // Un servicio de precio fijo no entra en el juego de franjas: su precio es
  // único por definición. Sin esta exclusión, un sauna de 14 en un estudio
  // con techo 18 salía "PRECIO REDUCIDO" sin tener nada de reducido.
  if (tipoPrecio == 'servicio') return false;
  if (creditos == null || rango == null) return false;
  if (!rango.hayRango) return false;
  return creditos < rango.max;
}

/// El rango publicado del estudio al que pertenece [clase].
///
/// El id puede venir en `clase['estudio_id']` o adentro del embed
/// `clase['estudios']['id']`, según qué consulta la haya traído.
RangoPublicado? rangoDeLaClase(
  Map<String, dynamic> clase,
  Map<int, RangoPublicado> porEstudio,
) {
  final estudio = clase['estudios'] as Map<String, dynamic>?;
  final id =
      (clase['estudio_id'] as num?)?.toInt() ??
      (estudio?['id'] as num?)?.toInt();
  if (id == null) return null;
  return porEstudio[id];
}
