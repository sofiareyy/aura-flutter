/// ¿Le mostramos a esta persona el cartel del bono de bienvenida?
///
/// La decisión vive acá y no adentro del widget para poder testearla: el
/// cartel es la única pieza del bono que la usuaria ve sí o sí, y si se
/// muestra cuando no corresponde (créditos ya gastados, bono vencido) queda
/// peor que no mostrarlo.
///
/// Los datos llegan del RPC `mi_bono`, que devuelve
/// `{tiene, monto, restante, vence_el, vencido}` o `{tiene: false}`.
class BonoCartel {
  /// Créditos del bono que todavía no se usaron.
  final int restante;

  /// Hasta cuándo se pueden usar. `null` si la base no lo informó.
  final DateTime? venceEl;

  const BonoCartel({required this.restante, this.venceEl});

  /// Devuelve el cartel a mostrar, o `null` si no hay que mostrar nada.
  ///
  /// Se descarta cuando: la respuesta no es un mapa (RPC caído o versión
  /// vieja de la base), no hay bono, ya se usó entero, o venció. El
  /// vencimiento se cree tanto por la bandera `vencido` que calcula la base
  /// como por la fecha, para que un reloj desfasado no muestre un regalo que
  /// ya no sirve.
  static BonoCartel? leer(Object? respuesta, {DateTime? hoy}) {
    if (respuesta is! Map) return null;
    final bono = Map<String, dynamic>.from(respuesta);
    if (bono['tiene'] != true) return null;

    final restante = (bono['restante'] as num?)?.toInt() ?? 0;
    if (restante <= 0) return null;
    if (bono['vencido'] == true) return null;

    final venceEl = _fecha(bono['vence_el']);
    if (venceEl != null) {
      final ahora = hoy ?? DateTime.now();
      final finDelDia = DateTime(venceEl.year, venceEl.month, venceEl.day, 23, 59, 59);
      if (finDelDia.isBefore(ahora)) return null;
    }

    return BonoCartel(restante: restante, venceEl: venceEl);
  }

  static DateTime? _fecha(Object? valor) {
    if (valor == null) return null;
    return DateTime.tryParse(valor.toString());
  }
}
