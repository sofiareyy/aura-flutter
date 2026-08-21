import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Handler de mensajes en background/terminada. Tiene que ser una funcion
/// top-level (Flutter la ejecuta en un isolate aparte, sin el estado de la app).
/// No hace falta mostrar nada a mano: cuando el mensaje trae `notification`,
/// el sistema la muestra solo. Esto queda por si despues hay que procesar data.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class NotificacionesService {
  NotificacionesService._();

  static final NotificacionesService instance = NotificacionesService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  void Function(String payload)? _onNotificationTap;

  void setNotificationTapHandler(void Function(String payload) handler) {
    _onNotificationTap = handler;
  }

  // IDs fijos para notificaciones únicas (no colisionan con reservaId que son ints pequeños)
  static const int _kCreditsExpiry7dId = 900001;
  static const int _kCreditsExpiry1dId = 900003;
  static const int _kRenewalId = 900002;
  static const int _kInactividadId = 900010;

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

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (details) {
        final payload = details.payload;
        if (payload != null && payload.isNotEmpty) {
          _onNotificationTap?.call(payload);
        }
      },
    );
    // OJO: aca NO se piden permisos a proposito. `initialize()` corre en main(),
    // o sea al abrir la app por primera vez, ANTES del login: el dialogo de iOS
    // salia en frio, sin que la persona supiera todavia que es Aura. Y en iOS
    // solo hay UN intento: si dice que no, no vuelve a aparecer nunca.
    // El permiso ahora se pide despues del primer login -> pedirPermisos().
    _initialized = true;
  }

  /// Pide el permiso de notificaciones. Se llama DESPUES del login (ver el
  /// authListener de main.dart), no al arrancar la app.
  ///
  /// Idempotente: si ya se concedio o ya se rechazo, el sistema no muestra
  /// nada. En Android 13+ tambien es un permiso explicito.
  Future<void> pedirPermisos() async {
    if (kIsWeb) return;
    await initialize();
    await _requestPermissions();
    // FCM lleva su propio pedido de permiso en iOS (APNs). En Android alcanza
    // con el del plugin local, que ya cubre POST_NOTIFICATIONS de Android 13+.
    if (Platform.isIOS) {
      await FirebaseMessaging.instance
          .requestPermission(alert: true, badge: true, sound: true);
    }
  }

  Future<NotificationAppLaunchDetails?> getLaunchDetails() async {
    if (kIsWeb) return null;
    return _plugin.getNotificationAppLaunchDetails();
  }

  // ══ PUSH (FCM) ═══════════════════════════════════════════════════════════
  // Todo lo de abajo es SOLO mobile. En web no se inicializa Firebase (no hay
  // app web registrada en el proyecto y push web necesitaria service worker +
  // claves VAPID), asi que somosaurapass.com no se toca.

  bool _fcmInitialized = false;

  /// Engancha los tres caminos por los que puede llegar un push. Se llama una
  /// sola vez desde main(), detras de `if (!kIsWeb)`.
  Future<void> initFirebaseMessaging() async {
    if (kIsWeb || _fcmInitialized) return;
    await initialize();

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 1) App ABIERTA: FCM no muestra nada solo, hay que mostrarlo a mano.
    FirebaseMessaging.onMessage.listen((msg) {
      final n = msg.notification;
      if (n == null) return;
      showImmediate(
        id: msg.hashCode & 0x7FFFFFFF,
        titulo: n.title ?? 'Aura',
        body: n.body ?? '',
        payload: _payloadDesdeData(msg.data),
      );
    });

    // 2) App en BACKGROUND y la tocaron.
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      final p = _payloadDesdeData(msg.data);
      if (p != null) _onNotificationTap?.call(p);
    });

    // 3) App CERRADA y la abrieron desde el push.
    final inicial = await FirebaseMessaging.instance.getInitialMessage();
    if (inicial != null) {
      final p = _payloadDesdeData(inicial.data);
      if (p != null) _onNotificationTap?.call(p);
    }

    // El token rota solo; hay que re-registrarlo cuando pasa.
    FirebaseMessaging.instance.onTokenRefresh.listen((t) {
      registrarDispositivo(tokenForzado: t);
    });

    _fcmInitialized = true;
  }

  /// FCM entrega `data` como Map. `_handleNotificationPayload` de main.dart ya
  /// sabe rutear un JSON por `tipo`, asi que se convierte al mismo formato y se
  /// reusa esa logica en vez de escribir un ruteo nuevo.
  String? _payloadDesdeData(Map<String, dynamic> data) {
    if (data.isEmpty) return null;
    try {
      return jsonEncode(data);
    } catch (_) {
      return null;
    }
  }

  /// Guarda el token de este aparato contra el usuario logueado.
  /// Va por RPC (no upsert directo): el token es unico y tiene que poder
  /// CAMBIAR DE DUENO si otra persona se loguea en el mismo celular.
  Future<void> registrarDispositivo({String? tokenForzado}) async {
    if (kIsWeb) return;
    try {
      final cliente = Supabase.instance.client;
      if (cliente.auth.currentUser == null) return;

      final token = tokenForzado ?? await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      String? version;
      try {
        final info = await PackageInfo.fromPlatform();
        version = '${info.version}+${info.buildNumber}';
      } catch (_) {}

      await cliente.rpc('registrar_dispositivo', params: {
        'p_token': token,
        'p_plataforma': Platform.isIOS ? 'ios' : 'android',
        'p_app_version': version,
      });
    } catch (e) {
      debugPrint('[push] no se pudo registrar el dispositivo: $e');
    }
  }

  /// Da de baja este aparato. Se llama ANTES del signOut: si no, a la proxima
  /// persona que se loguee en este celular le seguirian llegando los push de
  /// la cuenta anterior.
  Future<void> borrarDispositivo() async {
    if (kIsWeb) return;
    try {
      final cliente = Supabase.instance.client;
      if (cliente.auth.currentUser == null) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await cliente.rpc('borrar_dispositivo', params: {'p_token': token});
    } catch (e) {
      debugPrint('[push] no se pudo borrar el dispositivo: $e');
    }
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

  /// Notificacion local inmediata (no schedulada). Util para avisos del
  /// momento como "se libero un lugar en tu lista de espera". Si la app
  /// esta cerrada se muestra como banner. Si esta abierta tambien aparece.
  Future<void> showImmediate({
    required int id,
    required String titulo,
    required String body,
    String? payload,
    String channel = 'aura_reservas',
  }) async {
    await initialize();
    if (kIsWeb) return;
    await _plugin.show(
      id,
      titulo,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          'Avisos de Aura',
          channelDescription: 'Notificaciones inmediatas (cupos, recordatorios)',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  Future<void> scheduleReservaReminder({
    required int reservaId,
    required String titulo,
    required String estudioNombre,
    required DateTime fechaClase,
    String? direccionEstudio,
    String? codigoQr,
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

    final payload = jsonEncode({
      'tipo': 'recordatorio_clase',
      'codigo_qr': codigoQr ?? '',
      'clase_nombre': titulo,
      'estudio_nombre': estudioNombre,
    });

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
      payload: payload,
    );
  }

  Future<void> cancelReservaReminder(int reservaId) async {
    if (kIsWeb) return;
    await initialize();
    await _plugin.cancel(reservaId);
  }

  Future<void> scheduleResenaReminder({
    required int reservaId,
    required String claseNombre,
    required String estudioNombre,
    required int estudioId,
    required DateTime fechaClase,
    required int duracionMin,
  }) async {
    await initialize();
    if (kIsWeb) return;

    final reminderAt = fechaClase
        .add(Duration(minutes: duracionMin))
        .add(const Duration(hours: 2));
    if (!reminderAt.isAfter(DateTime.now())) return;

    final notifId = (reservaId + 200000) % 2147483647;

    await _plugin.zonedSchedule(
      notifId,
      '¿Cómo estuvo $claseNombre?',
      'Dejá tu reseña y ayudá a otros a descubrir este lugar 🧡',
      tz.TZDateTime.from(reminderAt, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'aura_resenas',
          'Solicitudes de reseña',
          channelDescription: 'Te pedimos una reseña después de cada clase',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: jsonEncode({
        'tipo': 'recordatorio_resena',
        'estudio_id': estudioId,
        'estudio_nombre': estudioNombre,
      }),
    );
  }

  Future<void> cancelResenaReminder(int reservaId) async {
    if (kIsWeb) return;
    await initialize();
    final notifId = (reservaId + 200000) % 2147483647;
    await _plugin.cancel(notifId);
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

  Future<void> scheduleInactividadReminder(int creditos) async {
    await initialize();
    if (kIsWeb || creditos <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final ultimoStr = prefs.getString('ultimo_recordatorio_inactividad');
    if (ultimoStr != null) {
      final ultimo = DateTime.tryParse(ultimoStr);
      if (ultimo != null && DateTime.now().difference(ultimo).inDays < 7) return;
    }
    final reminderAt = DateTime.now().add(const Duration(hours: 2));
    await _plugin.zonedSchedule(
      _kInactividadId,
      'Tus créditos te esperan 🧡',
      'Tenés $creditos créditos disponibles. ¿Qué querés hacer esta semana?',
      tz.TZDateTime.from(reminderAt, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'aura_inactividad',
          'Recordatorio de actividad',
          channelDescription: 'Te avisamos cuando tenés créditos sin usar',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: jsonEncode({'tipo': 'inactividad_creditos'}),
    );
    await prefs.setString(
        'ultimo_recordatorio_inactividad', DateTime.now().toIso8601String());
  }

  Future<void> syncReservasDelUsuario(String userId,
      {bool notifEnabled = true}) async {
    await initialize();
    if (kIsWeb || userId.isEmpty) return;

    final client = Supabase.instance.client;
    final reservas = await client
        .from('reservas')
        .select('id, clase_id, codigo_qr')
        .eq('usuario_id', userId)
        .inFilter('estado', ['confirmada', 'presente']);

    for (final raw in (reservas as List)) {
      final row = Map<String, dynamic>.from(raw);
      final reservaId = (row['id'] as num?)?.toInt();
      final claseId = (row['clase_id'] as num?)?.toInt();
      final codigoQr = row['codigo_qr']?.toString();
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
        codigoQr: codigoQr,
        enabled: notifEnabled,
      );
    }
  }
}
