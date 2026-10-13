// Los números de la cabecera de "Reservas del mes" (13/10/2026).
//
// Por qué es una función aparte: los tres contadores se calculaban sobre la
// lista ENTERA, canceladas incluidas. "12 reservas · 96 créditos" contaba
// plata que se había devuelto, y encima la fila de abajo mostraba el cartelito
// "Cancelada" al lado — los números y la lista decían cosas distintas en la
// misma pantalla.
//
// El criterio no se inventa acá: es `AppConstants.estadosLiquidables`, el
// mismo que usan Cobros y el Dashboard para decidir qué se cobra. Así los tres
// paneles cuentan igual, que es justo lo que hoy no pasa entre Cobros y el
// Dashboard.

import '../core/constants/app_constants.dart';

class ResumenReservasMes {
  /// Las que valen: confirmada, presente, ausente, completada.
  final int reservas;

  /// De las que valen, a cuántas se les marcó el presente.
  final int presentes;

  /// Los créditos de las que valen. Las canceladas no suman: esos créditos
  /// volvieron a la alumna.
  final int creditos;

  /// Se muestran aparte y sólo si hay. La lista las sigue mostrando con su
  /// cartelito, así que esconderlas del todo dejaría filas sin explicación.
  final int canceladas;

  const ResumenReservasMes({
    required this.reservas,
    required this.presentes,
    required this.creditos,
    required this.canceladas,
  });
}

/// Cualquier estado que empiece con `cancelada` cuenta como cancelada:
/// existen `cancelada` y `cancelada_por_estudio`, y las dos devuelven
/// créditos. Hoy en producción sólo hay filas de la primera, pero la segunda
/// la escribe el servidor cuando el estudio baja una clase.
bool esCancelada(String? estado) => (estado ?? '').startsWith('cancelada');

ResumenReservasMes resumirReservasDelMes(List<Map<String, dynamic>> filas) {
  var reservas = 0;
  var presentes = 0;
  var creditos = 0;
  var canceladas = 0;

  for (final r in filas) {
    final estado = r['estado']?.toString();
    if (esCancelada(estado)) {
      canceladas++;
      continue;
    }
    // Lo que no es liquidable ni cancelado es `pre_confirmada`: todavía no
    // consumió crédito ni ocupa lugar firme, así que no entra en ningún
    // número. Aparece igual en la lista de abajo.
    if (!AppConstants.estadosLiquidables.contains(estado)) continue;

    reservas++;
    if (r['checked_in_at'] != null) presentes++;
    creditos += (r['creditos_usados'] as num?)?.toInt() ?? 0;
  }

  return ResumenReservasMes(
    reservas: reservas,
    presentes: presentes,
    creditos: creditos,
    canceladas: canceladas,
  );
}
