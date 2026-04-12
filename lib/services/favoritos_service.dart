import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/estudio.dart';

class FavoritosService {
  final _client = Supabase.instance.client;

  Future<bool> esFavorito(String usuarioId, int estudioId) async {
    try {
      final data = await _client
          .from('favoritos_estudios')
          .select('estudio_id')
          .eq('usuario_id', usuarioId)
          .eq('estudio_id', estudioId)
          .maybeSingle();
      return data != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> toggleFavorito({
    required String usuarioId,
    required int estudioId,
    required bool favorito,
  }) async {
    if (favorito) {
      await _client.from('favoritos_estudios').upsert(
        {
          'usuario_id': usuarioId,
          'estudio_id': estudioId,
        },
        onConflict: 'usuario_id,estudio_id',
      );
      return;
    }

    await _client
        .from('favoritos_estudios')
        .delete()
        .eq('usuario_id', usuarioId)
        .eq('estudio_id', estudioId);
  }

  Future<List<Estudio>> getFavoritos(String usuarioId) async {
    try {
      final rows = await _client
          .from('favoritos_estudios')
          .select('estudio_id')
          .eq('usuario_id', usuarioId)
          .order('created_at', ascending: false);

      final ids = (rows as List)
          .map((row) => (row['estudio_id'] as num?)?.toInt())
          .whereType<int>()
          .toList();

      if (ids.isEmpty) return const [];

      final estudios = await _client
          .from('estudios')
          .select()
          .inFilter('id', ids);

      final byId = {
        for (final row in (estudios as List))
          (row['id'] as num?)?.toInt(): Estudio.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
      };

      return ids.map((id) => byId[id]).whereType<Estudio>().toList();
    } catch (_) {
      return const [];
    }
  }
}
