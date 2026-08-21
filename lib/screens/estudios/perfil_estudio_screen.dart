import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../models/estudio.dart';
import '../../services/auth_service.dart';
import '../../services/estudio_admin_service.dart';
import '../../services/estudios_service.dart';
import '../../services/media_upload_service.dart';
import '../../utils/datos_cobro.dart';
import '../../widgets/categorias_checklist.dart';
import '../../widgets/eliminar_cuenta_helper.dart';

class PerfilEstudioScreen extends StatefulWidget {
  const PerfilEstudioScreen({super.key});

  @override
  State<PerfilEstudioScreen> createState() => _PerfilEstudioScreenState();
}

class _PerfilEstudioScreenState extends State<PerfilEstudioScreen> {
  final _mediaUploadService = MediaUploadService();
  final _adminService = EstudioAdminService();
  final _estudiosService = EstudiosService();
  Map<String, dynamic>? _estudio;
  List<Map<String, dynamic>> _admins = [];
  List<Map<String, dynamic>> _profes = [];
  bool _loading = true;
  bool _uploadingPhoto = false;
  bool _uploadingGaleria = false;
  bool _guardandoCierres = false;
  bool _guardandoDescripcion = false;
  /// Las acciones destructivas arrancan colapsadas (FIX 4).
  bool _avanzadasAbiertas = false;
  String? _error;

  List<String> get _galeriaUrls => _parseUrlList(_estudio?['galeria_urls']);

