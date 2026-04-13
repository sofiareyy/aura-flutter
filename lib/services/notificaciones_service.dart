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

  // IDs fijos para notificaciones únicas (no colisionan con reservaId que son ints pequeños)
  static const int _kCreditsExpiry7dId = 900001;
  static const int _kCreditsExpiry1dId = 900003;
  static const int _kRenewalId = 900002;

  static const _detalleChannel = AndroidNotificationDetails(
    'aura_creditos',
    'Créditos y planes',
    channelDescription:
        'Avisos sobre vencimiento de créditos y renovación de planes',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const _estudioClasesChannel = AndroidNotificationDetails(
    'aura_estudio_clases',
    'Recordatorios de clases (estudio)',
    channelDescription:
        'Avisos 2 horas antes de cada clase para revisar la lista de asistentes',
    importance: Importance.high,
    priority: Priority.high,
  );

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
    String? direccionEstudio,
    bool enabled = true,
  }) async {
    await initialize();
    if (kIsWeb) return;
    if (!enabled) {
      await _plugin.cancel(reservaId);
      return;
    }

    final reminderAt = fechaClase.subtract(const Duration(hours: 1));
    if (!reminderAt.isAfter(DateTime.now())) return;

    final body = direccionEstudio != null && direccionEstudio.isNotEmpty
        ? '$titulo en $estudioNombre\n📍 $direccionEstudio'
        : '$titulo en $estudioNombre';

    await _plugin.zonedSchedule(
      reservaId,
      'Tu clase empieza en 1 hora',
      body,
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

  Future<void> scheduleCreditsExpiryReminder({
    required DateTime expiresAt,
  }) async {
    await initialize();
    if (kIsWeb) return;

    // 7 días antes
    final reminder7d = expiresAt.subtract(const Duration(days: 7));
    if (reminder7d.isAfter(DateTime.now())) {
      await _plugin.zonedSchedule(
        _kCreditsExpiry7dId,
        'Tus créditos vencen en 7 días 🧡',
        'Reservá una clase antes de que expiren',
        tz.TZDateTime.from(reminder7d, tz.local),
        const NotificationDetails(
          android: _detalleChannel,
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'credits_expiry_7d',
      );
    }

    // 1 día antes
    final reminder1d = expiresAt.subtract(const Duration(days: 1));
    if (reminder1d.isAfter(DateTime.now())) {
      await _plugin.zonedSchedule(
        _kCreditsExpiry1dId,
        '¡Mañana vencen tus créditos!',
        'No los pierdas — reservá ahora',
        tz.TZDateTime.from(reminder1d, tz.local),
        const NotificationDetails(
          android: _detalleChannel,
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'credits_expiry_1d',
      );
    }
  }

  Future<void> cancelCreditsExpiryReminder() async {
    if (kIsWeb) return;
    await initialize();
    await _plugin.cancel(_kCreditsExpiry7dId);
    await _plugin.cancel(_kCreditsExpiry1dId);
  }

  Future<void> scheduleRenewalReminder({
    required DateTime renewalDate,
    required String planNombre,
  }) async {
    await initialize();
    if (kIsWeb) return;

    final reminderAt = renewalDate.subtract(const Duration(days: 2));
    if (!reminderAt.isAfter(DateTime.now())) return;

    await _plugin.zonedSchedule(
      _kRenewalId,
      'Tu plan se renueva pronto',
      'Tu plan $planNombre se renueva en 2 días.',
      tz.TZDateTime.from(reminderAt, tz.local),
      const NotificationDetails(
        android: _detalleChannel,
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'renewal:$planNombre',
    );
  }

  Future<void> scheduleListaAsistentesReminder({
    required int claseId,
    required String claseNombre,
    required DateTime fechaClase,
    required int cantidadReservas,
    required String estudioNombre,
  }) async {
    await initialize();
    if (kIsWeb) return;

    final reminderAt = fechaClase.subtract(const Duration(hours: 2));
    if (!reminderAt.isAfter(DateTime.now())) return;

    final notifId = claseId + 10000;
    await _plugin.zonedSchedule(
      notifId,
      'Clase en 2 horas: $claseNombre',
      '$cantidadReservas alumnos reservaron — revisá la lista en Asistencia',
      tz.TZDateTime.from(reminderAt, tz.local),
      const NotificationDetails(
        android: _estudioClasesChannel,
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'lista_asistentes:$claseId',
    );
  }

  Future<void> cancelListaAsistentesReminder(int claseId) async {
    if (kIsWeb) return;
    await initialize();
    await _plugin.cancel(claseId + 10000);
  }

  Future<void> cancelRenewalReminder() async {
    if (kIsWeb) return;
    await initialize();
    await _plugin.cancel(_kRenewalId);
  }

  Future<void> syncReservasDelUsuario(String userId,
      {bool notifEnabled = true}) async {
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
        enabled: notifEnabled,
      );
    }
  }
}
