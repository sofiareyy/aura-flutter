class Clase {
  final int? id;
  final int estudioId;
  final String nombre;
  final String? instructor;
  final DateTime? fecha;
  final int? duracionMin;
  final int? creditos;
  final int? lugaresTotal;
  final int? lugaresDisponibles;
  Estudio? estudio;

  Clase({
    this.id,
    required this.estudioId,
    required this.nombre,
    this.instructor,
    this.fecha,
    this.duracionMin,
    this.creditos,
    this.lugaresTotal,
    this.lugaresDisponibles,
    this.estudio,
  });

  factory Clase.fromMap(Map<String, dynamic> map) {
    return Clase(
      id: (map['id'] as num?)?.toInt(),
      estudioId: (map['estudio_id'] as num?)?.toInt() ?? 0,
      nombre: map['nombre'] ?? '',
      instructor: map['instructor'],
      fecha: map['fecha'] != null
          ? DateTime.tryParse(map['fecha'].toString())
          : null,
      duracionMin: (map['duracion_min'] as num?)?.toInt(),
      creditos: (map['creditos'] as num?)?.toInt(),
      lugaresTotal: (map['lugares_total'] as num?)?.toInt(),
      lugaresDisponibles:
          (map['lugares_disponibles'] as num?)?.toInt() ??
          (map['lugares_ disponibles'] as num?)?.toInt(),
    );
  }

  bool get disponible => (lugaresDisponibles ?? 0) > 0;

  Map<String, dynamic> toMap() {
    return {
      'estudio_id': estudioId,
      'nombre': nombre,
      'instructor': instructor,
      'fecha': fecha?.toIso8601String(),
      'duracion_min': duracionMin,
      'creditos': creditos,
      'lugares_total': lugaresTotal,
      'lugares_disponibles': lugaresDisponibles,
    };
  }
}

// Forward declaration to avoid circular import
class Estudio {
  final String nombre;
  final String? fotoUrl;
  final String? barrio;
  const Estudio({required this.nombre, this.fotoUrl, this.barrio});
}
