import 'package:flutter/material.dart';
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

      // Cargar estudio asociado
      await _cargarEstudioAsociado(usuario);

      if (uid.isNotEmpty) {
        await NotificacionesService.instance.syncReservasDelUsuario(uid);
      }
    } catch (_) {
    } finally {
      notifyListeners();
    }
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
    notifyListeners();
  }
}
