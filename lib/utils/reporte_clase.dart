// "¿No pudiste ir o la clase no se dio?" (16/10/2026).
//
// POR QUÉ EXISTE
//
// Si el estudio no da la clase, hoy la alumna pierde los créditos y el
// estudio cobra: el sistema no distingue "no fue" de "la clase no existió".
// Pasó tres veces, y las tres se arreglaron a mano cancelando la reserva, que
// era lo único que evitaba que el estudio cobrara.
//
// El diseño está cerrado en `supabase/pendientes/RETOMAR_ACA.md` (17/9). Esta
// es la regla de cuándo se puede reportar; la de qué pasa después vive en la
// RPC `reportar_mi_clase` (`supabase/REPORTAR_CLASE_NO_DADA_2026-10-16.sql`).
//
// DOS COSAS QUE NO SON LO MISMO, y por eso hay dos motivos:
//
//  · "No pude ir"      — la alumna faltó. El estudio dio la clase y cobra.
//                        Se registra nada más, para saber que vio la pregunta
//                        y eligió: no es lo mismo que ignorarla.
//  · "La clase no se dio" — la reserva pasa a `en_revision`, deja de
//                        liquidarse y Sofía decide. NO devuelve créditos
//                        sola: primero se le pregunta al estudio.

/// Los dos motivos, con el texto que ve la alumna.
enum MotivoReporte {
  noPudeIr('no_pude_ir', 'No pude ir'),
  noSeDio('no_se_dio', 'La clase no se dio');

  final String valor;
  final String etiqueta;

  const MotivoReporte(this.valor, this.etiqueta);
}

/// Cuánto tiempo hay para avisar, desde que TERMINA la clase.
///
/// 48 h es la decisión del diseño: suficiente para que alguien se acuerde al
/// día siguiente, corto para que no llegue cuando el mes ya se liquidó.
const Duration kPlazoParaReportar = Duration(hours: 48);

/// ¿Esta reserva puede reportarse ahora?
///
/// [reserva] es la fila tal como viene de la consulta, con la clase adentro.
/// [ahora] se pasa para poder testearlo sin depender del reloj.
bool puedeReportar(Map<String, dynamic> reserva, {required DateTime ahora}) {
  // Ya avisó: no se pregunta dos veces.
  if (reserva['reporte_at'] != null) return false;

  // Una reserva cancelada no se reporta: nadie perdió créditos.
  final estado = reserva['estado']?.toString() ?? '';
  if (estado == 'cancelada' || estado == 'cancelada_por_estudio') return false;

  final clase = reserva['clases'] as Map<String, dynamic>?;
  if (clase == null) return false;

  // Las fechas vienen en hora argentina sin marcador. Se comparan contra un
  // `ahora` del mismo tipo: quien llama pasa `DateTime.now()`, que en el
  // teléfono de una usuaria argentina es la misma hora.
  final fecha = DateTime.tryParse(clase['fecha']?.toString() ?? '');
  if (fecha == null) return false;
  final duracion = (clase['duracion_min'] as num?)?.toInt() ?? 60;
  final fin = fecha.add(Duration(minutes: duracion));

  if (!fin.isBefore(ahora)) return false; // todavía no terminó
  return ahora.difference(fin) <= kPlazoParaReportar;
}

/// Lo que se le muestra a quien YA avisó, en vez de la pregunta.
String? etiquetaDeReporte(Map<String, dynamic> reserva) {
  if (reserva['reporte_at'] == null) return null;
  return switch (reserva['reporte_motivo']?.toString()) {
    'no_se_dio' => 'Lo estamos revisando',
    'no_pude_ir' => 'Avisaste que no pudiste ir',
    _ => null,
  };
}
