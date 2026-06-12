import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_constants.dart';
import '../models/reserva.dart';
import 'aura_gestion_service.dart';
import 'notificaciones_estudio_service.dart';
import 'notificaciones_service.dart';
import 'usuarios_service.dart';

class ReservasService {
  final _supabase = Supabase.instance.client;
  final _usuariosService = UsuariosService();
  final _gestionService = AuraGestionService();

  Future<List<Map<String, dynamic>>> getReservasUsuario([String? userId]) async {
    final effectiveUserId = userId ?? _supabase.auth.currentUser?.id ?? '';
    if (effectiveUserId.isEmpty) return [];

    final reservas = await _supabase
        .from(AppConstants.tableReservas)
        .select()
        .eq('usuario_id', effectiveUserId)
        .neq('estado', 'cancelada')
        .neq('estado', 'completada')
        .neq('estado', 'cancelada_por_estudio')
        .order('created_at', ascending: false);

    final joined = await _joinClasesEstudios(reservas as List);

    // BUG 17 (re-fix de BUG 13): filtrar reservas con fecha pasada que el cron de
    // "completar" todavía no marcó. Antes usábamos comparación de strings, frágil
    // con formatos mixtos (naive vs tz-aware). Ahora parseamos a DateTime y
    // comparamos como instantes absolutos en hora Argentina (UTC-3 fijo).
    const argOffset = Duration(hours: -3);
    final nowArgentina = DateTime.now().toUtc().add(argOffset);
    return joined.where((r) {
      final fechaStr = (r['clases'] as Map?)?['fecha']?.toString() ?? '';
      if (fechaStr.isEmpty) return false;
      final parsed = DateTime.tryParse(fechaStr);
      if (parsed == null) return false;
      // Si el string traía TZ (ej. "2026-04-30T19:00:00+00:00") parsed.isUtc=true.
      // En ese caso lo convertimos a Argentina. Si era naive lo asumimos
      // ya en hora Argentina (cómo lo escribe _toSupaDate del clases_service).
      final fechaArgentina =
          parsed.isUtc ? parsed.add(argOffset) : parsed;
      return !fechaArgentina.isBefore(nowArgentina);
    }).toList();
  }

  /// Paginated fetch of past reservations (cancelled or completed).
  Future<List<Map<String, dynamic>>> getHistorialReservas(
    String userId, {
    int limit = 20,
    int offset = 0,
  }) async {
    if (userId.isEmpty) return [];

    final reservas = await _supabase
        .from(AppConstants.tableReservas)
        .select()
        .eq('usuario_id', userId)
        .or('estado.eq.cancelada,estado.eq.completada,estado.eq.cancelada_por_estudio')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return _joinClasesEstudios(reservas as List);
  }

