import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_constants.dart';
import '../models/reserva.dart';
import 'aura_gestion_service.dart';
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
        .order('created_at', ascending: false);

    final result = <Map<String, dynamic>>[];
    for (final r in (reservas as List)) {
      final clase = await _supabase
          .from(AppConstants.tableClases)
          .select()
          .eq('id', r['clase_id'])
          .maybeSingle();
      if (clase != null) {
        final estudio = await _supabase
            .from(AppConstants.tableEstudios)
            .select()
            .eq('id', clase['estudio_id'])
            .maybeSingle();
        result.add({...r, 'clases': {...clase, 'estudios': estudio}});
      } else {
        result.add(Map<String, dynamic>.from(r));
      }
    }
    return result;
  }

  Future<Reserva?> crearReserva({
    required String userId,
    required int claseId,
    required int creditosUsados,
  }) async {
    final clase = await _supabase
        .from(AppConstants.tableClases)
        .select('fecha, reserva_cierre_minutos')
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
      final data = await _supabase
          .from(AppConstants.tableReservas)
          .insert({
            'usuario_id': userId,
            'clase_id': claseId,
            'estado': 'confirmada',
            'creditos_usados': creditosReales,
            'codigo_qr': codigoQr,
          })
          .select()
          .single();

      try {
        await _supabase.rpc('decrementar_lugares', params: {'clase_id': claseId});
      } catch (_) {
        // RPC opcional: no bloquea la reserva.
      }

      final claseDetalle = await _supabase
          .from(AppConstants.tableClases)
          .select('nombre, fecha, estudio_id')
          .eq('id', claseId)
          .maybeSingle();
      final estudio = claseDetalle == null
          ? null
          : await _supabase
              .from(AppConstants.tableEstudios)
              .select('nombre')
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
        );
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

  Future<void> cancelarReserva(String codigoQr) async {
    // Obtener datos antes de cancelar para devolver créditos
    final reserva = await _supabase
        .from(AppConstants.tableReservas)
        .select()
        .eq('codigo_qr', codigoQr)
        .maybeSingle();

    if (reserva == null) return;

    await _supabase
        .from(AppConstants.tableReservas)
        .update({'estado': 'cancelada'}).eq('codigo_qr', codigoQr);

    // Devolver créditos al usuario
    final usuarioId = reserva['usuario_id']?.toString() ?? '';
    final creditosUsados = (reserva['creditos_usados'] as num?)?.toInt() ?? 0;
    if (usuarioId.isNotEmpty && creditosUsados > 0) {
      await _usuariosService.agregarCreditos(usuarioId, creditosUsados);
    }

    // Cancelar notificación local (usa hash del código como ID entero)
    final notifId = codigoQr.hashCode.abs() % 2147483647;
    await NotificacionesService.instance.cancelReservaReminder(notifId);
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
