import 'package:flutter/foundation.dart';
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

  /// Backoffice: elimina un usuario completo invocando la Edge Function
  /// delete-account con target_user_id. El caller tiene que estar en la
  /// tabla admin_users (la edge function lo verifica). Cancela reservas
  /// futuras, devuelve creditos a los alumnos afectados y borra el row
  /// de public.usuarios + auth.users.
  Future<void> eliminarUsuario(String userId) async {
    final session = _client.auth.currentSession;
    final token = session?.accessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Sesión expirada.');
    }
    final res = await _client.functions.invoke(
      'delete-account',
      headers: {'x-aura-auth': token},
      body: {'target_user_id': userId},
    );
    if (res.status != 200) {
      final data = res.data;
      String? msg;
      if (data is Map) msg = data['error']?.toString();
      throw Exception(msg ?? 'No se pudo eliminar el usuario');
    }
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
    // Usa la RPC studio_promote_user_to_admin (multi-estudio: acumula en
    // estudio_admins en vez de pisar usuarios.estudio_id). Si la RPC no
    // existe en esta DB, intenta admin_link_estudio_access como fallback.
    try {
      final res = await _client.rpc(
        'studio_promote_user_to_admin',
        params: {
          'p_estudio_id': estudioId,
          'p_email': email.trim(),
        },
      );
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (map['ok'] == true) return;
      switch (map['error']?.toString()) {
        case 'user_not_found':
          throw Exception(
            'No existe una cuenta Aura con ese email. Revisá mayúsculas o pedile que se registre primero.',
          );
        case 'forbidden':
          throw Exception(
            'No tenés permisos para agregar admins a este estudio.',
          );
        case 'email_required':
          throw Exception('Ingresá un email válido.');
        default:
          throw Exception('No se pudo agregar el acceso.');
      }
    } on Exception {
      rethrow;
    } catch (_) {}

    // Fallback legacy
    await _client.rpc(
      'admin_link_estudio_access',
      params: {
        'p_estudio_id': estudioId,
        'p_email': email.trim(),
      },
    );
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

  /// Lista TODOS los miembros de un estudio (admins y profes) con su `rol`.
  /// Usa la RPC `admin_list_studio_members` (superadmin o admin del estudio).
  /// Si esa RPC todavía no está deployada (falta correr
  /// BACKOFFICE_GESTION_ACCESOS.sql), cae a `admin_list_studio_accesses`
  /// (sin distinción de rol) para no romper el panel.
  Future<List<Map<String, dynamic>>> listEstudioMembers({
    required int estudioId,
  }) async {
    try {
      final res = await _client.rpc(
        'admin_list_studio_members',
        params: {'p_estudio_id': estudioId},
      );
      return List<Map<String, dynamic>>.from(res as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    } on PostgrestException catch (e) {
      debugPrint(
        '[accesos] admin_list_studio_members falló '
        '(code=${e.code}, message=${e.message}, details=${e.details}). '
        'Fallback a admin_list_studio_accesses. '
        'Corré supabase/BACKOFFICE_GESTION_ACCESOS.sql para el panel completo.',
      );
      final res = await _client.rpc(
        'admin_list_studio_accesses',
        params: {'p_estudio_id': estudioId},
      );
      return List<Map<String, dynamic>>.from(res as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    }
  }

  /// Agrega una profe (rol 'profe') por email. Superadmin-aware.
  /// Lanza Exception con mensaje legible si el RPC devuelve error.
  Future<void> addEstudioProfe({
    required int estudioId,
    required String email,
  }) async {
    final res = await _client.rpc(
      'admin_add_studio_profe',
      params: {'p_estudio_id': estudioId, 'p_email': email.trim()},
    );
    final map =
        res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    if (map['ok'] == true) return;
    switch (map['error']?.toString()) {
      case 'user_not_found':
        throw Exception(
          'No existe una cuenta Aura con ese email. Pedile que se registre primero.',
        );
      case 'forbidden':
        throw Exception('No tenés permisos para agregar profes a este estudio.');
      case 'email_required':
        throw Exception('Ingresá un email válido.');
      default:
        throw Exception('No se pudo agregar la profe.');
    }
  }

  /// Cambia el rol de un miembro existente entre 'admin_estudio' y 'profe'.
  Future<void> setEstudioAccessRol({
    required int estudioId,
    required String userId,
    required String rol,
  }) async {
    final res = await _client.rpc(
      'admin_set_studio_access_rol',
      params: {
        'p_estudio_id': estudioId,
        'p_usuario_id': userId,
        'p_rol': rol,
      },
    );
    final map =
        res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    if (map['ok'] == true) return;
    switch (map['error']?.toString()) {
      case 'forbidden':
        throw Exception('No tenés permisos para editar accesos de este estudio.');
      case 'not_member':
        throw Exception('Esta persona ya no es miembro del estudio.');
      case 'invalid_rol':
        throw Exception('Rol inválido.');
      default:
        throw Exception('No se pudo cambiar el rol.');
    }
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

  /// Catálogo completo, con estado y uso. Solo para el backoffice.
  /// Devuelve `{nombre, activa, en_uso}` por categoría.
  Future<List<Map<String, dynamic>>> listStudyCategoriesDetalle() async {
    final res = await _client.rpc('admin_list_studio_categories');
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Solo los nombres. `soloActivas` es el default porque los selectores
  /// (estudio y backoffice) no deben ofrecer categorías dadas de baja.
  /// Estado del flag de créditos de bienvenida: {activa, monto}.
  Future<Map<String, dynamic>> getBienvenidaConfig() async {
    final activa = await getConfigGlobal('bienvenida_activa');
    final monto = await getConfigGlobal('bienvenida_monto');
    return {
      'activa': (activa ?? 'false').trim().toLowerCase() == 'true',
      'monto': int.tryParse((monto ?? '10').trim()) ?? 10,
    };
  }

  /// Enciende la bienvenida y acredita a todos los ya registrados.
  /// Devuelve cuántas se otorgaron.
  Future<int> encenderBienvenida({int? monto}) async {
    final res = await _client.rpc(
      'admin_encender_bienvenida',
      params: {'p_monto': monto},
    );
    final map = res is Map ? Map<String, dynamic>.from(res) : {};
    return (map['otorgadas'] as num?)?.toInt() ?? 0;
  }

  Future<void> apagarBienvenida() async {
    await _client.rpc('admin_apagar_bienvenida');
  }

  Future<List<String>> listStudyCategories({bool soloActivas = true}) async {
    final res = await _client.rpc('admin_list_studio_categories');
    return (res as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((e) => !soloActivas || e['activa'] != false)
        .map((e) => e['nombre']?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
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
        'p_actual': oldName.trim(),
        'p_nuevo': newName.trim(),
      },
    );
  }

  /// Dar de baja en vez de borrar: la saca de los selectores pero no toca
  /// las clases que ya la tienen asignada.
  Future<void> toggleStudyCategory(String nombre, bool activa) async {
    await _client.rpc(
      'admin_toggle_studio_category',
      params: {'p_nombre': nombre.trim(), 'p_activa': activa},
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
    required List<String> categorias,
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
    int? comision,
    int? comisionWorkshop,
    String? cbu,
    String? fechaInicioCobro,
    String? tipoPrecio,
    int? creditosMin,
    int? creditosMax,
  }) async {
    await _client.rpc(
      'admin_upsert_estudio',
      params: {
        'p_estudio_id': estudioId,
        'p_nombre': nombre.trim(),
        'p_categorias': categorias
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .toList(),
        // `p_categoria` sigue yendo (la primera) porque la columna escalar se
        // mantiene sincronizada para las vistas y queries legacy.
        'p_categoria': categorias.isEmpty ? '' : categorias.first.trim(),
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
        'p_comision': comision,
        'p_comision_workshop': comisionWorkshop,
        'p_cbu': cbu?.trim().isEmpty == true ? null : cbu?.trim(),
        'p_fecha_inicio_cobro': fechaInicioCobro,
        'p_tipo_precio': tipoPrecio,
        'p_creditos_min': creditosMin,
        'p_creditos_max': creditosMax,
      },
    );
  }

  /// Cuenta las clases futuras (no workshops) de un estudio.
  Future<int> contarClasesFuturas(int estudioId) async {
    final res = await _client.rpc(
      'admin_contar_clases_futuras',
      params: {'p_estudio_id': estudioId},
    );
    return (res as num?)?.toInt() ?? 0;
  }

  /// Actualiza los créditos de las clases futuras (no workshops) del estudio
  /// y sincroniza sus horarios fijos. Devuelve cuántas clases se actualizaron.
  /// Recalcula los créditos de las clases del estudio según su config actual
  /// (modo fijo o rango con grilla pico/valle). No recibe un precio: lo deriva
  /// la base con `calcular_precio_clase`, así que sirve para los dos modos.
  ///
  /// [incluirPasadas] reescribe también las clases que ya pasaron. No afecta
  /// la plata: liquidaciones y consumo salen de `reservas.creditos_usados`.
  Future<int> recalcularPreciosEstudio({
    required int estudioId,
    bool incluirPasadas = true,
  }) async {
    final res = await _client.rpc(
      'admin_recalcular_precios_estudio',
      params: {
        'p_estudio_id': estudioId,
        'p_incluir_pasadas': incluirPasadas,
      },
    );
    return (res as num?)?.toInt() ?? 0;
  }

  /// Elimina un estudio de forma permanente junto con todo lo asociado
  /// (clases y sus reservas, liquidaciones, reseñas, etc.). El RPC verifica
  /// que el caller sea admin.
  Future<void> eliminarEstudio(int estudioId) async {
    await _client.rpc(
      'admin_delete_estudio',
      params: {'p_estudio_id': estudioId},
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

  Future<Map<String, dynamic>> enviarAvisoCobro() async {
    final result = await _client.functions.invoke('aviso-cobro-manana');
    if (result.status != 200) {
      final msg = (result.data as Map?)?['error']?.toString() ?? 'Error al enviar avisos';
      throw Exception(msg);
    }
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> enviarReporteMensual() async {
    final result = await _client.functions.invoke('reporte-mensual-estudios');
    if (result.status != 200) {
      final msg = (result.data as Map?)?['error']?.toString() ?? 'Error al enviar reportes';
      throw Exception(msg);
    }
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Crea un estudio nuevo + cuenta de auth con email pre-verificado +
  /// fila en `usuarios` con rol 'estudio'. Solo para admins (la Edge Function
  /// chequea el rol del caller).
  /// Devuelve `{user_id, estudio_id, email, password}`.
  Future<Map<String, dynamic>> crearEstudioConCuenta({
    required String estudioNombre,
    required String email,
    required String password,
    List<String> categorias = const [],
    String? direccion,
    String? barrio,
  }) async {
    final jwt = _client.auth.currentSession?.accessToken ?? '';
    if (jwt.isEmpty) {
      throw Exception('Sin sesión activa.');
    }
    final result = await _client.functions.invoke(
      'admin-crear-estudio',
      headers: {'x-aura-auth': jwt},
      body: {
        'estudio_nombre': estudioNombre,
        'email': email,
        'password': password,
        if (categorias.isNotEmpty) 'categorias': categorias,
        if (direccion != null && direccion.isNotEmpty) 'direccion': direccion,
        if (barrio != null && barrio.isNotEmpty) 'barrio': barrio,
      },
    );
    if (result.status != 200) {
      final msg = (result.data as Map?)?['error']?.toString() ??
          'Error creando el estudio.';
      throw Exception(msg);
    }
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<String?> getConfigGlobal(String clave) async {
    try {
      final res = await _client
          .from('configuracion_global')
          .select('valor')
          .eq('clave', clave)
          .maybeSingle();
      return res?['valor']?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> setConfigGlobal(String clave, String valor) async {
    await _client.from('configuracion_global').upsert(
      {'clave': clave, 'valor': valor, 'updated_at': DateTime.now().toIso8601String()},
      onConflict: 'clave',
    );
  }

  /// Lee `valor_credito_ars` de `configuracion_global`.
  Future<int> getValorCreditoArs() async {
    final raw = await getConfigGlobal('valor_credito_ars');
    return int.tryParse((raw ?? '').trim()) ?? 1000;
  }

  /// Cambia el valor del credito y recalcula los precios de los 4 packs base.
  /// Llama al RPC `admin_set_valor_credito_ars` que tambien actualiza
  /// `pricing_credit_packs.precio` y `estudios.valor_credito` (compat).
  Future<void> setValorCreditoArs(int value) async {
    await _client.rpc(
      'admin_set_valor_credito_ars',
      params: {'p_value': value},
    );
  }

  // ── Empresas (usuarios corporativos) ──────────────────────────────────────

  /// Lista las empresas con nº de empleados registrados y créditos usados
  /// este mes. Requiere superadmin (la RPC valida is_admin()).
  Future<List<Map<String, dynamic>>> listEmpresas() async {
    final res = await _client.rpc('admin_list_empresas');
    return List<Map<String, dynamic>>.from(res as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  /// Crea o edita una empresa. Devuelve el id.
  Future<int> upsertEmpresa({
    int? empresaId,
    required String nombre,
    required String dominioMail,
    required int creditosPorEmpleado,
    required bool activa,
  }) async {
    final res = await _client.rpc(
      'admin_upsert_empresa',
      params: {
        'p_id': empresaId,
        'p_nombre': nombre.trim(),
        'p_dominio_mail': dominioMail.trim(),
        'p_creditos_por_empleado': creditosPorEmpleado,
        'p_activa': activa,
      },
    );
    return (res as num).toInt();
  }

  /// Activa o desactiva una empresa.
  Future<void> setEmpresaActiva({
    required int empresaId,
    required bool activa,
  }) async {
    await _client.rpc(
      'admin_set_empresa_activa',
      params: {'p_id': empresaId, 'p_activa': activa},
    );
  }

  /// Empleados registrados de una empresa: saldo y créditos usados este mes.
  Future<List<Map<String, dynamic>>> listEmpresaEmpleados(int empresaId) async {
    final res = await _client.rpc(
      'admin_list_empresa_empleados',
      params: {'p_empresa_id': empresaId},
    );
    return List<Map<String, dynamic>>.from(res as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}
