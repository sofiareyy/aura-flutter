// La vista previa de cambiar un servicio de precio fijo, y el texto que ve
// Sofía antes de confirmar. Espejo de lo que devuelve
// `admin_set_servicio_precio(..., p_solo_preview := true)`.
//
// Por qué está separado de la pantalla: es la única pieza de esta feature que
// habla de PLATA en palabras, y tiene que poder testearse sin levantar
// Supabase. La regla que enuncia es la que rige en la base (3/9/2026):
//   · las clases pasadas no se tocan;
//   · las futuras que ya tienen una reserva viva quedan selladas al precio
//     con el que se cobró;
//   · sólo las futuras sin reserva toman el precio nuevo.
// Los números NO se calculan acá: vienen de la base, con el mismo predicado
// que usa la RPC al aplicar. Si esta pantalla dijera un número y la RPC
// hiciera otro, el bug sería de la base, no de este archivo.

class ServicioPreview {
  final String servicio;
  final int creditos;
  final bool activo;
  final int? precioAnterior;
  final bool? activoAnterior;

  /// Futuras SIN reserva viva: las que cambian.
  final int afectadas;

  /// Futuras CON reserva viva: NO cambian.
  final int selladas;

  /// Pasadas con la categoría: no se tocan.
  final int pasadas;

  /// Horarios de la grilla con la categoría: nacen con el precio nuevo.
  final int horarios;

  const ServicioPreview({
    required this.servicio,
    required this.creditos,
    required this.activo,
    required this.afectadas,
    required this.selladas,
    required this.pasadas,
    required this.horarios,
    this.precioAnterior,
    this.activoAnterior,
  });

  /// Lee el jsonb de la RPC. Tolerante: un campo ausente vale 0/null, nunca
  /// rompe la confirmación.
  factory ServicioPreview.fromJson(Map<String, dynamic> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return ServicioPreview(
      servicio: j['servicio']?.toString() ?? '',
      creditos: n('creditos'),
      activo: j['activo'] != false,
      afectadas: n('clases_afectadas'),
      selladas: n('clases_selladas'),
      pasadas: n('clases_pasadas'),
      horarios: n('horarios_actualizados'),
      precioAnterior: (j['precio_anterior'] as num?)?.toInt(),
      activoAnterior: j['activo_anterior'] as bool?,
    );
  }

  bool get esNuevo => precioAnterior == null;
  bool get cambiaPrecio => precioAnterior != null && precioAnterior != creditos;
}

String _cr(int n) => '$n cr';
String _clases(int n) => n == 1 ? '1 clase' : '$n clases';
String _horarios(int n) => n == 1 ? '1 horario' : '$n horarios';

/// El título del cartel de confirmación.
String tituloConfirmacionServicio(ServicioPreview p, String estudio) {
  if (!p.activo) return 'Desactivar ${p.servicio} en $estudio';
  if (p.esNuevo) return '${p.servicio} a ${_cr(p.creditos)} en $estudio';
  if (p.cambiaPrecio) {
    return '${p.servicio}: de ${_cr(p.precioAnterior!)} a ${_cr(p.creditos)}';
  }
  return '${p.servicio} a ${_cr(p.creditos)} en $estudio';
}

/// El cuerpo del cartel: qué cambia y, sobre todo, qué NO cambia.
///
/// Siempre dice las tres cosas de la regla, con número, para que Sofía sepa
/// exactamente qué está aprobando. Un 0 se dice igual: "0 clases futuras sin
/// reserva" es información, no ruido.
String mensajeConfirmacionServicio(ServicioPreview p) {
  final b = StringBuffer();
  if (!p.activo) {
    b.writeln(
      'Las clases ya cargadas conservan su precio y las nuevas vuelven al '
      'precio del estudio.',
    );
    b.writeln();
    b.writeln('Ninguna reserva cambia.');
    return b.toString().trimRight();
  }

  b.writeln(
    '• ${_clases(p.afectadas)} futura${p.afectadas == 1 ? '' : 's'} sin '
    'reserva pasa${p.afectadas == 1 ? '' : 'n'} a ${_cr(p.creditos)}.',
  );
  if (p.selladas > 0) {
    b.writeln(
      '• ${_clases(p.selladas)} futura${p.selladas == 1 ? '' : 's'} ya '
      'reservada${p.selladas == 1 ? '' : 's'} NO cambia'
      '${p.selladas == 1 ? '' : 'n'}: queda${p.selladas == 1 ? '' : 'n'} '
      'al precio con el que se cobró.',
    );
  } else {
    b.writeln('• No hay clases futuras ya reservadas.');
  }
  b.writeln(
    '• ${_clases(p.pasadas)} pasada${p.pasadas == 1 ? '' : 's'} no se '
    'toca${p.pasadas == 1 ? '' : 'n'}.',
  );
  if (p.horarios > 0) {
    b.writeln(
      '• ${_horarios(p.horarios)} de la grilla nace${p.horarios == 1 ? '' : 'n'} '
      'con el precio nuevo.',
    );
  }
  b.writeln();
  b.write('Ninguna reserva ni liquidación cambia.');
  return b.toString();
}

/// El aviso corto después de aplicar.
String resumenAplicadoServicio(ServicioPreview p) {
  if (!p.activo) return '${p.servicio} desactivado.';
  final n = p.afectadas;
  return '${p.servicio} a ${_cr(p.creditos)}. '
      '${_clases(n)} actualizada${n == 1 ? '' : 's'}.';
}
