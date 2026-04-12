class Reserva {
  final int? id;
  final String usuarioId;
  final int claseId;
  final String? estado;
  final int? creditosUsados;
  final String? codigoQr;
  final DateTime? creadoEn;
  Map<String, dynamic>? clase;
  Map<String, dynamic>? estudio;

  Reserva({
    this.id,
    required this.usuarioId,
    required this.claseId,
    this.estado,
    this.creditosUsados,
    this.codigoQr,
    this.creadoEn,
    this.clase,
    this.estudio,
  });

  factory Reserva.fromMap(Map<String, dynamic> map) {
    return Reserva(
      id: (map['id'] as num?)?.toInt(),
      usuarioId: map['usuario_id']?.toString() ?? '',
      claseId: (map['clase_id'] as num?)?.toInt() ?? 0,
      estado: map['estado'],
      creditosUsados: (map['creditos_usados'] as num?)?.toInt(),
      codigoQr: map['codigo_qr'],
      creadoEn: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }

  bool get estaActiva => estado == 'confirmada' || estado == 'pendiente';
  bool get estaCancelada => estado == 'cancelada';
  bool get estaCompletada => estado == 'completada';

  Map<String, dynamic> toMap() {
    return {
      'usuario_id': usuarioId,
      'clase_id': claseId,
      'estado': estado,
      'creditos_usados': creditosUsados,
      'codigo_qr': codigoQr,
    };
  }
}
