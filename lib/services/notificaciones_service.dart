import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificacionesService {
  NotificacionesService._();

  static final NotificacionesService instance = NotificacionesService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Argentina/Buenos_Aires'));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(settings);
    await _requestPermissions();
    _initialized = true;
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  Future<void> scheduleReservaReminder({
    required int reservaId,
    required String titulo,
    required String estudioNombre,
    required DateTime fechaClase,
  }) async {
    await initialize();
    if (kIsWeb) return;

    final reminderAt = fechaClase.subtract(const Duration(hours: 1));
    if (!reminderAt.isAfter(DateTime.now())) return;

    await _plugin.zonedSchedule(
      reservaId,
      'Tu clase empieza en 1 hora',
      '$titulo en $estudioNombre',
      tz.TZDateTime.from(reminderAt, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'aura_reservas',
          'Recordatorios de reservas',
          channelDescription: 'Avisos antes de tus clases y experiencias',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'reserva:$reservaId',
    );
  }

  Future<void> cancelReservaReminder(int reservaId) async {
    if (kIsWeb) return;
    await initialize();
    await _plugin.cancel(reservaId);
  }

  Future<void> syncReservasDelUsuario(String userId) async {
    await initialize();
    if (kIsWeb || userId.isEmpty) return;

    final client = Supabase.instance.client;
    final reservas = await client
        .from('reservas')
        .select()
        .eq('usuario_id', userId)
        .inFilter('estado', ['confirmada', 'presente']);

    for (final raw in (reservas as List)) {
      final row = Map<String, dynamic>.from(raw);
      final reservaId = (row['id'] as num?)?.toInt();
      final claseId = (row['clase_id'] as num?)?.toInt();
      if (reservaId == null || claseId == null) continue;

      final clase = await client
          .from('clases')
          .select('nombre, fecha, estudio_id')
          .eq('id', claseId)
          .maybeSingle();
      if (clase == null) continue;

      final fecha = DateTime.tryParse(clase['fecha']?.toString() ?? '');
      if (fecha == null || !fecha.isAfter(DateTime.now())) {
        await cancelReservaReminder(reservaId);
        continue;
      }

      final estudio = await client
          .from('estudios')
          .select('nombre')
          .eq('id', clase['estudio_id'])
          .maybeSingle();

      await scheduleReservaReminder(
        reservaId: reservaId,
        titulo: clase['nombre']?.toString() ?? 'Tu clase',
        estudioNombre: estudio?['nombre']?.toString() ?? 'Aura',
        fechaClase: fecha,
      );
    }
  }
}
