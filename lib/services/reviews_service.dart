import 'package:supabase_flutter/supabase_flutter.dart';

class ReviewsService {
  final _supabase = Supabase.instance.client;

  String get _userId => _supabase.auth.currentUser?.id ?? '';

  Future<List<Map<String, dynamic>>> getReviewsForStudy(int estudioId) async {
    final rows = await _supabase
        .from('study_reviews')
        .select('id, estudio_id, usuario_id, clase_id, experiencia_label, rating, comentario, created_at, usuarios(nombre, email)')
        .eq('estudio_id', estudioId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Página de reseñas de un estudio, más nuevas primero.
  ///
  /// La usan las DOS puntas: la alumna que toca el promedio y el estudio que
  /// entra desde su Dashboard. Es la misma lista — la policy
  /// `study_reviews_select_all` es pública porque las reseñas se muestran en
  /// el perfil, así que no hay nada que separar por rol.
  ///
  /// [rating] filtra por estrellas (null = todas). [offset]/[limit] paginan:
  /// con 100+ reseñas traerlas todas de una sería lento y no aporta.
  Future<List<Map<String, dynamic>>> getReviewsPage(
    int estudioId, {
    int? rating,
    int offset = 0,
    int limit = 20,
  }) async {
    var query = _supabase
        .from('study_reviews')
        .select('id, estudio_id, usuario_id, clase_id, experiencia_label, '
            'rating, comentario, created_at, updated_at, '
            'clases(nombre, fecha, instructor)')
        .eq('estudio_id', estudioId);
    if (rating != null) query = query.eq('rating', rating);
    final rows = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Nombres de las autoras, en el formato que corresponde a quién mira.
  ///
  ///  · [esDueno] = el estudio: nombre COMPLETO vía `estudio_nombres_alumnas`
  ///    (tiene relación directa con sus alumnas y ya podía verlo).
  ///  · una alumna: ABREVIADO ("Juana S.") vía `resenas_nombres_publicos`,
  ///    que arma el recorte en SQL — el apellido completo nunca sale del
  ///    servidor.
  ///
  /// Si algo falla devuelve vacío y la pantalla muestra "Usuario Aura": una
  /// reseña sin nombre se lee igual, y es lo que pasaba hasta hoy.
  Future<Map<String, String>> getNombresAutoras(
    List<String> usuarioIds, {
    required bool esDueno,
  }) async {
    if (usuarioIds.isEmpty) return {};
    try {
      final data = await _supabase.rpc(
        esDueno ? 'estudio_nombres_alumnas' : 'resenas_nombres_publicos',
        params: {'p_ids': usuarioIds},
      );
      final out = <String, String>{};
      for (final row in (data as List)) {
        final id = row['id']?.toString();
        final nombre = row['nombre']?.toString().trim();
        if (id != null && nombre != null && nombre.isNotEmpty) {
          out[id] = nombre;
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Cuántas reseñas hay por cada puntaje: alimenta el desglose de barras y
  /// el promedio, sin traer las reseñas enteras.
  Future<Map<int, int>> getRatingBreakdown(int estudioId) async {
    final rows = await _supabase
        .from('study_reviews')
        .select('rating')
        .eq('estudio_id', estudioId);
    final out = {for (var i = 1; i <= 5; i++) i: 0};
    for (final r in (rows as List)) {
      final v = (r['rating'] as num?)?.toInt();
      if (v != null && v >= 1 && v <= 5) out[v] = out[v]! + 1;
    }
    return out;
  }

  Future<Map<String, dynamic>?> getMyReviewForStudy(int estudioId) async {
    if (_userId.isEmpty) return null;
    final row = await _supabase
        .from('study_reviews')
        .select('id, estudio_id, usuario_id, clase_id, experiencia_label, rating, comentario, created_at')
        .eq('estudio_id', estudioId)
        .eq('usuario_id', _userId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  /// La reseña de UNA reserva concreta, si ya existe.
  ///
  /// Es lo que Mis Reservas necesita para saber si mostrar "Dejar reseña" o
  /// "Ver mi reseña" en cada fila.
  Future<Map<String, dynamic>?> getMyReviewForReserva(int reservaId) async {
    if (_userId.isEmpty) return null;
    final row = await _supabase
        .from('study_reviews')
        .select('id, estudio_id, usuario_id, clase_id, reserva_id, rating, '
            'comentario, created_at')
        .eq('reserva_id', reservaId)
        .eq('usuario_id', _userId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  /// Las reseñas que la usuaria ya dejó, indexadas por reserva. Una sola
  /// consulta para toda la lista de Mis Reservas, en vez de una por fila.
  Future<Map<int, Map<String, dynamic>>> getMisResenasPorReserva() async {
    if (_userId.isEmpty) return {};
    try {
      final rows = await _supabase
          .from('study_reviews')
          .select('id, estudio_id, clase_id, reserva_id, rating, comentario')
          .eq('usuario_id', _userId)
          .not('reserva_id', 'is', null);
      final out = <int, Map<String, dynamic>>{};
      for (final r in (rows as List)) {
        final id = (r['reserva_id'] as num?)?.toInt();
        if (id != null) out[id] = Map<String, dynamic>.from(r);
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  /// ¿Se puede reseñar ESTA reserva? (modelo B, 2/9/2026)
  ///
  /// Dos condiciones: la clase ya pasó, y no la reseñó todavía. Antes el
  /// permiso era por estudio ("¿tomaste alguna clase acá?"), que con una
  /// reseña por asistencia ya no alcanza.
  Future<bool> canReviewReserva({
    required int reservaId,
    required DateTime? fechaClase,
    required String? estadoReserva,
  }) async {
    if (_userId.isEmpty) return false;
    if (estadoReserva == 'cancelada' ||
        estadoReserva == 'cancelada_por_estudio') {
      return false;
    }
    if (fechaClase == null || !fechaClase.isBefore(DateTime.now())) {
      return false;
    }
    return await getMyReviewForReserva(reservaId) == null;
  }

  Future<bool> canReviewStudy({
    required int estudioId,
    int? claseId,
  }) async {
    if (_userId.isEmpty) return false;

    final reservas = await _supabase
        .from('reservas')
        .select('id, estado, clase_id, created_at')
        .eq('usuario_id', _userId)
        .neq('estado', 'cancelada');

    final reservaList = List<Map<String, dynamic>>.from(reservas as List);
    if (reservaList.isEmpty) return false;

    final classIds = reservaList
        .map((row) => (row['clase_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .toList();
    if (classIds.isEmpty) return false;

    var clasesQuery = _supabase
        .from('clases')
        .select('id, estudio_id, fecha')
        .inFilter('id', classIds)
        .eq('estudio_id', estudioId);

    if (claseId != null) {
      clasesQuery = clasesQuery.eq('id', claseId) as dynamic;
    }

    final clases = await clasesQuery;
    final now = DateTime.now();
    for (final row in (clases as List)) {
      final fecha = DateTime.tryParse(row['fecha']?.toString() ?? '');
      if (fecha != null && fecha.isBefore(now)) {
        return true;
      }
    }
    return false;
  }

  /// Guarda (o edita) una reseña.
  ///
  /// Con [reservaId] es una reseña POR ASISTENCIA (modelo B): cada reserva
  /// pasada puede tener la suya. Sin él cae al comportamiento viejo —una por
  /// estudio— que es el que usan el botón del perfil y las apps que todavía
  /// no tienen este build.
  ///
  /// ⚠️ El UNIQUE de la base sigue siendo `(estudio_id, usuario_id)` hasta la
  /// etapa 3 (tras la adopción de la 1.0.7). Por eso acá NO se puede usar
  /// `onConflict: reserva_id`: ese índice todavía no existe y daría 42P10.
  /// Mientras tanto se resuelve a mano: si ya hay reseña de esta reserva se
  /// actualiza por id, y si no se inserta.
  Future<void> upsertStudyReview({
    required int estudioId,
    int? claseId,
    int? reservaId,
    String? experienciaLabel,
    required int rating,
    required String comentario,
  }) async {
    if (_userId.isEmpty) throw Exception('Necesitás iniciar sesión.');

    if (reservaId != null) {
      final existente = await getMyReviewForReserva(reservaId);
      if (existente != null) {
        await _supabase.from('study_reviews').update({
          'rating': rating,
          'comentario': comentario.trim(),
          'clase_id': claseId,
          'experiencia_label': experienciaLabel,
        }).eq('id', existente['id']);
      } else {
        try {
          await _supabase.from('study_reviews').insert({
            'estudio_id': estudioId,
            'usuario_id': _userId,
            'clase_id': claseId,
            'reserva_id': reservaId,
            'experiencia_label': experienciaLabel,
            'rating': rating,
            'comentario': comentario.trim(),
          });
        } on PostgrestException catch (e) {
          // 23505 = choca con el UNIQUE VIEJO (estudio_id, usuario_id), que
          // sigue puesto hasta la etapa 3. Hasta entonces una alumna tiene
          // UNA reseña por estudio: si reseña una segunda clase del mismo
          // lugar, se actualiza la que ya tenía y se la mueve a esta reserva.
          // Degradar así es lo correcto mientras dura la transición: la
          // alumna ve su reseña guardada, no un error. El día que caiga el
          // índice viejo, este catch deja de dispararse solo — sin tocar
          // Dart de nuevo.
          if (e.code != '23505') rethrow;
          await _supabase
              .from('study_reviews')
              .update({
                'rating': rating,
                'comentario': comentario.trim(),
                'clase_id': claseId,
                'reserva_id': reservaId,
                'experiencia_label': experienciaLabel,
              })
              .eq('estudio_id', estudioId)
              .eq('usuario_id', _userId);
        }
      }
    } else {
      await _supabase.from('study_reviews').upsert({
        'estudio_id': estudioId,
        'usuario_id': _userId,
        'clase_id': claseId,
        'experiencia_label': experienciaLabel,
        'rating': rating,
        'comentario': comentario.trim(),
      }, onConflict: 'estudio_id,usuario_id');
    }

    // Recalcular rating promedio del estudio
    try {
      final ratings = await _supabase
          .from('study_reviews')
          .select('rating')
          .eq('estudio_id', estudioId);
      final list = (ratings as List);
      if (list.isNotEmpty) {
        final avg = list
                .map((r) => (r['rating'] as num).toDouble())
                .reduce((a, b) => a + b) /
            list.length;
        await _supabase
            .from('estudios')
            .update({'rating': avg}).eq('id', estudioId);
      }
    } catch (_) {}
  }
}
