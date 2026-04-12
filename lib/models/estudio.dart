class Estudio {
  final int? id;
  final String nombre;
  final String categoria;
  final String? direccion;
  final String? barrio;
  final String? descripcion;
  final double? rating;
  final String? instagram;
  final String? whatsapp;
  final String? web;
  final String? fotoUrl;
  final double? lat;
  final double? lng;

  const Estudio({
    this.id,
    required this.nombre,
    required this.categoria,
    this.direccion,
    this.barrio,
    this.descripcion,
    this.rating,
    this.instagram,
    this.whatsapp,
    this.web,
    this.fotoUrl,
    this.lat,
    this.lng,
  });

  factory Estudio.fromMap(Map<String, dynamic> map) {
    return Estudio(
      id: (map['id'] as num?)?.toInt(),
      nombre: map['nombre'] ?? '',
      categoria: map['categoria'] ?? '',
      direccion: map['direccion'],
      barrio: map['barrio'],
      descripcion: map['descripcion'],
      rating: (map['rating'] as num?)?.toDouble(),
      instagram: map['instagram'],
      whatsapp: map['whatsapp'],
      web: map['web'],
      fotoUrl: map['foto_url'],
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'categoria': categoria,
      'direccion': direccion,
      'barrio': barrio,
      'descripcion': descripcion,
      'rating': rating,
      'instagram': instagram,
      'whatsapp': whatsapp,
      'web': web,
      'foto_url': fotoUrl,
      'lat': lat,
      'lng': lng,
    };
  }
}
