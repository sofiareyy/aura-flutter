// Cupos propios por horario, mientras se arma una grilla.
//
// El formulario de grilla tiene UN campo de cupos que se aplica a todos los
// horarios. Esto guarda las excepciones: `día -> minuto del día -> cupos`.
// Lo que no está acá usa el cupo general (30/9/2026).
//
// Vive afuera de la pantalla para poder probarlo: la pantalla del estudio
// pide login y no se puede abrir en un test.

import 'package:flutter/material.dart';

/// Minuto del día: la clave con la que se identifica un horario dentro de la
/// grilla mientras se la arma (todavía no tiene id).
int minutoClave(TimeOfDay t) => t.hour * 60 + t.minute;

/// Saca los cupos propios de horarios que ya no están en la grilla.
///
/// Sin esto, borrar las 08:00 y volver a agregarlas resucitaba el cupo viejo:
/// la usuaria veía "2 cupos" en un horario que creía recién creado.
void podarCupos(
  Map<int, Map<int, int>> cupos,
  Map<int, List<TimeOfDay>> horariosPorDia,
) {
  for (final dia in cupos.keys.toList()) {
    final vivos = (horariosPorDia[dia] ?? const <TimeOfDay>[])
        .map(minutoClave)
        .toSet();
    cupos[dia]!.removeWhere((minuto, _) => !vivos.contains(minuto));
    if (cupos[dia]!.isEmpty) cupos.remove(dia);
  }
}

/// Guarda el cupo propio de un horario.
///
/// Un valor igual al general NO es una excepción: se borra, para que el chip
/// no muestre un número que no significa nada.
void fijarCupo(
  Map<int, Map<int, int>> cupos, {
  required int dia,
  required int minuto,
  required int valor,
  required int general,
}) {
  if (valor == general) {
    quitarCupo(cupos, dia: dia, minuto: minuto);
    return;
  }
  (cupos[dia] ??= <int, int>{})[minuto] = valor;
}

/// Vuelve a usar el cupo general en ese horario.
void quitarCupo(
  Map<int, Map<int, int>> cupos, {
  required int dia,
  required int minuto,
}) {
  cupos[dia]?.remove(minuto);
  if (cupos[dia]?.isEmpty ?? false) cupos.remove(dia);
}

/// Cuántos horarios tienen cupo propio. Es lo que muestra el resumen previo.
int cuantosConCupoPropio(Map<int, Map<int, int>> cupos) =>
    cupos.values.fold<int>(0, (a, m) => a + m.length);
