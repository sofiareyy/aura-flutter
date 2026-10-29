/// A dónde lleva el toque de cada tipo de notificación. `null` = a ningún
/// lado (la app sólo se abre). Función pura: la navegación la hace main.dart.
///
/// Mismas rutas que antes del 29/10/2026; sólo se sacaron de main.dart para
/// poder probarlas sin levantar la app.
String? rutaDeNotificacion(Map<String, dynamic> data) {
  final tipo = data['tipo']?.toString();
  final codigoQr = data['codigo_qr']?.toString() ?? '';
  switch (tipo) {
    case 'recordatorio_clase':
      return codigoQr.isNotEmpty
          ? '/reserva-confirmada/$codigoQr?from_notif=true'
          : null;
    case 'recordatorio_resena':
      // Va a MIS RESERVAS (2/9). Antes iba al perfil del estudio, donde la
      // reseña se guardaba SIN clase. En Mis Reservas cada fila ES una
      // reserva, así que la reseña queda atada a la asistencia concreta. No
      // se linkea a la clase exacta porque el push no manda ids.
      return '/mis-reservas';
    case 'resena_nueva':
      // Le llega al ESTUDIO cuando una alumna deja una reseña. `?dueno=1`
      // sólo cambia el título a "Tus reseñas". Sin el id (notificaciones
      // viejas), el Dashboard tiene la tarjeta de reseñas.
      final estudioId = data['estudio_id'];
      return estudioId != null
          ? '/estudio/$estudioId/resenas?dueno=1'
          : '/estudio/dashboard';
    case 'inactividad_creditos':
      return '/explorar';
    case 'pre_confirmada':
      // "Se liberó un lugar" (lista de espera): tiene 30 min para confirmar,
      // así que va directo a su pre-reserva. push-enviar manda el codigo_qr;
      // si no vino, Mis reservas.
      return codigoQr.isNotEmpty
          ? '/reserva-confirmada/$codigoQr?from_notif=true'
          : '/mis-reservas';
  }
  return null;
}