  /// Batch-joins classes and studios to a list of reservations.
  /// Replaces the old serial N+1 loop.
  Future<List<Map<String, dynamic>>> _joinClasesEstudios(List rows) async {
    if (rows.isEmpty) return [];

    final claseIds = rows
        .map((r) => (r['clase_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .toList();

    if (claseIds.isEmpty) return List<Map<String, dynamic>>.from(rows);

    final clasesRows = await _supabase
        .from(AppConstants.tableClases)
        .select()
        .inFilter('id', claseIds);

    final estudioIds = (clasesRows as List)
        .map((c) => (c['estudio_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .toList();

    final Map<int, Map<String, dynamic>> estudiosMap = {};
    if (estudioIds.isNotEmpty) {
      final estudiosRows = await _supabase
          .from(AppConstants.tableEstudios)
          .select()
          .inFilter('id', estudioIds);
      for (final e in (estudiosRows as List)) {
        final id = (e['id'] as num?)?.toInt();
        if (id != null) estudiosMap[id] = Map<String, dynamic>.from(e);
      }
    }

    final clasesMap = <int, Map<String, dynamic>>{};
    for (final c in clasesRows) {
      final id = (c['id'] as num?)?.toInt();
      if (id != null) {
        final estudioId = (c['estudio_id'] as num?)?.toInt();
        clasesMap[id] = {
          ...Map<String, dynamic>.from(c),
          'estudios': estudioId != null ? estudiosMap[estudioId] : null,
        };
      }
    }

    return rows.map<Map<String, dynamic>>((r) {
      final claseId = (r['clase_id'] as num?)?.toInt();
      final clase = claseId != null ? clasesMap[claseId] : null;
      return {...Map<String, dynamic>.from(r), if (clase != null) 'clases': clase};
    }).toList();
  }

  Future<Reserva?> crearReserva({
    required String userId,
    required int claseId,
    required int creditosUsados,
  }) async {
    final clase = await _supabase
        .from(AppConstants.tableClases)
        .select('fecha, reserva_cierre_minutos, lugares_total, lugares_disponibles')
        .eq('id', claseId)
        .maybeSingle();

    if (clase == null) {
      throw Exception('No encontramos la clase.');
    }

    final fechaClase = DateTime.tryParse(clase['fecha']?.toString() ?? '');
    final cierreMinutos =
        (clase['reserva_cierre_minutos'] as num?)?.toInt() ?? 0;
    if (fechaClase != null && reservaCerrada(fechaClase, cierreMinutos)) {
      throw Exception(_mensajeCierreReserva(cierreMinutos));
    }

    // 0 cupos = clase visible pero no reservable (configurado a proposito
    // por el estudio). Cortamos antes de tocar creditos para no cobrar
    // sin entregar lugar.
    final total = (clase['lugares_total'] as num?)?.toInt() ?? 0;
    final disponibles =
        (clase['lugares_disponibles'] as num?)?.toInt() ?? total;
    if (total <= 0 || disponibles <= 0) {
      throw Exception('Esta clase no acepta reservas en este momento.');
    }

    // Verificar si es alumno directo en un estudio modo gestión → reserva gratis
    final userEmail =
        _supabase.auth.currentUser?.email ?? '';
    final esGratuita = userEmail.isNotEmpty
        ? await _gestionService.reservaEsGratuita(
            claseId: claseId,
            userEmail: userEmail,
          )
        : false;

    final creditosReales = esGratuita ? 0 : creditosUsados;

    if (!esGratuita) {
      final consumidos =
          await _usuariosService.descontarCreditos(userId, creditosReales);
      if (!consumidos) {
        throw Exception(
            'No tenés créditos disponibles para reservar esta clase.');
      }
    }

    final codigoQr = _generarCodigoQr(userId, claseId);

    try {
      // Reserva atomica via RPC: lockea la fila de clases, valida lugares,
      // inserta y decrementa todo en una transaccion. Elimina la race
      // condition del flujo viejo de 3 pasos separados (SELECT lugares ->
      // INSERT -> decrementar_lugares).
      final res = await _supabase.rpc('apply_reservation', params: {
        'p_user_id': userId,
        'p_clase_id': claseId,
        'p_codigo_qr': codigoQr,
        'p_creditos_usados': creditosReales,
      });

      final ok = res is Map && res['ok'] == true;
      if (!ok) {
        final errorCode = (res is Map ? res['error'] : null)?.toString();
        throw Exception(_mensajeReservaError(errorCode));
      }

      final reservaMap = res['reserva'];
      if (reservaMap is! Map) {
        throw Exception('Respuesta inesperada al crear la reserva.');
      }
      final data = Map<String, dynamic>.from(reservaMap);

      final claseDetalle = await _supabase
          .from(AppConstants.tableClases)
          .select('nombre, fecha, estudio_id, duracion_min')
          .eq('id', claseId)
          .maybeSingle();
      final estudio = claseDetalle == null
          ? null
          : await _supabase
              .from(AppConstants.tableEstudios)
              .select('nombre, direccion')
              .eq('id', claseDetalle['estudio_id'])
              .maybeSingle();
      final fechaDetalle = DateTime.tryParse(
        claseDetalle?['fecha']?.toString() ?? '',
      );
      if (claseDetalle != null && fechaDetalle != null) {
        final notifId = codigoQr.hashCode.abs() % 2147483647;
        await NotificacionesService.instance.scheduleReservaReminder(
          reservaId: notifId,
          titulo: claseDetalle['nombre']?.toString() ?? 'Tu clase',
          estudioNombre: estudio?['nombre']?.toString() ?? 'Aura',
          fechaClase: fechaDetalle,
          direccionEstudio: estudio?['direccion']?.toString(),
          codigoQr: codigoQr,
        );
        final estudioId = (claseDetalle['estudio_id'] as num?)?.toInt();
        final duracionMin = (claseDetalle['duracion_min'] as num?)?.toInt() ?? 60;
        if (estudioId != null) {
          NotificacionesService.instance.scheduleResenaReminder(
            reservaId: notifId,
            claseNombre: claseDetalle['nombre']?.toString() ?? 'Tu clase',
            estudioNombre: estudio?['nombre']?.toString() ?? 'Aura',
            estudioId: estudioId,
            fechaClase: fechaDetalle,
            duracionMin: duracionMin,
          ).ignore();
        }
      }

      // Notify studio (fire-and-forget — never blocks the reservation)
      if (claseDetalle != null) {
        final estudioId = (claseDetalle['estudio_id'] as num?)?.toInt();
        if (estudioId != null) {
          _notifyStudio(
            userId,
            estudioId,
            claseDetalle['nombre']?.toString() ?? 'la clase',
            claseId,
          ).ignore();
        }
      }

      return Reserva.fromMap(data);
    } catch (e) {
      if (!esGratuita && creditosReales > 0) {
        try {
          await _usuariosService.agregarCreditos(userId, creditosReales);
        } catch (_) {
          // Si falla la devolución, priorizamos no ocultar el error original.
        }
      }
      rethrow;
    }
  }

  Future<void> _notifyStudio(
    String userId,
    int estudioId,
    String claseNombre,
    int claseId,
  ) async {
    try {
      final profile = await _supabase
          .from(AppConstants.tableUsuarios)
          .select('nombre')
          .eq('id', userId)
          .maybeSingle();
      final nombre = profile?['nombre']?.toString() ?? 'Un usuario';
      await NotificacionesEstudioService.instance.insertarNuevaReserva(
        estudioId: estudioId,
        claseNombre: claseNombre,
        usuarioNombre: nombre,
        claseId: claseId,
      );
    } catch (_) {}
  }

  /// Cancela la reserva y devuelve los créditos. Lanza excepción si la reserva
  /// no se encuentra. Devuelve la cantidad de créditos restituidos para que la UI
  /// pueda mostrar feedback ("Te devolvimos N créditos").
  Future<int> cancelarReserva(String codigoQr) async {
    // Obtener datos antes de cancelar para devolver créditos + nombre de clase
    final reserva = await _supabase
        .from(AppConstants.tableReservas)
        .select()
        .eq('codigo_qr', codigoQr)
        .maybeSingle();

    if (reserva == null) return 0;

    await _supabase
        .from(AppConstants.tableReservas)
        .update({'estado': 'cancelada'}).eq('codigo_qr', codigoQr);

    final usuarioId = reserva['usuario_id']?.toString() ?? '';
    final creditosUsados = (reserva['creditos_usados'] as num?)?.toInt() ?? 0;
    final claseId = (reserva['clase_id'] as num?)?.toInt();

    // Buscar nombre de clase para la descripción del movimiento
    String claseNombre = 'clase cancelada';
    if (claseId != null) {
      try {
        final clase = await _supabase
            .from(AppConstants.tableClases)
            .select('nombre')
            .eq('id', claseId)
            .maybeSingle();
        final nombre = clase?['nombre']?.toString().trim();
        if (nombre != null && nombre.isNotEmpty) {
          claseNombre = nombre;
        }
      } catch (_) {
        // Non-critical: dejamos el fallback
      }
    }

    // Devolver créditos vía RPC para que quede asentado en creditos_movimientos
    // como entrada de historial. Si falla, fallback a UPDATE directo.
    if (usuarioId.isNotEmpty && creditosUsados > 0) {
      final vencimiento = DateTime.now().add(const Duration(days: 60));
      try {
        await _supabase.rpc('grant_user_credits', params: {
          'p_user_id': usuarioId,
          'p_amount': creditosUsados,
          'p_source': 'devolucion_cancelacion',
          'p_description': 'Devolución — $claseNombre',
          'p_expires_at': vencimiento.toIso8601String(),
        });
      } catch (_) {
        await _usuariosService.agregarCreditos(usuarioId, creditosUsados);
      }
    }

    // Cancelar notificación local (usa hash del código como ID entero)
    final notifId = codigoQr.hashCode.abs() % 2147483647;
    await NotificacionesService.instance.cancelReservaReminder(notifId);

    return creditosUsados;
  }

  /// Called by the studio to cancel a class.
  /// Returns credits to every confirmed reservation and marks them
  /// as 'cancelada_por_estudio'. Returns the number of users refunded.
  Future<int> cancelarClaseConDevolucion(int claseId, String claseNombre) async {
    final reservas = await _supabase
        .from(AppConstants.tableReservas)
        .select()
        .eq('clase_id', claseId)
        .eq('estado', 'confirmada');

    int devueltos = 0;
    for (final raw in (reservas as List)) {
      final reserva = Map<String, dynamic>.from(raw);
      final userId = reserva['usuario_id']?.toString() ?? '';
      final creditos = (reserva['creditos_usados'] as num?)?.toInt() ?? 0;
      final reservaId = (reserva['id'] as num?)?.toInt();

      if (userId.isNotEmpty && creditos > 0) {
        final vencimiento = DateTime.now().add(const Duration(days: 90));
        try {
          await _supabase.rpc('grant_user_credits', params: {
            'p_user_id': userId,
            'p_amount': creditos,
            'p_source': 'devolucion_cancelacion',
            'p_description': 'Devolución por clase cancelada: $claseNombre',
            'p_expires_at': vencimiento.toIso8601String(),
          });
        } catch (_) {
          await _usuariosService.agregarCreditos(userId, creditos);
        }
        devueltos++;
      }

      if (reservaId != null) {
        await _supabase
            .from(AppConstants.tableReservas)
            .update({'estado': 'cancelada_por_estudio'})
            .eq('id', reservaId);
      }
    }

    // Mark the class itself as cancelled
    await _supabase
        .from(AppConstants.tableClases)
        .update({'estado': 'cancelada'})
        .eq('id', claseId);

    return devueltos;
  }

  /// Returns current-month reservations (confirmada or presente) with class data joined.
  Future<List<Map<String, dynamic>>> getReservasMes([String? userId]) async {
    final effectiveUserId = userId ?? _supabase.auth.currentUser?.id ?? '';
    if (effectiveUserId.isEmpty) return [];

    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final lastDay = DateTime(now.year, now.month + 1, 1);

    final reservas = await _supabase
        .from(AppConstants.tableReservas)
        .select()
        .eq('usuario_id', effectiveUserId)
        .inFilter('estado', ['confirmada', 'presente'])
        .gte('created_at', firstDay.toIso8601String())
        .lt('created_at', lastDay.toIso8601String())
        .order('created_at', ascending: false);

    return _joinClasesEstudios(reservas as List);
  }

  Future<bool> tieneReserva(String userId, int claseId) async {
    final data = await _supabase
        .from(AppConstants.tableReservas)
        .select('codigo_qr')
        .eq('usuario_id', userId)
        .eq('clase_id', claseId)
        .neq('estado', 'cancelada')
        .maybeSingle();
    return data != null;
  }

  /// Marca una reserva existente como confirmada (check-in) y registra el momento.
  /// Retorna la reserva actualizada, o null si el código QR no existe.
  Future<Reserva?> confirmarReserva(String codigoQr) async {
    final data = await _supabase
        .from(AppConstants.tableReservas)
        .update({
          'estado': 'confirmada',
          'checked_in_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('codigo_qr', codigoQr)
        .select()
        .maybeSingle();
    if (data == null) return null;
    return Reserva.fromMap(data);
  }

  Future<Map<String, dynamic>?> getReservaPorQr(String codigoQr) async {
    final reserva = await _supabase
        .from(AppConstants.tableReservas)
        .select()
        .eq('codigo_qr', codigoQr)
        .maybeSingle();
    if (reserva == null) return null;

    final clase = await _supabase
        .from(AppConstants.tableClases)
        .select()
        .eq('id', reserva['clase_id'])
        .maybeSingle();

    if (clase != null) {
      final estudio = await _supabase
          .from(AppConstants.tableEstudios)
          .select()
          .eq('id', clase['estudio_id'])
          .maybeSingle();
      return {...reserva, 'clases': {...clase, 'estudios': estudio}};
    }
    return Map<String, dynamic>.from(reserva);
  }

  String _generarCodigoQr(String userId, int claseId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(9999).toString().padLeft(4, '0');
    return 'AURA-${userId.substring(0, 8).toUpperCase()}-$claseId-$timestamp-$random';
  }

  /// Mapea los codigos de error que devuelve la RPC apply_reservation a
  /// mensajes user-friendly. Cualquier codigo desconocido (incluido un
  /// sqlerrm crudo) se devuelve tal cual entre comillas como fallback.
  String _mensajeReservaError(String? code) {
    switch (code) {
      case 'sin_lugares':
        return 'Se acaba de llenar esta clase. No quedan lugares disponibles.';
      case 'clase_no_encontrada':
        return 'No encontramos la clase.';
      case 'clase_cancelada':
        return 'Esta clase fue cancelada por el estudio.';
      case 'codigo_qr_invalido':
        return 'No pudimos generar el código de tu reserva. Probá de nuevo.';
      case 'codigo_qr_duplicado':
        return 'Hubo una colisión generando tu código. Probá de nuevo.';
      case 'parametros_invalidos':
        return 'Faltan datos para crear la reserva. Probá de nuevo.';
      default:
        return code == null || code.isEmpty
            ? 'No se pudo crear la reserva.'
            : 'No se pudo crear la reserva: $code';
    }
  }

  static bool reservaCerrada(DateTime fechaClase, int cierreMinutos) {
    final cierre = fechaClase.subtract(Duration(minutes: cierreMinutos));
    return !DateTime.now().isBefore(cierre);
  }

  static String labelCierreReserva(int cierreMinutos) {
    if (cierreMinutos <= 0) return 'hasta el inicio de la clase';
    if (cierreMinutos % 1440 == 0) {
      final dias = cierreMinutos ~/ 1440;
      return dias == 1 ? 'hasta 1 día antes' : 'hasta $dias días antes';
    }
    if (cierreMinutos % 60 == 0) {
      final horas = cierreMinutos ~/ 60;
      return horas == 1 ? 'hasta 1 hora antes' : 'hasta $horas horas antes';
    }
    return 'hasta $cierreMinutos min antes';
  }

  static String _mensajeCierreReserva(int cierreMinutos) {
    if (cierreMinutos <= 0) {
      return 'Las reservas ya están cerradas para esta clase.';
    }
    return 'Las reservas se cierran ${labelCierreReserva(cierreMinutos)}.';
  }
}
