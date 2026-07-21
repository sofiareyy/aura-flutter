class Estudio {
  final int? id;
  final String nombre;

  /// Todas las categorías del estudio. Un estudio puede ser Pilates + Barre
  /// + Yoga a la vez, así que la fuente de verdad es esta lista y no el
  /// escalar `categoria`.
  final List<String> categorias;

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
    this.categorias = const [],
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

  /// Categoría principal (la primera). Se mantiene para los lugares donde la
  /// UI muestra un único badge y para compatibilidad con la columna
  /// `estudios.categoria`, que sigue existiendo sincronizada.
  String get categoria => categorias.isEmpty ? '' : categorias.first;

  /// Etiqueta corta para las cards: hasta dos categorías y un "+N".
  String get categoriasLabel {
    if (categorias.isEmpty) return '';
    if (categorias.length <= 2) return categorias.join(' · ');
    return '${categorias.take(2).join(' · ')} +${categorias.length - 2}';
  }

  /// True si el estudio pertenece a `categoria` (case-insensitive).
  bool tieneCategoria(String categoria) {
    final target = categoria.trim().toLowerCase();
    return categorias.any((c) => c.trim().toLowerCase() == target);
  }

  factory Estudio.fromMap(Map<String, dynamic> map) {
    return Estudio(
      id: (map['id'] as num?)?.toInt(),
      nombre: map['nombre'] ?? '',
      categorias: parseCategorias(map),
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

  /// Lee `categorias` (text[]) con fallback al escalar `categoria` para las
  /// filas que todavía no migraron. PostgREST puede devolver el array como
  /// `List` o como literal de Postgres (`"{Yoga,Barre}"`), igual que
  /// `galeria_urls`; cubrimos los dos casos.
  static List<String> parseCategorias(Map<String, dynamic> map) {
    final raw = map['categorias'];
    final parsed = _parseStringList(raw);
    if (parsed.isNotEmpty) return parsed;

    final legacy = map['categoria']?.toString().trim() ?? '';
    return legacy.isEmpty ? const [] : [legacy];
  }

  static List<String> _parseStringList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((entry) => entry?.toString().trim() ?? '')
          .where((entry) => entry.isNotEmpty)
          .toList();
    }
    if (raw is String) {
      var s = raw.trim();
      if (s.isEmpty || s == '{}') return const [];
      if (s.startsWith('{') && s.endsWith('}')) {
        s = s.substring(1, s.length - 1);
      }
      return s
          .split(',')
          .map((e) => e.trim().replaceAll(RegExp(r'^"|"$'), ''))
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'categorias': categorias,
      // Se mantiene sincronizada con la primera categoría: hay queries y
      // vistas legacy que todavía leen el escalar.
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