  /// Parsea `galeria_urls` (text[] en Postgres). En el camino feliz vuelve
  /// como `List<dynamic>`. Pero PostgREST puede devolverlo como string con
  /// literal de array (`"{url1,url2}"`) en algunas combinaciones de Accept
  /// y de select; cubrimos ese caso para no perder fotos en el panel.
  static List<String> _parseUrlList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((entry) => entry?.toString().trim() ?? '')
          .where((entry) => entry.isNotEmpty)
          .toList();
    }
    if (raw is String) {
      var s = raw.trim();
      if (s.isEmpty || s == '{}') return const [];
      if (s.startsWith('{') && s.endsWith('}')) {
        s = s.substring(1, s.length - 1);
      }
      return s
          .split(',')
          .map((e) => e.trim().replaceAll(RegExp(r'^"|"$'), ''))
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'No hay una sesión activa.';
        });
        return;
      }

      final userData = await Supabase.instance.client
          .from('usuarios')
          .select('estudio_id')
          .eq('id', uid)
          .maybeSingle();

      final estudioId = userData?['estudio_id'];
      if (estudioId == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Tu usuario no tiene un estudio asociado todavía.';
          _estudio = null;
          _admins = [];
          _profes = [];
        });
        return;
      }

      // Con los datos de cobro embebidos y aplanados: esta pantalla muestra y
      // edita CBU/alias/banco/titular, que ya no viven en `estudios`.
      final estudioRow = await Supabase.instance.client
          .from('estudios')
          .select(DatosCobro.embedTodo)
          .eq('id', estudioId)
          .maybeSingle();
      final estudio = estudioRow == null
          ? null
          : DatosCobro.aplanar(Map<String, dynamic>.from(estudioRow));

      // Lista de admins del estudio: usa la tabla estudio_admins (M:N), via
      // service. Necesita el SQL supabase/MULTI_ESTUDIO_ADMINS.sql aplicado.
      final admins = (estudioId is num)
          ? await _adminService.listEstudioAdmins(estudioId.toInt())
          : <Map<String, dynamic>>[];

      // Profes del estudio (rol limitado), via RPC dedicado.
      final profes = (estudioId is num)
          ? await _adminService.listProfes(estudioId.toInt())
          : <Map<String, dynamic>>[];

      if (!mounted) return;
      setState(() {
        _estudio = estudio;
        // La sección "Administradores" no debe listar profes (van en su
        // propia sección "Mis Profes").
        _admins =
            admins.where((a) => a['rol']?.toString() != 'profe').toList();
        _profes = profes;
        _loading = false;
        _error = estudio == null ? 'No encontramos datos del estudio.' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar el perfil del estudio.';
      });
    }
  }

  Future<void> _subirFotoEstudio() async {
    if (_estudio == null || _uploadingPhoto) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return;

    setState(() => _uploadingPhoto = true);
    try {
      final url = await _mediaUploadService.pickAndUpload(
        bucket: 'study-media',
        folder: 'study-profile',
        userId: userId,
      );
      if (url == null) return;

      await Supabase.instance.client
          .from('estudios')
          .update({'foto_url': url})
          .eq('id', _estudio!['id']);

      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Foto del estudio actualizada.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo subir la foto: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _subirFotoGaleria() async {
    if (_estudio == null || _uploadingGaleria) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return;

    setState(() => _uploadingGaleria = true);
    try {
      final url = await _mediaUploadService.pickAndUpload(
        bucket: 'study-media',
        folder: 'study-gallery',
        userId: userId,
      );
      if (url == null) return;

      final nueva = [..._galeriaUrls, url];
      await Supabase.instance.client
          .from('estudios')
          .update({'galeria_urls': nueva})
          .eq('id', _estudio!['id']);

      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Foto agregada a la galería.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo subir la foto: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingGaleria = false);
    }
  }

  Future<void> _eliminarFotoGaleria(String url) async {
    if (_estudio == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar foto'),
        content: const Text('Se va a sacar de la galería del estudio.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Borrar',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final nueva = _galeriaUrls.where((entry) => entry != url).toList();
    try {
      await Supabase.instance.client
          .from('estudios')
          .update({'galeria_urls': nueva})
          .eq('id', _estudio!['id']);
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo borrar la foto: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _eliminarAdmin(String adminId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar administrador'),
        content: const Text('Esta persona dejará de administrar el estudio.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final estudioId = (_estudio?['id'] as num?)?.toInt();
    if (estudioId == null) return;

    final ok = await _adminService.removeEstudioAdminAccess(
      estudioId: estudioId,
      usuarioId: adminId,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo eliminar el administrador.')),
      );
      return;
    }

    await _cargar();
  }

  Future<void> _agregarAdmin() async {
    final emailCtrl = TextEditingController();
    String? email;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Agregar administrador'),
        content: TextField(
          controller: emailCtrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            hintText: 'Email del usuario',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              email = emailCtrl.text.trim();
              Navigator.pop(ctx);
            },
            child: const Text(
              'Agregar',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
    emailCtrl.dispose();

    if (email == null || email!.isEmpty || _estudio == null) return;

    final estudioId = (_estudio?['id'] as num?)?.toInt();
    if (estudioId == null) return;

    String? errorMsg;
    try {
      final res = await Supabase.instance.client.rpc(
        'studio_promote_user_to_admin',
        params: {
          'p_estudio_id': estudioId,
          'p_email': email,
        },
      );
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (map['ok'] != true) {
        switch (map['error']?.toString()) {
          case 'user_not_found':
            errorMsg = 'No existe una cuenta Aura con ese email.';
            break;
          case 'forbidden':
          case 'not_owner_of_estudio':
            errorMsg = 'No tenés permisos para agregar admins a este estudio.';
            break;
          case 'email_required':
            errorMsg = 'Ingresá un email válido.';
            break;
          default:
            errorMsg = 'No se pudo agregar el administrador.';
        }
      }
    } catch (e) {
      errorMsg = 'Error: ${e.toString()}';
    }

    if (!mounted) return;

    if (errorMsg != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg)),
      );
      return;
    }

    await _cargar();
  }

  // ── Profes ────────────────────────────────────────────────────────────────

  Future<void> _agregarProfe() async {
    final emailCtrl = TextEditingController();
    String? email;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Agregar profe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'La profe ya tiene que tener una cuenta en Aura. Verá solo Mis '
              'Clases y Asistencia (sin cobros ni configuración).',
              style: TextStyle(color: AppColors.grey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'Email de la profe',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              email = emailCtrl.text.trim();
              Navigator.pop(ctx);
            },
            child: const Text(
              'Agregar',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
    emailCtrl.dispose();

    if (email == null || email!.isEmpty || _estudio == null) return;

    final estudioId = (_estudio?['id'] as num?)?.toInt();
    if (estudioId == null) return;

    String? errorMsg;
    try {
      final res = await _adminService.addProfe(
        estudioId: estudioId,
        email: email!,
      );
      if (res['ok'] != true) {
        switch (res['error']?.toString()) {
          case 'user_not_found':
            errorMsg = 'No existe una cuenta Aura con ese email. '
                'Pedile que se registre primero.';
            break;
          case 'forbidden':
            errorMsg = 'No tenés permisos para agregar profes a este estudio.';
            break;
          case 'email_required':
            errorMsg = 'Ingresá un email válido.';
            break;
          default:
            errorMsg = 'No se pudo agregar la profe.';
        }
      }
    } catch (e) {
      errorMsg = 'Error: ${e.toString()}';
    }

    if (!mounted) return;

    if (errorMsg != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg)),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profe agregada.')),
    );
    await _cargar();
  }

  Future<void> _eliminarProfe(String profeId, String nombre) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar profe'),
        content: Text('$nombre dejará de tener acceso al panel del estudio.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final estudioId = (_estudio?['id'] as num?)?.toInt();
    if (estudioId == null) return;

    final ok = await _adminService.removeEstudioAdminAccess(
      estudioId: estudioId,
      usuarioId: profeId,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo eliminar la profe.')),
      );
      return;
    }
    await _cargar();
  }

  /// Máximo de horas de la ventana de cancelación. Política de Aura: el
  /// estudio puede acortarla pero no estirarla. Espejado en el RPC
  /// `set_estudio_cierres` y en la constraint `estudios_cierres_rango_check`.
  static final int _maxCancelacionHoras =
      AppConstants.cancelacionCierreMinutosDefault ~/ 60;

  List<String> get _categoriasEstudio => _estudio == null
      ? const []
      : Estudio.parseCategorias(Map<String, dynamic>.from(_estudio!));

  /// FEATURE 5 — El estudio elige sus propias categorías (puede ser Pilates
  /// + Barre + Yoga a la vez). Antes solo se editaban desde el backoffice.
  Future<void> _editarCategorias() async {
    if (_estudio == null) return;
    final disponibles = await _estudiosService.getCategorias();
    if (!mounted) return;

    final seleccion = [..._categoriasEstudio];

    final guardar = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Categorías del estudio',
                style: TextStyle(
                  color: AppColors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Elegí todas las que hagas. Tu estudio aparece cuando el '
                'usuario filtra por cualquiera de ellas.',
                style: TextStyle(color: AppColors.grey, fontSize: 13),
              ),
              const SizedBox(height: 20),
              CategoriasChecklist(
                disponibles: disponibles,
                seleccionadas: seleccion,
                onToggle: (cat, marcada) => setSheet(() {
                  if (marcada) {
                    if (!seleccion.contains(cat)) seleccion.add(cat);
                  } else {
                    seleccion.remove(cat);
                  }
                }),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: seleccion.isEmpty
                      ? null
                      : () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Guardar'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: AppColors.grey),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (guardar != true || !mounted) return;

    try {
      await Supabase.instance.client.from('estudios').update({
        'categorias': seleccion,
        // Escalar sincronizado con la primera, para queries legacy.
        'categoria': seleccion.first,
      }).eq('id', _estudio!['id']);
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Categorías actualizadas.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudieron guardar las categorías: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// FIX 4 — Puerta de confirmación por texto para acciones irreversibles.
  /// Pide escribir CONFIRMAR: un tap accidental o un "Sí" por inercia no
  /// alcanzan. Si el usuario confirma, corre `accion`.
  Future<void> _confirmarYEjecutar({
    required String titulo,
    required String mensaje,
    required Future<void> Function() accion,
  }) async {
    const palabra = 'CONFIRMAR';
    final ctrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final habilitado = ctrl.text.trim().toUpperCase() == palabra;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(titulo),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mensaje,
                  style: const TextStyle(color: AppColors.grey, fontSize: 14),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Escribí CONFIRMAR para continuar',
                  style: TextStyle(
                    color: AppColors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setDialog(() {}),
                  decoration: InputDecoration(
                    hintText: palabra,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: AppColors.grey),
                ),
              ),
              TextButton(
                onPressed:
                    habilitado ? () => Navigator.of(ctx).pop(true) : null,
                child: Text(
                  'Continuar',
                  style: TextStyle(
                    color: habilitado ? AppColors.error : AppColors.grey,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    ctrl.dispose();
    if (ok == true) await accion();
  }

  /// FIX 3 — Las dos ventanas de tiempo del estudio. Son reglas distintas y
  /// se guardan por separado: cerrar reservas 2 hs antes no obliga a cerrar
  /// las cancelaciones 2 hs antes.
  /// Editar la descripción del estudio (lo que ven los alumnos en el perfil).
  /// La columna `descripcion` no está bloqueada por el trigger de columnas de
  /// Aura, así que se puede guardar con un update directo del cliente.
  Future<void> _editarDescripcion() async {
    final estudioId = (_estudio?['id'] as num?)?.toInt();
    if (estudioId == null) return;
    final ctrl =
        TextEditingController(text: _estudio?['descripcion']?.toString() ?? '');

    final guardar = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).padding.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Descripción del estudio',
                style: TextStyle(
                    color: AppColors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Contá de qué se trata tu estudio. Es lo que ven tus alumnos en '
                'el perfil.',
                style: TextStyle(color: AppColors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                maxLines: 5,
                maxLength: 600,
                decoration: InputDecoration(
                  hintText:
                      'Ej: Estudio de pilates y yoga en Palermo, con clases '
                      'para todos los niveles…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Guardar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final texto = ctrl.text.trim();
    ctrl.dispose();
    if (guardar != true || !mounted) return;

    setState(() => _guardandoDescripcion = true);
    try {
      await Supabase.instance.client.from('estudios').update({
        'descripcion': texto.isEmpty ? null : texto,
      }).eq('id', estudioId);
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Descripción actualizada.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar la descripción: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _guardandoDescripcion = false);
    }
  }

  Future<void> _editarCierres() async {
    final estudioId = (_estudio?['id'] as num?)?.toInt();
    if (estudioId == null) return;

    // Default 1 h (coincide con AppConstants.reservaCierreMinutosDefault): si el
    // estudio nunca lo tocó, mostramos 1 h en vez de 0.
    int reservaHoras = _horasDe('reserva_cierre_minutos', 1);
    // Clamp al tope: si en la base quedó un valor viejo por encima de 12 hs,
    // el stepper lo baja al máximo en vez de mostrar algo que ya no se puede
    // guardar (el RPC y la constraint también lo rechazan).
    int cancelacionHoras =
        _horasDe('cancelacion_cierre_minutos', 12).clamp(0, _maxCancelacionHoras);

    final guardar = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Reservas y cancelaciones',
                style: TextStyle(
                  color: AppColors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Aplica a todas tus clases. Podés cambiarlo en una clase '
                'puntual desde el formulario de esa clase.',
                style: TextStyle(color: AppColors.grey, fontSize: 13),
              ),
              const SizedBox(height: 20),
              _HorasStepper(
                label: 'Cierre de reservas (horas antes)',
                helper: reservaHoras == 0
                    ? 'Se puede reservar hasta que la clase arranca.'
                    : 'Nadie puede reservar en las últimas '
                        '$reservaHoras h antes de la clase.',
                value: reservaHoras,
                maxHoras: 48,
                onChanged: (v) => setSheet(() => reservaHoras = v),
              ),
              const SizedBox(height: 18),
              _HorasStepper(
                label: 'Límite de cancelación (horas antes)',
                helper: cancelacionHoras == 0
                    ? 'Se puede cancelar hasta que la clase arranca.'
                    : cancelacionHoras >= _maxCancelacionHoras
                        ? 'Cancelar con menos de $cancelacionHoras h consume '
                            'los créditos. Es el máximo permitido.'
                        : 'Cancelar con menos de $cancelacionHoras h consume '
                            'los créditos.',
                value: cancelacionHoras,
                // Tope duro: el estudio puede BAJARLO, nunca subirlo de 12 hs.
                maxHoras: _maxCancelacionHoras,
                onChanged: (v) => setSheet(() => cancelacionHoras = v),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Guardar'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: AppColors.grey),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (guardar != true || !mounted) return;

    setState(() => _guardandoCierres = true);
    final ok = await _adminService.guardarCierresEstudio(
      estudioId: estudioId,
      reservaCierreMinutos: reservaHoras * 60,
      cancelacionCierreMinutos: cancelacionHoras * 60,
    );
    if (!mounted) return;
    setState(() {
      _guardandoCierres = false;
      if (ok && _estudio != null) {
        _estudio!['reserva_cierre_minutos'] = reservaHoras * 60;
        _estudio!['cancelacion_cierre_minutos'] = cancelacionHoras * 60;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Configuración guardada.'
            : 'No pudimos guardar la configuración.'),
        backgroundColor: ok ? null : AppColors.error,
      ),
    );
  }

  /// Lee una columna en minutos y la devuelve en horas enteras.
  int _horasDe(String columna, int fallbackHoras) {
    final min = (_estudio?[columna] as num?)?.toInt();
    if (min == null) return fallbackHoras;
    return (min / 60).round();
  }

  Future<void> _editarDatosBancarios() async {
    if (_estudio == null) return;

    final titularCtrl =
        TextEditingController(text: _estudio?['titular']?.toString() ?? '');
    final bancoCtrl =
        TextEditingController(text: _estudio?['banco']?.toString() ?? '');
    final aliasCtrl =
        TextEditingController(text: _estudio?['alias']?.toString() ?? '');
    final cbuCtrl =
        TextEditingController(text: _estudio?['cbu']?.toString() ?? '');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Datos bancarios',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.black,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Estos datos se usan para liquidarte los pagos de Aura.',
              style: TextStyle(color: Color(0xFF8F877F), fontSize: 13),
            ),
            const SizedBox(height: 20),
            _BankField(
              controller: titularCtrl,
              label: 'Titular de la cuenta',
              hint: 'Nombre y apellido o razón social',
            ),
            const SizedBox(height: 14),
            _BankField(
              controller: bancoCtrl,
              label: 'Banco',
              hint: 'Ej: Banco Galicia',
            ),
            const SizedBox(height: 14),
            _BankField(
              controller: aliasCtrl,
              label: 'Alias',
              hint: 'Ej: MI.ESTUDIO.AURA',
            ),
            const SizedBox(height: 14),
            _BankField(
              controller: cbuCtrl,
              label: 'CBU',
              hint: '22 dígitos',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar'),
              ),
            ),
          ],
        ),
      ),
    );

    final titular = titularCtrl.text.trim();
    final banco = bancoCtrl.text.trim();
    final alias = aliasCtrl.text.trim();
    final cbu = cbuCtrl.text.trim();

    titularCtrl.dispose();
    bancoCtrl.dispose();
    aliasCtrl.dispose();
    cbuCtrl.dispose();

    if (saved != true || _estudio == null) return;

    try {
      final datos = {
        'titular': titular.isEmpty ? null : titular,
        'banco': banco.isEmpty ? null : banco,
        'alias': alias.isEmpty ? null : alias,
        'cbu': cbu.isEmpty ? null : cbu,
      };
      // Los datos bancarios viven solo en estudios_datos_cobro: `estudios` es
      // el catálogo público y ya no tiene esas columnas.
      await Supabase.instance.client
          .from('estudios_datos_cobro')
          .upsert({'estudio_id': _estudio!['id'], ...datos},
              onConflict: 'estudio_id');

      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Datos bancarios actualizados.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo guardar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _dejarDeAdministrar() async {
    final estudioId = (_estudio?['id'] as num?)?.toInt();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (estudioId == null || userId == null) return;

    final esUnicoAdmin = _admins.length == 1 &&
        (_admins.first['id']?.toString() ?? '') == userId;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          esUnicoAdmin
              ? 'Sos el único administrador'
              : '¿Dejar de administrar este estudio?',
        ),
        content: Text(
          esUnicoAdmin
              ? 'Sos el único administrador de este estudio. Si te vas, nadie puede gestionarlo. ¿Estás segura?'
              : 'Vas a dejar de tener acceso a este estudio. Los otros administradores siguen pudiendo gestionarlo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              esUnicoAdmin ? 'Sí, irme igual' : 'Dejar de administrar',
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final ok = await _adminService.removeEstudioAdminAccess(
      estudioId: estudioId,
      usuarioId: userId,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo dejar el estudio.')),
      );
      return;
    }

    // Decidir el destino segun si el usuario sigue siendo admin de otro estudio
    String destino = '/home';
    try {
      final row = await Supabase.instance.client
          .from('usuarios')
          .select('rol')
          .eq('id', userId)
          .maybeSingle();
      final rol = row?['rol']?.toString();
      if (rol == 'estudio' || rol == 'admin_estudio') {
        destino = '/estudio/dashboard';
      }
    } catch (_) {}

    if (!mounted) return;
    context.go(destino);
  }

  Future<void> _cerrarSesion() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text('¿Querés salir del panel del estudio?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Cerrar sesión',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await AuthService().signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => context.go('/estudio/dashboard'),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Perfil del estudio',
                        style: TextStyle(
                          color: AppColors.black,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_error != null) _ErrorCard(message: _error!),
                  if (_error == null) ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          if ((_estudio?['foto_url']?.toString() ?? '').isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.network(
                                _estudio!['foto_url'].toString(),
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _avatarFallback(),
                              ),
                            )
                          else
                            _avatarFallback(),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _uploadingPhoto ? null : _subirFotoEstudio,
                            icon: _uploadingPhoto
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primary,
                                    ),
                                  )
                                : const Icon(Icons.photo_camera_outlined),
                            label: const Text('Cambiar foto principal'),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _estudio?['nombre']?.toString() ?? 'Estudio',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.black,
                            ),
                          ),
                          // Un estudio puede tener varias categorías: un pill
                          // por cada una.
                          if (_categoriasEstudio.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              alignment: WrapAlignment.center,
                              children: _categoriasEstudio
                                  .map(
                                    (cat) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryLight,
                                        borderRadius:
                                            BorderRadius.circular(9999),
                                      ),
                                      child: Text(
                                        cat,
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                          const SizedBox(height: 6),
                          TextButton.icon(
                            onPressed: _editarCategorias,
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: Text(
                              _categoriasEstudio.isEmpty
                                  ? 'Elegir categorías'
                                  : 'Editar categorías',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          if ((_estudio?['direccion']?.toString() ?? '').isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.location_on_rounded,
                                  color: AppColors.grey,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    _estudio?['direccion']?.toString() ?? '',
                                    style: const TextStyle(
                                      color: AppColors.grey,
                                      fontSize: 13,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 10),
                      child: Text(
                        'GALERÍA DEL LUGAR',
                        style: TextStyle(
                          color: AppColors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Mostrale al usuario cómo es tu estudio. Estas fotos NO son las de las clases.',
                            style: TextStyle(
                              color: AppColors.grey,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (_galeriaUrls.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 22),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F3EE),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'Todavía no hay fotos.',
                                style: TextStyle(
                                  color: AppColors.grey,
                                  fontSize: 13,
                                ),
                              ),
                            )
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _galeriaUrls.map((url) {
                                return Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(
                                        url,
                                        width: 96,
                                        height: 96,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          width: 96,
                                          height: 96,
                                          color: const Color(0xFFEDE7E1),
                                          child: const Icon(
                                            Icons.image_not_supported_outlined,
                                            color: AppColors.grey,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 2,
                                      right: 2,
                                      child: GestureDetector(
                                        onTap: () => _eliminarFotoGaleria(url),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close_rounded,
                                            color: Colors.white,
                                            size: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _uploadingGaleria
                                  ? null
                                  : _subirFotoGaleria,
                              icon: _uploadingGaleria
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.primary,
                                      ),
                                    )
                                  : const Icon(Icons.add_photo_alternate_outlined),
                              label: Text(
                                _uploadingGaleria
                                    ? 'Subiendo…'
                                    : 'Agregar foto a la galería',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 10),
                      child: Text(
                        'ADMINISTRADORES',
                        style: TextStyle(
                          color: AppColors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          if (_admins.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                'Todavía no hay otros administradores asociados.',
                                style: TextStyle(
                                  color: AppColors.grey,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ..._admins.asMap().entries.map((entry) {
                            final admin = entry.value;
                            final nombre =
                                admin['nombre']?.toString() ?? 'Sin nombre';
                            final isLast = entry.key == _admins.length - 1;
                            return Column(
                              children: [
                                ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.primaryLight,
                                    child: Text(
                                      nombre.isNotEmpty
                                          ? nombre[0].toUpperCase()
                                          : 'A',
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    nombre,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  subtitle: Text(
                                    admin['email']?.toString() ?? '',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.grey,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: AppColors.error,
                                    ),
                                    onPressed: () =>
                                        _eliminarAdmin(admin['id'].toString()),
                                  ),
                                ),
                                if (!isLast)
                                  const Divider(height: 1, indent: 56),
                              ],
                            );
                          }),
                          ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.add_rounded,
                                color: AppColors.primary,
                              ),
                            ),
                            title: const Text(
                              'Agregar administrador',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            onTap: _agregarAdmin,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 10),
                      child: Text(
                        'MIS PROFES',
                        style: TextStyle(
                          color: AppColors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Las profes ven solo Mis Clases y Asistencia. '
                                'No acceden a Cobros, Configuración ni datos '
                                'bancarios.',
                                style: TextStyle(
                                  color: AppColors.grey,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                          if (_profes.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Todavía no agregaste profes.',
                                  style: TextStyle(
                                    color: AppColors.grey,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ..._profes.asMap().entries.map((entry) {
                            final profe = entry.value;
                            final nombre =
                                profe['nombre']?.toString() ?? 'Sin nombre';
                            final isLast = entry.key == _profes.length - 1;
                            return Column(
                              children: [
                                ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.primaryLight,
                                    child: Text(
                                      nombre.isNotEmpty
                                          ? nombre[0].toUpperCase()
                                          : 'P',
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    nombre,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  subtitle: Text(
                                    profe['email']?.toString() ?? '',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.grey,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: AppColors.error,
                                    ),
                                    onPressed: () => _eliminarProfe(
                                      profe['id'].toString(),
                                      nombre,
                                    ),
                                  ),
                                ),
                                if (!isLast)
                                  const Divider(height: 1, indent: 56),
                              ],
                            );
                          }),
                          ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.add_rounded,
                                color: AppColors.primary,
                              ),
                            ),
                            title: const Text(
                              'Agregar profe',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            onTap: _agregarProfe,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 10),
                      child: Text(
                        'DATOS BANCARIOS',
                        style: TextStyle(
                          color: AppColors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    _BankDataCard(
                      estudio: _estudio,
                      onEdit: _editarDatosBancarios,
                    ),
                    const SizedBox(height: 24),
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 10),
                      child: Text(
                        'CONFIGURACIÓN',
                        style: TextStyle(
                          color: AppColors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    _CierresCard(
                      reservaMinutos: _estudio?['reserva_cierre_minutos'],
                      cancelacionMinutos:
                          _estudio?['cancelacion_cierre_minutos'],
                      guardando: _guardandoCierres,
                      onEdit: _editarCierres,
                    ),
                    const SizedBox(height: 16),
                    _DescripcionCard(
                      descripcion: _estudio?['descripcion']?.toString(),
                      guardando: _guardandoDescripcion,
                      onEdit: _editarDescripcion,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => context.go('/home'),
                        icon: const Icon(Icons.home_outlined),
                        label: const Text('Cambiar al lado usuario'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _cerrarSesion,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Cerrar sesión'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // FIX 4 — Acciones irreversibles: colapsadas, al final, y
                  // detrás de una confirmación escribiendo CONFIRMAR.
                  _OpcionesAvanzadas(
                    expanded: _avanzadasAbiertas,
                    onToggle: () => setState(
                        () => _avanzadasAbiertas = !_avanzadasAbiertas),
                    children: [
                      if (_error == null)
                        _AccionPeligrosa(
                          icon: Icons.exit_to_app_rounded,
                          label: 'Dejar de administrar el estudio',
                          detalle:
                              'Perdés el acceso al panel. El estudio y sus '
                              'clases siguen existiendo.',
                          onTap: () => _confirmarYEjecutar(
                            titulo: 'Dejar de administrar',
                            mensaje:
                                'Vas a perder el acceso al panel de este '
                                'estudio.',
                            accion: _dejarDeAdministrar,
                          ),
                        ),
                      // Eliminar cuenta — requisito Apple App Store 5.1.1.
                      // contextoEstudio=true: desde el panel sabemos que el
                      // usuario administra al menos un estudio.
                      _AccionPeligrosa(
                        icon: Icons.delete_forever_rounded,
                        label: 'Eliminar mi cuenta',
                        detalle:
                            'Se borra tu cuenta y todas las clases de tu '
                            'estudio. No se puede deshacer.',
                        onTap: () => _confirmarYEjecutar(
                          titulo: 'Eliminar mi cuenta',
                          mensaje:
                              'Esta acción es permanente. Se eliminan tu '
                              'cuenta y todas las clases de tu estudio.',
                          accion: () async => EliminarCuentaFlow.ejecutar(
                            context,
                            contextoEstudio: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _avatarFallback() {
    final nombre = _estudio?['nombre']?.toString() ?? 'Estudio';
    final inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : 'E';
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          inicial,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _BankDataCard extends StatelessWidget {
  final Map<String, dynamic>? estudio;
  final VoidCallback onEdit;

  const _BankDataCard({required this.estudio, required this.onEdit});

  bool get _hasData =>
      (estudio?['cbu']?.toString() ?? '').isNotEmpty ||
      (estudio?['alias']?.toString() ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasData) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEDE7E1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sin datos bancarios',
              style: TextStyle(
                color: AppColors.black,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Completá tus datos para recibir los pagos de Aura.',
              style: TextStyle(color: Color(0xFF8F877F), fontSize: 13),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onEdit,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Completar datos bancarios'),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Cuenta bancaria',
                    style: TextStyle(
                      color: AppColors.black,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onEdit,
                  child: const Text(
                    'Editar',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          if ((estudio?['titular']?.toString() ?? '').isNotEmpty)
            _BankInfoRow(
              icon: Icons.person_outline_rounded,
              label: 'Titular',
              value: estudio!['titular'].toString(),
            ),
          if ((estudio?['banco']?.toString() ?? '').isNotEmpty)
            _BankInfoRow(
              icon: Icons.business_outlined,
              label: 'Banco',
              value: estudio!['banco'].toString(),
            ),
          if ((estudio?['alias']?.toString() ?? '').isNotEmpty)
            _BankInfoRow(
              icon: Icons.alternate_email_rounded,
              label: 'Alias',
              value: estudio!['alias'].toString(),
            ),
          if ((estudio?['cbu']?.toString() ?? '').isNotEmpty)
            _BankInfoRow(
              icon: Icons.account_balance_outlined,
              label: 'CBU',
              value: estudio!['cbu'].toString(),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _BankInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _BankInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF8F877F)),
          const SizedBox(width: 10),
          Text(
            '$label:  ',
            style: const TextStyle(
              color: Color(0xFF8F877F),
              fontSize: 13,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.black,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BankField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;

  const _BankField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF8F877F),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 15, color: AppColors.black),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFFB0A8A0), fontSize: 14),
            filled: true,
            fillColor: AppColors.background,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDDD7D0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AppColors.black,
          fontSize: 15,
        ),
      ),
    );
  }
}

/// FIX 3 — Resumen de las dos ventanas de tiempo del estudio.
class _CierresCard extends StatelessWidget {
  final Object? reservaMinutos;
  final Object? cancelacionMinutos;
  final bool guardando;
  final VoidCallback onEdit;

  const _CierresCard({
    required this.reservaMinutos,
    required this.cancelacionMinutos,
    required this.guardando,
    required this.onEdit,
  });

  /// `null` en la columna = el estudio nunca la configuró: mostramos el
  /// default vigente para no dejar la fila en blanco.
  static String _texto(Object? minutos, int fallbackHoras) {
    final min = (minutos as num?)?.toInt() ?? fallbackHoras * 60;
    if (min <= 0) return 'Hasta que arranca la clase';
    final horas = (min / 60).round();
    return horas == 1 ? '1 hora antes' : '$horas horas antes';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDE7E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CierreRow(
            label: 'Cierre de reservas',
            value: _texto(reservaMinutos, 1),
          ),
          const SizedBox(height: 12),
          _CierreRow(
            label: 'Límite de cancelación',
            value: _texto(cancelacionMinutos, 12),
          ),
          const SizedBox(height: 14),
          const Text(
            'Tus alumnos ven esta política en el detalle de cada clase.',
            style: TextStyle(color: Color(0xFF8F877F), fontSize: 12),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: guardando ? null : onEdit,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: guardando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : const Text('Editar'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DescripcionCard extends StatelessWidget {
  final String? descripcion;
  final bool guardando;
  final VoidCallback onEdit;

  const _DescripcionCard({
    required this.descripcion,
    required this.guardando,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final tiene = (descripcion?.trim().isNotEmpty ?? false);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDE7E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Descripción del estudio',
            style: TextStyle(
                color: AppColors.black,
                fontSize: 15,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            tiene
                ? descripcion!.trim()
                : 'Todavía no cargaste una descripción. Es lo que ven tus '
                    'alumnos en el perfil del estudio.',
            style: TextStyle(
              color: tiene ? const Color(0xFF4A4A4A) : const Color(0xFF8F877F),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: guardando ? null : onEdit,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(guardando
                  ? 'Guardando…'
                  : tiene
                      ? 'Editar descripción'
                      : 'Agregar descripción'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CierreRow extends StatelessWidget {
  final String label;
  final String value;

  const _CierreRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF8F877F), fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: AppColors.black,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
}

/// Stepper en horas. Va de 0 a 48 hs: cubre desde "sin restricción" hasta
/// dos días, que es el rango real de un estudio.
class _HorasStepper extends StatelessWidget {
  final String label;
  final String helper;
  final int value;
  final ValueChanged<int> onChanged;

  const _HorasStepper({
    required this.label,
    required this.helper,
    required this.value,
    required this.onChanged,
    required this.maxHoras,
  });

  /// Tope de horas. Cada ventana tiene el suyo: la de cancelación no puede
  /// pasar de 12 hs (política de Aura, el estudio solo puede bajarla), la de
  /// reservas sí admite más margen.
  final int maxHoras;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.black,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              onPressed: value > 0 ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove_circle_outline_rounded),
              color: AppColors.primary,
            ),
            Expanded(
              child: Text(
                value == 0 ? 'Sin límite' : '$value h',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed:
                  value < maxHoras ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add_circle_outline_rounded),
              color: AppColors.primary,
            ),
          ],
        ),
        Text(
          helper,
          style: const TextStyle(color: Color(0xFF8F877F), fontSize: 12),
        ),
      ],
    );
  }
}

/// FIX 4 — Sección colapsada para las acciones irreversibles.
class _OpcionesAvanzadas extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  const _OpcionesAvanzadas({
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDE7E1)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 16,
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Opciones avanzadas',
                      style: TextStyle(
                        color: Color(0xFF8F877F),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(
                      Icons.expand_more_rounded,
                      color: Color(0xFF8F877F),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1, color: Color(0xFFEDE7E1)),
            ...children,
          ],
        ],
      ),
    );
  }
}

class _AccionPeligrosa extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detalle;
  final VoidCallback onTap;

  const _AccionPeligrosa({
    required this.icon,
    required this.label,
    required this.detalle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 6,
        ),
        leading: Icon(icon, color: AppColors.error),
        title: Text(
          label,
          style: const TextStyle(
            color: AppColors.error,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          detalle,
          style: const TextStyle(color: Color(0xFF8F877F), fontSize: 12),
        ),
      );
}
