// La vuelta de Mercado Pago a /payment-result (16/11/2026).
//
// MP le AGREGA sus propios parámetros a nuestra back_url, incluido otro
// `status` (approved / rejected / null) y `collection_status`. Con
// `queryParameters` Dart se queda con el ÚLTIMO, o sea el de MP: nuestro
// `status=failure` llegaba como `rejected` (o `null` si la persona tocaba
// "volver"), ninguno coincidía con 'failure' y la pantalla iba a confirmar y
// terminaba en "Estamos procesando tu pago" para un pago rechazado.
//
// Además MP manda `payment_id=null` / `collection_id=null` como TEXTO cuando
// no hubo pago, y eso se usaba como id.

/// Qué mostrar: 'success' (ir a confirmar), 'failure' o 'pending'.
String estadoDeVueltaMp(Map<String, List<String>> params) {
  final valores = <String>[
    ...?params['status'],
    ...?params['collection_status'],
  ].map((v) => v.trim().toLowerCase()).where((v) => v.isNotEmpty).toList();

  // Si alguno dice aprobado, se confirma contra el servidor (que decide).
  if (valores.any((v) => v == 'success' || v == 'approved')) return 'success';
  if (valores.any(
    (v) => v == 'pending' || v == 'in_process' || v == 'in_mediation',
  )) {
    return 'pending';
  }
  if (valores.any(
    (v) => v == 'failure' || v == 'rejected' || v == 'cancelled' || v == 'null',
  )) {
    return 'failure';
  }
  // Sin status (vuelta manual, link viejo): se confirma igual.
  return 'success';
}

/// El primer id de pago de MP que sea de verdad (no vacío ni "null").
String? idDePagoMp(Map<String, List<String>> params) {
  for (final clave in const ['payment_id', 'collection_id']) {
    for (final v in params[clave] ?? const <String>[]) {
      final t = v.trim();
      if (t.isNotEmpty && t.toLowerCase() != 'null') return t;
    }
  }
  return null;
}
