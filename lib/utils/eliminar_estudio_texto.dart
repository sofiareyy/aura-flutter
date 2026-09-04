// Eliminar un estudio desde el backoffice: el resumen que devuelve la base y
// las palabras del cartel. Separado de la pantalla porque es lo que decide si
// Sofía se entera de que está por borrar historial de plata, y tiene que
// poder testearse sin Supabase.
//
// La regla (4/9/2026):
//   · sin historial (0 reservas y 0 liquidaciones): se borra limpio;
//   · con historial: aviso fuerte con número y empujón a DESACTIVAR;
//   · siempre: hay que escribir el nombre del estudio, y el botón no se
//     habilita hasta que coincida.

class ResumenBorrado {
  final int id;
  final String nombre;
  final bool activo;
  final int clases;
  final int clasesFuturas;
  final int reservas;
  final int reservasFuturasVivas;
  final int creditosADevolver;
  final int alumnasAfectadas;
  final int liquidaciones;
  final int liquidacionesPagadas;
  final int montoPagado;
  final int resenas;
  final int accesos;
  final bool tieneHistorial;

  const ResumenBorrado({
    required this.id,
    required this.nombre,
    required this.activo,
    required this.clases,
    required this.clasesFuturas,
    required this.reservas,
    required this.reservasFuturasVivas,
    required this.creditosADevolver,
    required this.alumnasAfectadas,
    required this.liquidaciones,
    required this.liquidacionesPagadas,
    required this.montoPagado,
    required this.resenas,
    required this.accesos,
    required this.tieneHistorial,
  });

  factory ResumenBorrado.fromJson(Map<String, dynamic> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return ResumenBorrado(
      id: n('id'),
      nombre: j['nombre']?.toString() ?? '',
      activo: j['activo'] != false,
      clases: n('clases'),
      clasesFuturas: n('clases_futuras'),
      reservas: n('reservas'),
      reservasFuturasVivas: n('reservas_futuras_vivas'),
      creditosADevolver: n('creditos_a_devolver'),
      alumnasAfectadas: n('alumnas_afectadas'),
      liquidaciones: n('liquidaciones'),
      liquidacionesPagadas: n('liquidaciones_pagadas'),
      montoPagado: n('monto_pagado'),
      resenas: n('resenas'),
      accesos: n('accesos'),
      // Si la base no lo manda, se asume que SÍ hay historial: el cartel
      // fuerte de más nunca borra nada; el de menos, sí.
      tieneHistorial: j['tiene_historial'] != false,
    );
  }
}

/// El nombre escrito coincide con el del estudio. Sin distinguir mayúsculas
/// ni espacios de más: la barrera es ESCRIBIRLO, no acertar una mayúscula.
/// Es el mismo criterio que aplica la base al recibirlo.
bool nombreCoincide(String escrito, String nombre) =>
    escrito.trim().toLowerCase() == nombre.trim().toLowerCase();

String _pl(int n, String uno, String varios) => n == 1 ? '1 $uno' : '$n $varios';

/// El aviso fuerte cuando hay historial de plata. Null si no hay: un estudio
/// de prueba se borra limpio y no hace falta asustar.
String? advertenciaHistorial(ResumenBorrado r) {
  if (!r.tieneHistorial) return null;
  final partes = <String>[];
  if (r.reservas > 0) partes.add(_pl(r.reservas, 'reserva', 'reservas'));
  if (r.liquidaciones > 0) {
    final liq = _pl(r.liquidaciones, 'liquidación', 'liquidaciones');
    partes.add(r.liquidacionesPagadas > 0
        ? '$liq (${_pl(r.liquidacionesPagadas, 'pagada', 'pagadas')})'
        : liq);
  }
  final b = StringBuffer();
  b.write('Este estudio tiene ${partes.join(' y ')}. ');
  b.write('Si lo eliminás, se pierde ese historial de plata para siempre.');
  if (r.reservasFuturasVivas > 0) {
    b.write('\n\nAdemás, ');
    b.write(_pl(r.alumnasAfectadas, 'alumna tiene', 'alumnas tienen'));
    b.write(' ${_pl(r.reservasFuturasVivas, 'reserva futura', 'reservas futuras')}: ');
    b.write('se cancelan, se les devuelven ${r.creditosADevolver} créditos y se les avisa.');
  }
  b.write('\n\nSi sólo querés que no aparezca en la app, mejor desactivalo.');
  return b.toString();
}

/// Lo que se va, en una línea, para el cartel de cualquier estudio.
String detalleQueSeBorra(ResumenBorrado r) {
  final partes = <String>[
    _pl(r.clases, 'clase', 'clases'),
    if (r.resenas > 0) _pl(r.resenas, 'reseña', 'reseñas'),
    if (r.accesos > 0) _pl(r.accesos, 'acceso vinculado', 'accesos vinculados'),
  ];
  return 'Se borran ${partes.join(', ')}. No se puede deshacer.';
}

/// El aviso después de borrar, con lo que devolvió la base.
String resumenBorradoHecho(Map<String, dynamic> j) {
  int n(String k) => (j[k] as num?)?.toInt() ?? 0;
  final nombre = j['nombre']?.toString() ?? 'Estudio';
  final b = StringBuffer('$nombre eliminado. ');
  b.write('${_pl(n('clases'), 'clase', 'clases')} y ');
  b.write('${_pl(n('reservas'), 'reserva', 'reservas')} borradas');
  if (n('creditos_devueltos') > 0) {
    b.write(', ${n('creditos_devueltos')} créditos devueltos a ');
    b.write(_pl(n('alumnas_avisadas'), 'alumna', 'alumnas'));
  }
  b.write('.');
  return b.toString();
}
