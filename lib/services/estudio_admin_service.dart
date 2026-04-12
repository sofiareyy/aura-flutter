import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class EstudioAdminService {
  final SupabaseClient _client = Supabase.instance.client;

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

  Future<Map<String, dynamic>?> getCurrentStudio() async {
    final studioId = await getCurrentStudioId();
    if (studioId == null) return null;

    final rows = await _client.from('estudios').select().eq('id', studioId).limit(1);
    if (rows.isNotEmpty) {
      return Map<String, dynamic>.from(rows.first);
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getClasesDeEstudio({
    DateTime? from,
    DateTime? to,
    int? limit,
  }) async {
    final studioId = await getCurrentStudioId();
    if (studioId == null) return [];

final query = _client.from('clases').select().eq('estudio_id', studioId);

    if (from != null) {
      query.gte('fecha', _toSupaDate(from));
    }
    if (to != null) {
      query.lte('fecha', _toSupaDate(to));
    }

    final data = await (limit != null ? query.order('fecha').limit(limit) : query.order('fecha'));
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
    return List<Map<String, dynamic>>.from(data as List);
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

  Future<int> crearHorariosFijosEnGrilla({
    required List<int> diasSemana,
    required TimeOfDay horaInicio,
    required TimeOfDay horaFin,
    required int duracionMin,
    required Map<String, dynamic> payloadBase,
  }) async {
    final studioId = await getCurrentStudioId();
    if (studioId == null) {
      throw Exception('No hay estudio asociado.');
    }

    final dias = diasSemana.toSet().where((d) => d >= 1 && d <= 7).toList()
      ..sort();
    if (dias.isEmpty) {
      throw Exception('Elegí al menos un día.');
    }

    final inicio = horaInicio.hour * 60 + horaInicio.minute;
    final fin = horaFin.hour * 60 + horaFin.minute;
    if (duracionMin <= 0) {
      throw Exception('La duración debe ser mayor a 0.');
    }
    if (fin <= inicio) {
      throw Exception('La hora de fin tiene que ser posterior a la de inicio.');
    }

    final rows = <Map<String, dynamic>>[];
    for (final dia in dias) {
      for (var current = inicio; current + duracionMin <= fin; current += duracionMin) {
        final hh = (current ~/ 60).toString().padLeft(2, '0');
        final mm = (current % 60).toString().padLeft(2, '0');
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
      throw Exception('No se generaron horarios con esa configuración.');
    }

    await _client.from('horarios_fijos').insert(rows);
    await generarProximasSemanasDesdeHorarios();
    return rows.length;
  }

  Future<void> eliminarHorarioFijo(int id) async {
    await _client.from('horarios_fijos').delete().eq('id', id);
  }

  Future<void> editarClase(int id, Map<String, dynamic> payload) async {
    await _client.from('clases').update(payload).eq('id', id);
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

  Future<Map<String, dynamic>> actualizarHorarioFijo(
    int id,
    Map<String, dynamic> payload,
  ) async {
    final updated = await _client
        .from('horarios_fijos')
        .update(payload)
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

    final payload = <String, dynamic>{
      'nombre': horario['nombre'],
      'instructor': horario['instructor'],
      'instructor_descripcion': horario['instructor_descripcion'],
      'incluye': horario['incluye'],
      'imagen_url': horario['imagen_url'],
      'imagen_ajuste': horario['imagen_ajuste'],
      'galeria_urls': horario['galeria_urls'],
      'duracion_min': (horario['duracion_min'] as num?)?.toInt() ?? 60,
      'lugares_total': (horario['lugares_total'] as num?)?.toInt() ?? 12,
      'creditos': (horario['creditos'] as num?)?.toInt() ?? 10,
      'reserva_cierre_minutos':
          (horario['reserva_cierre_minutos'] as num?)?.toInt() ?? 0,
      'categoria': horario['categoria'],
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

  Future<Map<String, int>> generarProximasSemanasDesdeHorarios({int weeks = 2}) async {
    // Usar la fecha actual en UTC-3 (Argentina)
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
      final reservaCierreMinutos =
          (horario['reserva_cierre_minutos'] as num?)?.toInt() ?? 0;
      final categoria = horario['categoria']?.toString();

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
        if (categoria != null && categoria.isNotEmpty) 'categoria': categoria,
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
        if (categoria != null && categoria.isNotEmpty) 'categoria': categoria,
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
