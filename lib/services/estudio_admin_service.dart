import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/datos_cobro.dart';

/// Formatea un DateTime a "yyyy-MM-dd HH:mm:ss" sin timezone,
/// consistente con el formato que usa la tabla clases en Supabase.
/// El caller es responsable de pasar un DateTime ya en hora Argentina.
String _toSupaDate(DateTime dt) {
  return '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:00';
}

/// Ventana de generacion de grilla: 9 semanas = 63 dias.
///
/// Se usa tanto desde el boton del panel como desde el cron nocturno
/// (`regenerar-grillas`), que antes generaban 13 y 4 semanas
/// respectivamente — el estudio veia una ventana y el cron mantenia otra.
const int kGrillaSemanas = 9;

class EstudioAdminService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<bool> getTutorialCompletado() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return true;
    try {
      final row = await _client
          .from('usuarios')
          .select('tutorial_completado')
          .eq('id', uid)
          .maybeSingle();
      return (row?['tutorial_completado'] as bool?) ?? false;
    } catch (_) {
      return true; // Si falla, no mostramos el tutorial
    }
  }

  Future<void> marcarTutorialCompletado() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    await _client
        .from('usuarios')
        .update({'tutorial_completado': true})
        .eq('id', uid);
  }

  Future<int?> getCurrentStudioId() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;

    final userRows = await _client
        .from('usuarios')
        .select('estudio_id')
        .eq('id', uid)
        .limit(1);

    if (userRows.isNotEmpty) {
      return (userRows.first['estudio_id'] as num?)?.toInt();
    }
    return null;
  }

  /// Métricas del dashboard del estudio: favoritos + vistas del mes.
  /// Devuelve {favoritos, vistas_mes} (0 si falla o no hay permisos).
  Future<({int favoritos, int vistasMes})> getMetricasEstudio(
      int estudioId) async {
    try {
      final res = await _client.rpc(
        'estudio_metricas',
        params: {'p_estudio_id': estudioId},
      );
      final map = res is Map ? Map<String, dynamic>.from(res) : {};
      return (
        favoritos: (map['favoritos'] as num?)?.toInt() ?? 0,
        vistasMes: (map['vistas_mes'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return (favoritos: 0, vistasMes: 0);
    }
  }

  /// Registra una vista del perfil de un estudio (fire-and-forget).
  Future<void> registrarVistaEstudio(int estudioId) async {
    try {
      await _client.from('estudio_vistas').insert({
        'estudio_id': estudioId,
        'usuario_id': _client.auth.currentUser?.id,
      });
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> getCurrentStudio() async {
    final studioId = await getCurrentStudioId();
    if (studioId == null) return null;

    // Trae tambien los datos de cobro (CBU, comisiones, valor_credito), que
    // viven en estudios_datos_cobro. Se aplanan para que las pantallas del
    // panel sigan leyendo estudio['cbu'] igual que antes. Ver DatosCobro.
    final rows = await _client
        .from('estudios')
        .select(DatosCobro.embedTodo)
        .eq('id', studioId)
        .limit(1);
    if (rows.isNotEmpty) {
      return DatosCobro.aplanar(Map<String, dynamic>.from(rows.first));
    }
    return null;
  }

  /// Lista los estudios que el usuario logueado puede administrar (M:N via
  /// estudio_admins). El campo `is_active` marca cual es el workspace
  /// actualmente seleccionado.
  Future<List<Map<String, dynamic>>> listMyStudios() async {
    try {
      final res = await _client.rpc('list_my_studios');
      final list = List<Map<String, dynamic>>.from(res as List);
      if (list.isNotEmpty) return list;
    } catch (_) {}

    // Fallback: la RPC fallo o devolvio vacio. Hacemos query directa
    // contra estudio_admins (RLS self-read) + join a estudios.
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return const [];
      final ea = await _client
          .from('estudio_admins')
          .select('estudio_id, rol, estudios(id, nombre, foto_url)')
          .eq('usuario_id', uid);
      final userRow = await _client
          .from('usuarios')
          .select('estudio_id')
          .eq('id', uid)
          .maybeSingle();
      final activoId = (userRow?['estudio_id'] as num?)?.toInt();
      return List<Map<String, dynamic>>.from(ea as List).map((row) {
        final est = row['estudios'] as Map?;
        final eId = (est?['id'] as num?)?.toInt() ??
            (row['estudio_id'] as num?)?.toInt();
        return {
          'estudio_id': eId,
          'nombre': est?['nombre'],
          'foto_url': est?['foto_url'],
          'is_active': eId == activoId,
          'rol': row['rol'],
        };
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Cambia el estudio activo (workspace) del usuario logueado. El backend
  /// valida que el usuario sea admin del estudio en cuestion.
  Future<bool> setActiveEstudio(int estudioId) async {
    try {
      final res = await _client.rpc(
        'set_active_estudio',
        params: {'p_estudio_id': estudioId},
      );
      // La RPC devuelve un boolean (true = ok). Compat: si alguna versión vieja
      // devolviera un json {ok:...}, también lo tomamos.
      if (res is bool) return res;
      if (res is Map) return res['ok'] == true;
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Lista los administradores de un estudio. Para uso desde el perfil del
  /// estudio. Reusa `admin_list_studio_accesses` si existe; sino consulta
  /// estudio_admins join usuarios directamente.
  Future<List<Map<String, dynamic>>> listEstudioAdmins(int estudioId) async {
    try {
      final res = await _client.rpc(
        'admin_list_studio_accesses',
        params: {'p_estudio_id': estudioId},
      );
      return List<Map<String, dynamic>>.from(res as List);
    } catch (_) {}
    try {
      final res = await _client
          .from('estudio_admins')
          .select('usuario_id, rol, usuarios(id, nombre, email)')
          .eq('estudio_id', estudioId);
      return List<Map<String, dynamic>>.from(res as List).map((row) {
        final user = row['usuarios'] as Map?;
        return {
          'id': user?['id'] ?? row['usuario_id'],
          'nombre': user?['nombre'],
          'email': user?['email'],
          'rol': row['rol'],
        };
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> removeEstudioAdminAccess({
    required int estudioId,
    required String usuarioId,
  }) async {
    try {
      final res = await _client.rpc(
        'remove_estudio_admin_access',
        params: {
          'p_estudio_id': estudioId,
          'p_usuario_id': usuarioId,
        },
      );
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      return map['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Guarda las dos ventanas de tiempo del estudio (FIX 3). El RPC valida
  /// que el caller administre el estudio y que los valores esten en rango.
  Future<bool> guardarCierresEstudio({
    required int estudioId,
    required int reservaCierreMinutos,
    required int cancelacionCierreMinutos,
  }) async {
    try {
      final res = await _client.rpc(
        'set_estudio_cierres',
        params: {
          'p_estudio_id': estudioId,
          'p_reserva_cierre_minutos': reservaCierreMinutos,
          'p_cancelacion_cierre_minutos': cancelacionCierreMinutos,
        },
      );
      final map =
          res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      return map['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Lista las profes (rol limitado) de un estudio. Solo funciona si el caller
  /// es admin real del estudio (validado en el RPC).
  /// Cuánta gente espera lugar en cada clase futura del estudio, en UNA sola
  /// llamada: `{clase_id: cuántas}`.
  ///
  /// `lista_espera` sólo deja ver la fila propia (policy `waitlist_own`), así
  /// que consultarla desde el panel devuelve 0 filas siempre — tiene que salir
  /// de la RPC. Devuelve conteos, no identidades.
  Future<Map<int, int>> getListaEsperaDelEstudio(int estudioId) async {
    try {
      final rows = await _client.rpc(
        'estudio_lista_espera_conteo',
        params: {'p_estudio_id': estudioId},
      );
      return {
        for (final r in (rows as List))
          ((r as Map)['clase_id'] as num).toInt():
              (r['esperando'] as num).toInt(),
      };
    } catch (e) {
      // Que no se caiga el panel entero por un contador.
      debugPrint('[getListaEsperaDelEstudio] $e');
      return const {};
    }
  }

  Future<List<Map<String, dynamic>>> listProfes(int estudioId) async {
    try {
      final res = await _client.rpc(
        'studio_list_profes',
        params: {'p_estudio_id': estudioId},
      );
      return List<Map<String, dynamic>>.from(res as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Agrega una profe (por email de una cuenta Aura existente) a un estudio.
  /// Devuelve el mapa del RPC: `{ok: bool, error?: String, user_id?: String}`.
  Future<Map<String, dynamic>> addProfe({
    required int estudioId,
    required String email,
  }) async {
    final res = await _client.rpc(
      'studio_add_profe',
      params: {'p_estudio_id': estudioId, 'p_email': email.trim()},
    );
    return res is Map
        ? Map<String, dynamic>.from(res)
        : <String, dynamic>{'ok': false, 'error': 'unknown'};
  }

  Future<List<Map<String, dynamic>>> getClasesDeEstudio({
    DateTime? from,
    DateTime? to,
    int? limit,
  }) async {
    final studioId = await getCurrentStudioId();
    if (studioId == null) return [];

    // OJO: los filtros de postgrest NO mutan el builder, devuelven uno nuevo
    // (`gte()` hace `return copyWithUrl(...)`). Antes esto era
    // `query.gte(...)` sin reasignar, asi que `from`/`to` se descartaban en
    // silencio y la query traia TODAS las clases del estudio ordenadas por
    // fecha asc. Con `limit` eso devolvia las mas VIEJAS: la pantalla de
    // asistencia pedia las de hoy, recibia las de hace dos meses y mostraba
    // "Sin clase activa ahora" con el estudio lleno de clases.
    var query = _client.from('clases').select().eq('estudio_id', studioId);

    if (from != null) {
      query = query.gte('fecha', _toSupaDate(from));
    }
    if (to != null) {
      query = query.lte('fecha', _toSupaDate(to));
    }

    final data = await (limit != null
        ? query.order('fecha', ascending: true).limit(limit)
        : query.order('fecha', ascending: true));
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<List<Map<String, dynamic>>> getReservasDeEstudio({int? limit}) async {
    final clases = await getClasesDeEstudio();
    final classIds = clases
        .map((c) => (c['id'] as num?)?.toInt())
        .whereType<int>()
        .toList();

    if (classIds.isEmpty) return [];

    dynamic query = _client
        .from('reservas')
        .select()
        .inFilter('clase_id', classIds)
        .order('created_at', ascending: false);

    if (limit != null) {
      query = query.limit(limit);
    }

    final data = await query;

    // Adjuntamos el tipo de la clase ('clase' | 'workshop') sin otra query:
    // ya lo tenemos en `clases`. Cobros lo necesita porque los workshops
    // liquidan con `comision_workshop` y no con `comision_aura`.
    final tipoPorClase = <int, String>{};
    for (final c in clases) {
      final id = (c['id'] as num?)?.toInt();
      if (id != null) {
        tipoPorClase[id] = c['tipo']?.toString() ?? 'clase';
      }
    }

    return List<Map<String, dynamic>>.from(data as List).map((r) {
      final claseId = (r['clase_id'] as num?)?.toInt();
      return {
        ...r,
        '_clase_tipo': tipoPorClase[claseId] ?? 'clase',
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getHorariosFijosDeEstudio() async {
    final studioId = await getCurrentStudioId();
    if (studioId == null) return [];

    final data = await _client
        .from('horarios_fijos')
        .select()
        .eq('estudio_id', studioId)
        .order('dia_semana')
        .order('hora_inicio');
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<Map<String, dynamic>> crearHorarioFijo(Map<String, dynamic> payload) async {
    final studioId = await getCurrentStudioId();
    if (studioId == null) {
      throw Exception('No hay estudio asociado.');
    }

    final inserted = await _client
        .from('horarios_fijos')
        .insert({
          ...payload,
          'estudio_id': studioId,
        })
        .select()
        .single();
    await generarProximasSemanasDesdeHorarios();
    return Map<String, dynamic>.from(inserted);
  }

  /// Crea una clase INDIVIDUAL (evento único) en una fecha y hora concretas.
  /// A diferencia de los horarios fijos, NO crea un `horario_fijo` ni dispara
  /// `generarProximasSemanasDesdeHorarios()`: la clase NO se repite jamás.
  /// Aparece en la solapa "Clases cargadas".
  Future<Map<String, dynamic>> crearClaseIndividual({
    required DateTime fechaHora,
    required Map<String, dynamic> payload,
  }) async {
    final studioId = await getCurrentStudioId();
    if (studioId == null) {
      throw Exception('No hay estudio asociado.');
    }

    final lugares = (payload['lugares_total'] as num?)?.toInt() ?? 12;

    // Solo columnas válidas de `clases` (descarta campos de horario_fijo como
    // dia_semana / hora_inicio / activo si vinieran en el payload).
    final insertPayload = <String, dynamic>{
      'estudio_id': studioId,
      'nombre': payload['nombre'],
      'instructor': payload['instructor'],
      'instructor_descripcion': payload['instructor_descripcion'],
      'incluye': payload['incluye'],
      'imagen_url': payload['imagen_url'],
      'galeria_urls': payload['galeria_urls'],
      'fecha': _toSupaDate(fechaHora),
      'duracion_min': (payload['duracion_min'] as num?)?.toInt() ?? 60,
      'lugares_total': lugares,
      'lugares_disponibles': lugares,
      'creditos': (payload['creditos'] as num?)?.toInt() ?? 10,
      // null (no `?? 0`) = "sin override": la clase hereda el default del
      // estudio. Guardar 0 pisaba ese default y rompia la ventana de 12 hs.
      'reserva_cierre_minutos':
          (payload['reserva_cierre_minutos'] as num?)?.toInt(),
      'cancelacion_cierre_minutos':
          (payload['cancelacion_cierre_minutos'] as num?)?.toInt(),
    };
    // Tipo: 'clase' (normal) o 'workshop' (evento). Si es workshop se guardan
    // los organizadores [{nombre, instagram}] y los campos propios del evento
    // (descripción larga y dirección).
    final tipo = payload['tipo']?.toString();
    if (tipo == 'workshop') {
      insertPayload['tipo'] = 'workshop';
      insertPayload['organizadores'] = payload['organizadores'] ?? const [];
      final descripcion = payload['descripcion']?.toString();
      if (descripcion != null && descripcion.trim().isNotEmpty) {
        insertPayload['descripcion'] = descripcion.trim();
      }
      final direccionEvento = payload['direccion']?.toString();
      if (direccionEvento != null && direccionEvento.trim().isNotEmpty) {
        insertPayload['direccion'] = direccionEvento.trim();
      }
    }
    // `categorias` es la fuente de verdad; el escalar `categoria` lo
    // sincroniza el trigger sync_categorias_clase.
    final categorias = payload['categorias'];
    if (categorias is List) {
      insertPayload['categorias'] =
          categorias.map((e) => e.toString()).toList();
    }
    final sala = payload['sala'];
    if (sala != null && sala.toString().trim().isNotEmpty) {
      insertPayload['sala'] = sala;
    }

    final inserted = await _client
        .from('clases')
        .insert(insertPayload)
        .select()
        .single();
    return Map<String, dynamic>.from(inserted);
  }

  /// Crea los horarios fijos de una grilla a partir de la LISTA EXACTA de
  /// horarios por día que el estudio armó en el formulario.
  ///
  /// Antes recibía un rango (Desde / Hasta / duración) y generaba una franja
  /// por cada `duración` minutos. Ese modelo se leía como "horario de apertura"
  /// y produjo grillas de 13 clases por día donde el estudio creía cargar 2
  /// (Tiwar, 25/8). Ahora lo que se ve en pantalla es exactamente lo que se
  /// crea; el rango pasó a ser un atajo del formulario que RELLENA la lista.
  ///
  /// Devuelve la cantidad REAL de filas insertadas (lo que confirma el
  /// servidor), no el largo del lote armado en el cliente.
  Future<int> crearHorariosFijosEnGrilla({
    required Map<int, List<TimeOfDay>> horariosPorDia,
    required int duracionMin,
    required Map<String, dynamic> payloadBase,
  }) async {
    final studioId = await getCurrentStudioId();
    if (studioId == null) {
      throw Exception('No hay estudio asociado.');
    }
    if (duracionMin <= 0) {
      throw Exception('La duración debe ser mayor a 0.');
    }

    final rows = <Map<String, dynamic>>[];
    final dias = horariosPorDia.keys.where((d) => d >= 1 && d <= 7).toList()
      ..sort();
    for (final dia in dias) {
      // Dedup por minuto del día y orden cronológico: dos chips iguales no
      // pueden convertirse en dos filas (el guard de la base lo rechazaría
      // entero y el estudio no entendería por qué).
      final minutos = <int>{};
      for (final t in horariosPorDia[dia] ?? const <TimeOfDay>[]) {
        minutos.add(t.hour * 60 + t.minute);
      }
      for (final m in minutos.toList()..sort()) {
        final hh = (m ~/ 60).toString().padLeft(2, '0');
        final mm = (m % 60).toString().padLeft(2, '0');
        rows.add({
          ...payloadBase,
          'estudio_id': studioId,
          'dia_semana': dia,
          'hora_inicio': '$hh:$mm',
          'duracion_min': duracionMin,
        });
      }
    }

    if (rows.isEmpty) {
      throw Exception('Agregá al menos un horario.');
    }

    final inserted =
        await _client.from('horarios_fijos').insert(rows).select('id');
    await generarProximasSemanasDesdeHorarios();
    return (inserted as List).length;
  }

  Future<void> eliminarHorarioFijo(int id) async {
    await _client.from('horarios_fijos').delete().eq('id', id);
  }

  /// Elimina UNA clase de la tabla `clases`. No toca reservas — eso es
  /// responsabilidad del caller (usar
  /// `ReservasService.cancelarClaseConDevolucion` primero para devolver
  /// los creditos a los alumnos).
  /// Quita la marca `cancelada` de una clase (la vuelve reservable). Solo el
  /// admin del estudio pasa la RLS de UPDATE sobre `clases`.
  Future<void> reactivarClase(int id) async {
    await _client.from('clases').update({'cancelada': false}).eq('id', id);
  }

  Future<void> eliminarClaseRow(int id) async {
    await _client.from('clases').delete().eq('id', id);
  }

  /// Lista las clases futuras (fecha >= hoy AR) generadas a partir de un
  /// horario fijo. Usado por "Eliminar toda la grilla" para iterar y
  /// devolver creditos a cada clase antes de eliminarla.
  Future<List<Map<String, dynamic>>> listarClasesFuturasDeHorario(
    int horarioFijoId,
  ) async {
    final nowAr = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    final hoyAr = DateTime(nowAr.year, nowAr.month, nowAr.day);
    final data = await _client
        .from('clases')
        .select('id, nombre, fecha')
        .eq('horario_fijo_id', horarioFijoId)
        .gte('fecha', _toSupaDate(hoyAr));
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<void> editarClase(int id, Map<String, dynamic> payload) async {
    // Detectar si el update aumenta lugares_disponibles para auto-promover
    // de lista de espera. Comparamos el valor previo vs el del payload.
    int? lugaresPrevios;
    if (payload.containsKey('lugares_disponibles')) {
      try {
        final previa = await _client
            .from('clases')
            .select('lugares_disponibles')
            .eq('id', id)
            .maybeSingle();
        lugaresPrevios =
            (previa?['lugares_disponibles'] as num?)?.toInt();
      } catch (_) {}
    }

    await _client.from('clases').update(payload).eq('id', id);

    if (lugaresPrevios != null && payload['lugares_disponibles'] != null) {
      final lugaresNuevos =
          (payload['lugares_disponibles'] as num?)?.toInt() ?? lugaresPrevios;
      final delta = lugaresNuevos - lugaresPrevios;
      if (delta > 0) {
        // Promover hasta `delta` entries de lista_espera. Fire-and-forget:
        // un error aca no debe romper el editarClase. El RPC tambien
        // decrementa lugares_disponibles internamente por cada promocion.
        try {
          await _client.rpc('cleanup_pre_reservas_expiradas',
              params: {'p_clase_id': id});
          final res =
              await _client.rpc('waitlist_promote_next', params: {
            'p_clase_id': id,
            'p_count': delta,
          });
          // Insertar notificacion in-app (campanita) por cada promovido.
          // La notif "push" local la dispara el dispositivo del alumno
          // cuando entra a la app y detecta su pre_confirmada (vease
          // DetalleClaseScreen + MisReservas).
          // La campanita de "se abrieron lugares" la crea la base dentro de
          // `_waitlist_promote_interno` desde el 22/8. Acá había un insert a
          // `notificaciones_usuario` que RLS rechazaba SIEMPRE (la tabla no
          // tiene policy de INSERT: sólo SELECT y UPDATE de lo propio) y el
          // `catch (_) {}` se lo tragaba. Si RLS lo dejara pasar, duplicaría
          // el aviso. Se borró: no hay que reemplazarlo por nada.
        } catch (_) {}
      }
    }
  }

  /// Cancela todas las reservas activas de la clase y luego la elimina.
  Future<void> cancelarClase(int id) async {
    await _client
        .from('reservas')
        .update({'estado': 'cancelada'})
        .eq('clase_id', id)
        .neq('estado', 'cancelada');
    await _client.from('clases').delete().eq('id', id);
  }

  /// Columnas que existen de verdad en `horarios_fijos`.
  ///
  /// El formulario de la grilla arma un payload compartido entre "clase
  /// individual" (va a `clases`) y "horario fijo" (va acá), y `clases` tiene
  /// columnas que `horarios_fijos` no: `tipo`, `organizadores`, `descripcion`
  /// y `direccion`. Mandarlas hacía que PostgREST rechazara el PATCH entero
  /// con `PGRST204 Could not find the 'tipo' column`, asi que editar un
  /// horario fijo no guardaba NADA (ningun campo, no solo el cierre).
  static const _columnasHorarioFijo = <String>{
    'nombre',
    'instructor',
    'instructor_descripcion',
    'incluye',
    'sala',
    'dia_semana',
    'hora_inicio',
    'duracion_min',
    'lugares_total',
    'creditos',
    'imagen_url',
    'imagen_ajuste',
    'galeria_urls',
    'categoria',
    'categorias',
    'reserva_cierre_minutos',
    'cancelacion_cierre_minutos',
    'activo',
  };

  Future<Map<String, dynamic>> actualizarHorarioFijo(
    int id,
    Map<String, dynamic> payload,
  ) async {
    // Filtramos acá y no en la pantalla para cubrir cualquier caller, y para
    // que agregar un campo nuevo al diálogo no vuelva a romper el guardado.
    final limpio = <String, dynamic>{
      for (final e in payload.entries)
        if (_columnasHorarioFijo.contains(e.key)) e.key: e.value,
    };

    final updated = await _client
        .from('horarios_fijos')
        .update(limpio)
        .eq('id', id)
        .select()
        .single();
    await _propagarHorarioFijoAClasesFuturas(
      id,
      Map<String, dynamic>.from(updated),
    );
    await generarProximasSemanasDesdeHorarios();
    return Map<String, dynamic>.from(updated);
  }

  Future<void> _propagarHorarioFijoAClasesFuturas(
    int horarioFijoId,
    Map<String, dynamic> horario,
  ) async {
    final nowAr = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    final hoyAr = DateTime(nowAr.year, nowAr.month, nowAr.day);

    final lugaresTotal = (horario['lugares_total'] as num?)?.toInt() ?? 12;
    final payload = <String, dynamic>{
      'nombre': horario['nombre'],
      'instructor': horario['instructor'],
      'instructor_descripcion': horario['instructor_descripcion'],
      'incluye': horario['incluye'],
      'imagen_url': horario['imagen_url'],
      'imagen_ajuste': horario['imagen_ajuste'],
      'galeria_urls': horario['galeria_urls'],
      'duracion_min': (horario['duracion_min'] as num?)?.toInt() ?? 60,
      'lugares_total': lugaresTotal,
      // Si el horario fijo paso a 0 cupos, sincronizamos lugares_disponibles
      // tambien a 0 en las clases futuras. Sin esto quedaban total=0 pero
      // disp con el valor viejo (ej 12) -> el guard de Dart tiraba "Esta
      // clase no acepta reservas en este momento" porque comparaba total<=0,
      // y para el user era un error generico.
      if (lugaresTotal == 0) 'lugares_disponibles': 0,
      'creditos': (horario['creditos'] as num?)?.toInt() ?? 10,
      // null = hereda del estudio. Ver comentario en crearClaseIndividual.
      'reserva_cierre_minutos':
          (horario['reserva_cierre_minutos'] as num?)?.toInt(),
      'cancelacion_cierre_minutos':
          (horario['cancelacion_cierre_minutos'] as num?)?.toInt(),
      'categorias': horario['categorias'] ?? const <String>[],
      'sala': horario['sala'],
    };

    try {
      await _client
          .from('clases')
          .update(payload)
          .eq('horario_fijo_id', horarioFijoId)
          .gte('fecha', _toSupaDate(hoyAr));
    } on PostgrestException catch (e) {
      if (!e.message.toLowerCase().contains('horario_fijo_id')) rethrow;
    }
  }

  Future<Map<String, int>> generarProximasSemanasDesdeHorarios({int weeks = kGrillaSemanas}) async {
    // Path rapido: si existe la RPC server-side (supabase/GENERAR_CLASES_DESDE_SQL.sql),
    // delega todo el loop a la base. Es ~10x mas rapido y no depende de
    // que el cliente pase RLS de INSERT/UPDATE/SELECT por cada semana.
    try {
      final studioId = await getCurrentStudioId();
      if (studioId == null) {
        throw Exception('No hay estudio asociado.');
      }
      final res = await _client.rpc(
        'generar_clases_estudio',
        params: {'p_estudio_id': studioId, 'p_weeks': weeks},
      );
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      return {
        'creadas': (map['creadas'] as num?)?.toInt() ?? 0,
        'omitidas': (map['omitidas'] as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      // Fallback al loop cliente (compatibilidad con DBs que todavia no
      // tienen la RPC generar_clases_estudio).
    }

    final today = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    final currentWeekStart = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: today.weekday - 1));

    var creadas = 0;
    var omitidas = 0;
    for (var i = 0; i < weeks; i++) {
      final result = await generarClasesDesdeHorarios(
        weekStart: currentWeekStart.add(Duration(days: 7 * i)),
      );
      creadas += result['creadas'] ?? 0;
      omitidas += result['omitidas'] ?? 0;
    }
    return {'creadas': creadas, 'omitidas': omitidas};
  }

  Future<Map<String, int>> generarClasesDesdeHorarios({
    required DateTime weekStart,
  }) async {
    final studioId = await getCurrentStudioId();
    if (studioId == null) {
      throw Exception('No hay estudio asociado.');
    }

    final horarios = await getHorariosFijosDeEstudio();
    if (horarios.isEmpty) {
      return {'creadas': 0, 'omitidas': 0};
    }

    var creadas = 0;
    var omitidas = 0;

    for (final horario in horarios) {
      if (horario['activo'] == false) {
        omitidas++;
        continue;
      }

      final horarioId = (horario['id'] as num?)?.toInt();
      if (horarioId == null) {
        omitidas++;
        continue;
      }

      final diaSemana = (horario['dia_semana'] as num?)?.toInt();
      if (diaSemana == null || diaSemana < 1 || diaSemana > 7) {
        omitidas++;
        continue;
      }

      final horaInicio = horario['hora_inicio']?.toString() ?? '08:00';
      final partesHora = horaInicio.split(':');
      final hora = int.tryParse(partesHora.first) ?? 8;
      final minuto = int.tryParse(partesHora.length > 1 ? partesHora[1] : '0') ?? 0;
      final fechaClase = DateTime(
        weekStart.year,
        weekStart.month,
        weekStart.day,
      ).add(Duration(days: diaSemana - 1, hours: hora, minutes: minuto));

      final nombre = horario['nombre']?.toString().trim();
      if (nombre == null || nombre.isEmpty) {
        omitidas++;
        continue;
      }

      // Buscar con rango ±1h para tolerar diferencias de timezone/formato
      final fechaInicio = _toSupaDate(fechaClase.subtract(const Duration(hours: 1)));
      final fechaFin    = _toSupaDate(fechaClase.add(const Duration(hours: 1)));
      Map<String, dynamic>? existente;
      try {
        final byHorario = await _client
            .from('clases')
            .select('id')
            .eq('estudio_id', studioId)
            .eq('horario_fijo_id', horarioId)
            .gte('fecha', fechaInicio)
            .lte('fecha', fechaFin)
            .maybeSingle();
        if (byHorario != null) {
          existente = Map<String, dynamic>.from(byHorario);
        }
      } on PostgrestException {
        // Compatibilidad temporal para bases que todavia no tienen horario_fijo_id.
      }

      existente ??= await _client
          .from('clases')
          .select('id')
          .eq('estudio_id', studioId)
          .eq('nombre', nombre)
          .gte('fecha', fechaInicio)
          .lte('fecha', fechaFin)
          .maybeSingle();

      final lugares = (horario['lugares_total'] as num?)?.toInt() ?? 12;
      final duracion = (horario['duracion_min'] as num?)?.toInt() ?? 60;
      final creditos = (horario['creditos'] as num?)?.toInt() ?? 10;
      // null = hereda el default del estudio (no `?? 0`, que lo pisaria).
      final reservaCierreMinutos =
          (horario['reserva_cierre_minutos'] as num?)?.toInt();
      final cancelacionCierreMinutos =
          (horario['cancelacion_cierre_minutos'] as num?)?.toInt();
      final categorias = (horario['categorias'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];

      final fechaStr = _toSupaDate(fechaClase);

      // Payload completo para INSERT (nueva clase desde cero).
      final insertPayload = <String, dynamic>{
        'estudio_id': studioId,
        'horario_fijo_id': horarioId,
        'nombre': nombre,
        'instructor': horario['instructor'],
        'instructor_descripcion': horario['instructor_descripcion'],
        'incluye': horario['incluye'],
        'imagen_url': horario['imagen_url'],
        'imagen_ajuste': horario['imagen_ajuste'],
        'galeria_urls': horario['galeria_urls'],
        'fecha': fechaStr,
        'duracion_min': duracion,
        'lugares_total': lugares,
        'lugares_disponibles': lugares,  // al crear, siempre igual a total
        'creditos': creditos,
        'reserva_cierre_minutos': reservaCierreMinutos,
        'cancelacion_cierre_minutos': cancelacionCierreMinutos,
        'categorias': categorias,
      };
      final sala = horario['sala'];
      if (sala != null && sala.toString().trim().isNotEmpty) {
        insertPayload['sala'] = sala;
      }

      // Payload para UPDATE: NO toca lugares_disponibles ni creditos para no
      // pisarlos si el admin los editó manualmente en esa clase puntual.
      final updatePayload = <String, dynamic>{
        'estudio_id': studioId,
        'horario_fijo_id': horarioId,
        'nombre': nombre,
        'instructor': horario['instructor'],
        'instructor_descripcion': horario['instructor_descripcion'],
        'incluye': horario['incluye'],
        'imagen_url': horario['imagen_url'],
        'imagen_ajuste': horario['imagen_ajuste'],
        'galeria_urls': horario['galeria_urls'],
        'duracion_min': duracion,
        'lugares_total': lugares,
        'reserva_cierre_minutos': reservaCierreMinutos,
        'cancelacion_cierre_minutos': cancelacionCierreMinutos,
        'categorias': categorias,
        if (sala != null && sala.toString().trim().isNotEmpty) 'sala': sala,
      };

      if (existente != null) {
        try {
          await _client
              .from('clases')
              .update(updatePayload)
              .eq('id', (existente['id'] as num).toInt());
        } on PostgrestException catch (e) {
          if (!e.message.toLowerCase().contains('horario_fijo_id')) rethrow;
          final fallback = Map<String, dynamic>.from(updatePayload)
            ..remove('horario_fijo_id');
          await _client
              .from('clases')
              .update(fallback)
              .eq('id', (existente['id'] as num).toInt());
        }
      } else {
        try {
          await _client.from('clases').insert(insertPayload);
        } on PostgrestException catch (e) {
          if (e.message.toLowerCase().contains('horario_fijo_id')) {
            final fallback = Map<String, dynamic>.from(insertPayload)
              ..remove('horario_fijo_id');
            await _client.from('clases').insert(fallback);
            creadas++;
            continue;
          }
          // Duplicate key: la fila ya existe con fecha ligeramente distinta
          if (e.code == '23505') {
            omitidas++;
            continue;
          }
          rethrow;
        }
      }

      creadas++;
    }

    return {'creadas': creadas, 'omitidas': omitidas};
  }
}
