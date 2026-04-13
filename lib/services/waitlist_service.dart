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

  /// Returns the number of people currently on the waitlist for [claseId].
  Future<int> getCount(int claseId) async {
    final rows = await _client
        .from('lista_espera')
        .select('id')
        .eq('clase_id', claseId);
    return (rows as List).length;
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
