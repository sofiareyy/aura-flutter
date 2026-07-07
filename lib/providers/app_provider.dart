import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/estudio.dart';
import '../models/usuario.dart';
import '../services/estudios_service.dart';
import '../services/notificaciones_service.dart';
import '../services/usuarios_service.dart';

class AppProvider extends ChangeNotifier {
  final _usuariosService = UsuariosService();
  final _estudiosService = EstudiosService();

  Usuario? _usuario;
  bool _loading = false;
  Estudio? _estudioAsociado;

  Usuario? get usuario => _usuario;
  bool get loading => _loading;
  Estudio? get estudioAsociado => _estudioAsociado;
  bool get isLoggedIn => Supabase.instance.client.auth.currentUser != null;

  /// Rol global del usuario ('usuario', 'profe', 'admin_estudio', 'estudio',
  /// 'admin'). Puede ser null mientras carga.
  String? get rol => _usuario?.rol;

  /// Una profe es un admin de estudio con vista limitada (solo Mis Clases y
  /// Asistencia; sin Cobros, Configuración ni gestión de usuarios).
  bool get esProfe => _usuario?.rol == 'profe';

  String get userId =>
      Supabase.instance.client.auth.currentUser?.id ?? '';

  Future<void> cargarUsuario() async {
    final uid = userId;
    if (uid.isEmpty) return;

    try {
      var usuario = await _usuariosService.getUsuario(uid);
      if (usuario == null) {
        await _usuariosService.crearUsuarioSiNoExiste(uid);
        usuario = await _usuariosService.getUsuario(uid);
      }
      _usuario = usuario;

      // Sentry: adjuntar usuario para identificar errores por cuenta
      if (usuario != null) {
        final uid = usuario.id;
        final email = Supabase.instance.client.auth.currentUser?.email;
        Sentry.configureScope((scope) {
          scope.setUser(SentryUser(id: uid, email: email));
        });
      }

      // Cargar estudio asociado
      await _cargarEstudioAsociado(usuario);

      if (uid.isNotEmpty) {
        final notifRecordatorios = usuario?.notifRecordatorios ?? true;

        // Recordatorios de reservas (1h antes de cada clase)
        await NotificacionesService.instance.syncReservasDelUsuario(
          uid,
          notifEnabled: notifRecordatorios,
        );

        // Recordatorio de vencimiento de créditos (3 días antes)
        if (notifRecordatorios &&
            usuario?.creditosVencimiento != null &&
            (usuario?.creditos ?? 0) > 0) {
          await NotificacionesService.instance.scheduleCreditsExpiryReminder(
            expiresAt: usuario!.creditosVencimiento!,
          );
        } else {
          await NotificacionesService.instance.cancelCreditsExpiryReminder();
        }

        // Recordatorio de renovación de plan (2 días antes)
        if (notifRecordatorios &&
            usuario?.renewalDate != null &&
            usuario?.plan != null &&
            usuario?.subscriptionStatus == 'active') {
          await NotificacionesService.instance.scheduleRenewalReminder(
            renewalDate: usuario!.renewalDate!,
            planNombre: usuario.plan!,
          );
        } else {
          await NotificacionesService.instance.cancelRenewalReminder();
        }

        // Recordatorio de inactividad (si tiene créditos y no reservó en 10+ días)
        if (notifRecordatorios && (usuario?.creditos ?? 0) > 0) {
          _checkInactividadReminder(usuario!.creditos).ignore();
        }
      }
    } catch (_) {
    } finally {
      notifyListeners();
    }
  }

  Future<void> _checkInactividadReminder(int creditos) async {
    try {
      final uid = userId;
      if (uid.isEmpty) return;
      final ultimaReserva = await Supabase.instance.client
          .from('reservas')
          .select('created_at')
          .eq('usuario_id', uid)
          .neq('estado', 'cancelada')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (ultimaReserva == null) return; // Sin reservas, skip
      final fecha = DateTime.tryParse(
          ultimaReserva['created_at']?.toString() ?? '');
      if (fecha == null) return;
      final diasDesde = DateTime.now().difference(fecha).inDays;
      if (diasDesde >= 10) {
        await NotificacionesService.instance
            .scheduleInactividadReminder(creditos);
      }
    } catch (_) {}
  }

  Future<void> _cargarEstudioAsociado(Usuario? usuario) async {
    if (usuario == null) {
      _estudioAsociado = null;
      return;
    }

    // 1. Si ya tiene el id guardado, cargar directamente
    if (usuario.estudioAsociadoId != null) {
      _estudioAsociado = await _estudiosService
          .getEstudio(usuario.estudioAsociadoId!)
          .catchError((_) => null);
      return;
    }

    // 2. Si no, consultar estudio_alumnos por email
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    if (email.isEmpty) {
      _estudioAsociado = null;
      return;
    }

    try {
      final row = await Supabase.instance.client
          .from('estudio_alumnos')
          .select('estudio_id')
          .eq('email', email.toLowerCase())
          .eq('activo', true)
          .maybeSingle();

      final estudioId = (row?['estudio_id'] as num?)?.toInt();
      if (estudioId == null) {
        _estudioAsociado = null;
        return;
      }

      // 3. Persistir en usuarios para no volver a consultar estudio_alumnos
      await Supabase.instance.client
          .from('usuarios')
          .update({'estudio_asociado_id': estudioId})
          .eq('id', usuario.id);

      _estudioAsociado = await _estudiosService.getEstudio(estudioId);
    } catch (_) {
      _estudioAsociado = null;
    }
  }

  Future<void> refrescarUsuario() async {
    await cargarUsuario();
  }

  void setUsuario(Usuario usuario) {
    _usuario = usuario;
    notifyListeners();
  }

  void limpiarUsuario() {
    _usuario = null;
    _estudioAsociado = null;
    Sentry.configureScope((scope) => scope.setUser(null));
    notifyListeners();
  }
}
