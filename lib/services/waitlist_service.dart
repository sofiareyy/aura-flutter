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
  /// Puesto de la usuaria logueada en la lista de espera de [claseId], o
  /// null si no está anotada.
  ///
  /// `posicion` NO es una columna de `lista_espera`: el orden es por llegada
  /// (`created_at`) y el puesto lo deriva la base con `row_number()` en
  /// `waitlist_mis_posiciones()`. La policy `waitlist_own` sólo deja ver la
  /// fila propia, así que contar "cuántas hay antes que yo" desde el cliente
  /// devolvería siempre 1 — tiene que salir de la RPC.
  Future<({int posicion, int total})?> getMiPosicion(int claseId) async {
    try {
      final rows = await _client.rpc('waitlist_mis_posiciones');
      for (final r in (rows as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        if ((m['clase_id'] as num?)?.toInt() == claseId) {
          return (
            posicion: (m['posicion'] as num).toInt(),
            total: (m['total'] as num).toInt(),
          );
        }
      }
    } catch (_) {
      // Sin puesto la UI cae al texto de "N esperando", que ya funcionaba.
    }
    return null;
  }

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
