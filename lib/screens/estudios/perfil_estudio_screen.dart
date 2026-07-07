import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../services/estudio_admin_service.dart';
import '../../services/media_upload_service.dart';
import '../../widgets/eliminar_cuenta_helper.dart';

class PerfilEstudioScreen extends StatefulWidget {
  const PerfilEstudioScreen({super.key});

  @override
  State<PerfilEstudioScreen> createState() => _PerfilEstudioScreenState();
}

class _PerfilEstudioScreenState extends State<PerfilEstudioScreen> {
  final _mediaUploadService = MediaUploadService();
  final _adminService = EstudioAdminService();
  Map<String, dynamic>? _estudio;
  List<Map<String, dynamic>> _admins = [];
  List<Map<String, dynamic>> _profes = [];
  bool _loading = true;
  bool _uploadingPhoto = false;
  bool _uploadingGaleria = false;
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

      final estudio = await Supabase.instance.client
          .from('estudios')
          .select()
          .eq('id', estudioId)
          .maybeSingle();

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
      await Supabase.instance.client.from('estudios').update({
        'titular': titular.isEmpty ? null : titular,
        'banco': banco.isEmpty ? null : banco,
        'alias': alias.isEmpty ? null : alias,
        'cbu': cbu.isEmpty ? null : cbu,
      }).eq('id', _estudio!['id']);

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

    await Supabase.instance.client.auth.signOut();
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
                          if ((_estudio?['categoria']?.toString() ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(9999),
                              ),
                              child: Text(
                                _estudio?['categoria']?.toString() ?? '',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
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
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => context.go('/home'),
                        icon: const Icon(Icons.home_outlined),
                        label: const Text('Cambiar al lado usuario'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _dejarDeAdministrar,
                        icon: const Icon(
                          Icons.exit_to_app_rounded,
                          color: AppColors.error,
                        ),
                        label: const Text(
                          'Dejar de administrar este estudio',
                          style: TextStyle(color: AppColors.error),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.error),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
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
                  const SizedBox(height: 12),
                  // Eliminar cuenta — requisito Apple App Store 5.1.1.
                  // Forzamos contextoEstudio=true porque desde el panel
                  // sabemos que el usuario administra al menos un estudio.
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          EliminarCuentaFlow.ejecutar(context,
                              contextoEstudio: true),
                      icon: const Icon(
                        Icons.delete_forever_rounded,
                        color: AppColors.error,
                      ),
                      label: const Text(
                        'Eliminar mi cuenta',
                        style: TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: AppColors.error.withValues(alpha: 0.4),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
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
