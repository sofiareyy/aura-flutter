import 'package:supabase_flutter/supabase_flutter.dart';

class AdminService {
  final _client = Supabase.instance.client;

  Future<bool> isCurrentUserAdmin() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return false;
    try {
      final data = await _client
          .from('admin_users')
          .select('user_id')
          .eq('user_id', userId)
          .maybeSingle();
      return data != null;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getDashboardMetrics({
    DateTime? from,
    DateTime? to,
  }) async {
    final res = await _client.rpc(
      'admin_dashboard_metrics',
      params: {
        'p_from': from?.toIso8601String(),
        'p_to': to?.toIso8601String(),
      },
    );
    final m = Map<String, dynamic>.from((res as List).first as Map);

    final now = DateTime.now();
    final fromStr = (from ?? now.subtract(const Duration(days: 30))).toIso8601String();
    final toStr = (to ?? now).toIso8601String();
    final weekEnd = now.add(const Duration(days: 7));
    final venceHasta = now.add(const Duration(days: 3)).toIso8601String();
    final hace24h = now.subtract(const Duration(hours: 24)).toIso8601String();

    try {
      final results = await Future.wait([
        _client.from('usuarios').select('creditos').not('creditos', 'is', null),
        _client.from('reservas').select('usuario_id').gte('created_at', fromStr).lte('created_at', toStr).neq('estado', 'cancelada'),
        _client.from('clases').select('instructor').not('instructor', 'is', null).gte('fecha', fromStr).lte('fecha', toStr),
        _client.from('reservas').select('created_at').gte('created_at', fromStr).lte('created_at', toStr).neq('estado', 'cancelada'),
        _client.from('estudios').select('id').eq('activo', true),
        _client.from('clases').select('estudio_id').gte('fecha', now.toIso8601String()).lte('fecha', weekEnd.toIso8601String()),
        _client.from('usuarios').select('id').not('creditos_vencimiento', 'is', null).gt('creditos', 0).lte('creditos_vencimiento', venceHasta).gte('creditos_vencimiento', now.toIso8601String()),
        _client.from('reservas').select('id').eq('estado', 'confirmada').isFilter('checked_in_at', null).lte('created_at', hace24h),
      ]);

      // Créditos en circulación
      final creditosCirculacion = (results[0] as List).fold<int>(0, (s, r) => s + ((r['creditos'] as num?)?.toInt() ?? 0));

      // Tasa de conversión
      final usuariosQueReservaron = (results[1] as List).map((r) => r['usuario_id']).toSet().length;
      final usuariosTotal = (m['usuarios_total'] as num?)?.toInt() ?? 1;
      final tasaConversion = usuariosTotal > 0 ? (usuariosQueReservaron * 100 / usuariosTotal).round() : 0;

      // Top instructor
      final instructorCount = <String, int>{};
      for (final row in (results[2] as List)) {
        final ins = (row['instructor'] as String?)?.trim() ?? '';
        if (ins.isNotEmpty) instructorCount[ins] = (instructorCount[ins] ?? 0) + 1;
      }
      final topInstructor = instructorCount.isEmpty
          ? 'Sin datos'
          : instructorCount.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

      // Hora pico
      final horaCount = <int, int>{};
      for (final row in (results[3] as List)) {
        final dt = DateTime.tryParse(row['created_at']?.toString() ?? '');
        if (dt != null) horaCount[dt.toLocal().hour] = (horaCount[dt.toLocal().hour] ?? 0) + 1;
      }
      final horaPico = horaCount.isEmpty
          ? 'Sin datos'
          : '${horaCount.entries.reduce((a, b) => a.value >= b.value ? a : b).key}:00 hs';

      // Alertas
      final estudiosActivos = (results[4] as List).map((r) => (r['id'] as num?)?.toInt()).toSet();
      final estudiosConClases = (results[5] as List).map((r) => (r['estudio_id'] as num?)?.toInt()).toSet();
      final estudiosSinClases = estudiosActivos.difference(estudiosConClases).length;
      final creditosVenciendo = (results[6] as List).length;
      final reservasSinCheckIn = (results[7] as List).length;

      final alertas = <String>[];
      if (estudiosSinClases > 0) alertas.add('$estudiosSinClases estudio${estudiosSinClases > 1 ? "s" : ""} sin clases esta semana');
      if (creditosVenciendo > 0) alertas.add('$creditosVenciendo usuario${creditosVenciendo > 1 ? "s" : ""} con créditos por vencer en 3 días');
      if (reservasSinCheckIn > 0) alertas.add('$reservasSinCheckIn reserva${reservasSinCheckIn > 1 ? "s" : ""} confirmada${reservasSinCheckIn > 1 ? "s" : ""} sin check-in hace +24 hs');

      m['creditos_circulacion'] = creditosCirculacion;
      m['tasa_conversion'] = tasaConversion;
      m['top_instructor'] = topInstructor;
      m['hora_pico'] = horaPico;
      m['alertas'] = alertas;
    } catch (_) {
      // Métricas extendidas son opcionales; no fallan el dashboard
      m.putIfAbsent('creditos_circulacion', () => 0);
      m.putIfAbsent('tasa_conversion', () => 0);
      m.putIfAbsent('top_instructor', () => 'Sin datos');
      m.putIfAbsent('hora_pico', () => 'Sin datos');
      m.putIfAbsent('alertas', () => <String>[]);
    }

    return m;
  }

  Future<List<Map<String, dynamic>>> listUsuarios({String? search}) async {
    final res = await _client.rpc(
      'admin_list_users',
      params: {'p_search': (search ?? '').trim().isEmpty ? null : search!.trim()},
    );
    return List<Map<String, dynamic>>.from(res as List).where((row) {
      final rol = row['rol']?.toString() ?? '';
      return rol != 'estudio' && rol != 'admin_estudio';
    }).toList();
  }

  Future<void> adjustCreditos({
    required String userId,
    required int delta,
  }) async {
    await _client.rpc(
      'admin_adjust_user_credits',
      params: {
        'p_user_id': userId,
        'p_delta': delta,
      },
    );
  }

  Future<void> updateUsuario({
    required String userId,
    required String nombre,
    required String? plan,
  }) async {
    await _client.rpc(
      'admin_update_user',
      params: {
        'p_user_id': userId,
        'p_nombre': nombre.trim(),
        'p_plan': plan == null || plan.trim().isEmpty ? null : plan.trim(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> listEstudios({String? search}) async {
    try {
      final res = await _client.rpc(
        'admin_list_studios',
        params: {'p_search': (search ?? '').trim().isEmpty ? null : search!.trim()},
      );
      return List<Map<String, dynamic>>.from(res as List);
    } catch (_) {
      final query = _client.from('estudios').select().order('nombre');
      final rows = await (search == null || search.trim().isEmpty
          ? query
          : _client
              .from('estudios')
              .select()
              .or(
                'nombre.ilike.%${search.trim()}%,barrio.ilike.%${search.trim()}%,categoria.ilike.%${search.trim()}%',
              )
              .order('nombre'));
      final studios = List<Map<String, dynamic>>.from(rows as List).map((e) {
        final row = Map<String, dynamic>.from(e);
        row['activo'] = row['activo'] ?? true;
        return row;
      }).toList();

      final estudioIds = studios
          .map((row) => (row['id'] as num?)?.toInt())
          .whereType<int>()
          .toList();
      if (estudioIds.isEmpty) return studios;

      final users = await _client
          .from('usuarios')
          .select('email, rol, estudio_id')
          .inFilter('estudio_id', estudioIds)
          .inFilter('rol', ['estudio', 'admin_estudio']);

      final accessByStudio = <int, List<String>>{};
      for (final item in List<Map<String, dynamic>>.from(users as List)) {
        final estudioId = (item['estudio_id'] as num?)?.toInt();
        final email = item['email']?.toString().trim() ?? '';
        if (estudioId == null || email.isEmpty) continue;
        accessByStudio.putIfAbsent(estudioId, () => []).add(email);
      }

      for (final row in studios) {
        final estudioId = (row['id'] as num?)?.toInt();
        final emails = estudioId == null ? <String>[] : (accessByStudio[estudioId] ?? <String>[]);
        emails.sort();
        row['admin_count'] =
            ((row['admin_count'] as num?)?.toInt() ?? emails.length);
        row['admin_email'] = emails.isEmpty ? null : emails.first;
        row['admin_emails'] = emails.join(', ');
      }
      return studios;
    }
  }

  Future<void> linkEstudioAccess({
    required int estudioId,
    required String email,
  }) async {
    final normalized = email.trim().toLowerCase();
    try {
      await _client.rpc(
        'admin_link_estudio_access',
        params: {
          'p_estudio_id': estudioId,
          'p_email': email.trim(),
        },
      );
      return;
    } catch (_) {}

    final users = await _client.from('usuarios').select('id, email');
    Map<String, dynamic>? match;
    for (final row in List<Map<String, dynamic>>.from(users as List)) {
      if ((row['email']?.toString().trim().toLowerCase() ?? '') ==
          normalized) {
        match = row;
        break;
      }
    }

    if (match == null) {
      throw Exception(
        'No existe una cuenta Aura con ese email. Revisá mayúsculas o pedile que se registre primero.',
      );
    }

    await _client.from('usuarios').update({
      'rol': 'admin_estudio',
      'estudio_id': estudioId,
    }).eq('id', match['id']);
  }

  Future<List<Map<String, dynamic>>> listEstudioAccesses({
    required int estudioId,
  }) async {
    final res = await _client.rpc(
      'admin_list_studio_accesses',
      params: {'p_estudio_id': estudioId},
    );
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<void> removeEstudioAccess({
    required int estudioId,
    required String userId,
  }) async {
    await _client.rpc(
      'admin_remove_studio_access',
      params: {
        'p_estudio_id': estudioId,
        'p_user_id': userId,
      },
    );
  }

  Future<List<String>> listStudyCategories() async {
    try {
      final res = await _client.rpc('admin_list_studio_categories');
      return (res as List)
          .map((e) => (e as Map)['nombre']?.toString() ?? '')
          .where((e) => e.trim().isNotEmpty)
          .toList();
    } catch (_) {
      final rows = await _client
          .from('estudios')
          .select('categoria')
          .not('categoria', 'is', null);
      final values = (rows as List)
          .map((e) => (e as Map)['categoria']?.toString() ?? '')
          .where((e) => e.trim().isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      return values;
    }
  }

  Future<void> addStudyCategory(String nombre) async {
    await _client.rpc(
      'admin_add_studio_category',
      params: {'p_nombre': nombre.trim()},
    );
  }

  Future<void> renameStudyCategory({
    required String oldName,
    required String newName,
  }) async {
    await _client.rpc(
      'admin_rename_studio_category',
      params: {
        'p_old_name': oldName.trim(),
        'p_new_name': newName.trim(),
      },
    );
  }

  Future<void> deleteStudyCategory(String nombre) async {
    await _client.rpc(
      'admin_delete_studio_category',
      params: {'p_nombre': nombre.trim()},
    );
  }

  Future<void> saveEstudio({
    int? estudioId,
    required String nombre,
    required String categoria,
    String? barrio,
    String? direccion,
    String? descripcion,
    String? fotoUrl,
    String? instagram,
    String? whatsapp,
    String? web,
    double? lat,
    double? lng,
    required bool activo,
  }) async {
    await _client.rpc(
      'admin_upsert_estudio',
      params: {
        'p_estudio_id': estudioId,
        'p_nombre': nombre.trim(),
        'p_categoria': categoria.trim(),
        'p_barrio': barrio?.trim().isEmpty == true ? null : barrio?.trim(),
        'p_direccion':
            direccion?.trim().isEmpty == true ? null : direccion?.trim(),
        'p_descripcion':
            descripcion?.trim().isEmpty == true ? null : descripcion?.trim(),
        'p_foto_url': fotoUrl?.trim().isEmpty == true ? null : fotoUrl?.trim(),
        'p_instagram':
            instagram?.trim().isEmpty == true ? null : instagram?.trim(),
        'p_whatsapp':
            whatsapp?.trim().isEmpty == true ? null : whatsapp?.trim(),
        'p_web': web?.trim().isEmpty == true ? null : web?.trim(),
        'p_lat': lat,
        'p_lng': lng,
        'p_activo': activo,
      },
    );
  }

  Future<List<Map<String, dynamic>>> listReservas({String? search}) async {
    final res = await _client.rpc(
      'admin_list_reservas',
      params: {'p_search': (search ?? '').trim().isEmpty ? null : search!.trim()},
    );
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<void> cancelarReserva(int reservaId) async {
    await _client.rpc(
      'admin_cancel_reserva',
      params: {'p_reserva_id': reservaId},
    );
  }

  Future<Map<String, dynamic>> getPricingSnapshot() async {
    final res = await _client.rpc('admin_pricing_snapshot');
    return Map<String, dynamic>.from((res as List).first as Map);
  }

  Future<void> updateGlobalCreditValue(int value) async {
    await _client.rpc(
      'admin_update_global_credit_value',
      params: {'p_value': value},
    );
  }

  Future<List<Map<String, dynamic>>> listPricingPlans() async {
    final res = await _client.rpc('admin_list_pricing_plans');
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<List<Map<String, dynamic>>> listPricingPacks() async {
    final res = await _client.rpc('admin_list_pricing_packs');
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<void> upsertPricingPlan({
    int? id,
    required String nombre,
    required int creditos,
    required int precio,
    String? descripcion,
    String? ahorro,
    required bool destacado,
    required bool activo,
    required int orden,
  }) async {
    await _client.rpc(
      'admin_upsert_pricing_plan',
      params: {
        'p_id': id,
        'p_nombre': nombre.trim(),
        'p_creditos': creditos,
        'p_precio': precio,
        'p_descripcion':
            descripcion?.trim().isEmpty == true ? null : descripcion?.trim(),
        'p_ahorro': ahorro?.trim().isEmpty == true ? null : ahorro?.trim(),
        'p_destacado': destacado,
        'p_activo': activo,
        'p_orden': orden,
      },
    );
  }

  Future<void> upsertPricingPack({
    int? id,
    required String nombre,
    required int creditos,
    required int precio,
    String? descripcion,
    required bool popular,
    required bool activo,
    required int orden,
  }) async {
    await _client.rpc(
      'admin_upsert_pricing_pack',
      params: {
        'p_id': id,
        'p_nombre': nombre.trim(),
        'p_creditos': creditos,
        'p_precio': precio,
        'p_descripcion':
            descripcion?.trim().isEmpty == true ? null : descripcion?.trim(),
        'p_popular': popular,
        'p_activo': activo,
        'p_orden': orden,
      },
    );
  }

  Future<List<Map<String, dynamic>>> listAdminActivity() async {
    final res = await _client.rpc('admin_list_activity_logs');
    return List<Map<String, dynamic>>.from(res as List);
  }
}
