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
  final List<String> galeriaUrls;
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
    this.galeriaUrls = const [],
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
      galeriaUrls: (map['galeria_urls'] as List?)
              ?.map((entry) => entry.toString())
              .where((entry) => entry.trim().isNotEmpty)
              .toList() ??
          const [],
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
      'galeria_urls': galeriaUrls,
      'lat': lat,
      'lng': lng,
    };
  }
}
