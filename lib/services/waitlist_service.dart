import 'package:supabase_flutter/supabase_flutter.dart';

class WaitlistService {
  final _client = Supabase.instance.client;

  /// Returns true if the user is already on the waitlist for [claseId].
  Future<bool> isOnWaitlist(int claseId, String userId) async {
    final rows = await _client
        .from('lista_espera')
        .select('id')
        .eq('clase_id', claseId)
        .eq('usuario_id', userId)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  /// Cuánta gente hay en la lista de espera de [claseId].
  ///
  /// Va por RPC: antes contaba filas del lado cliente, y eso dependía de la
  /// policy `waitlist_count_public` (USING true), que exponía el `usuario_id`
  /// de todos a cualquiera — incluido un invitado. Esa policy se cerró, así
  /// que contar filas ahora devuelve siempre 0.
  /// `waitlist_count` devuelve solo el número, nunca identidades.
  Future<int> getCount(int claseId) async {
    try {
      final res =
          await _client.rpc('waitlist_count', params: {'p_clase_id': claseId});
      return (res as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Adds the user to the waitlist. Silently ignores duplicate entries.
  Future<void> join(int claseId, String userId) async {
    await _client.from('lista_espera').upsert({
      'clase_id': claseId,
      'usuario_id': userId,
    }, onConflict: 'clase_id,usuario_id');
  }

  /// Removes the user from the waitlist.
  Future<void> leave(int claseId, String userId) async {
    await _client
        .from('lista_espera')
        .delete()
        .eq('clase_id', claseId)
        .eq('usuario_id', userId);
  }
}
