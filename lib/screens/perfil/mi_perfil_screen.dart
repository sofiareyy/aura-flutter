import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../models/estudio.dart';
import '../../models/usuario.dart';
import '../../providers/app_provider.dart';
import '../../services/media_upload_service.dart';
import '../../services/auth_service.dart';
import '../../services/estudio_admin_service.dart';
import '../../services/favoritos_service.dart';
import '../../services/referidos_service.dart';
import '../../services/reservas_service.dart';
import '../../services/usuarios_service.dart';

class MiPerfilScreen extends StatefulWidget {
  const MiPerfilScreen({super.key});

  @override
  State<MiPerfilScreen> createState() => _MiPerfilScreenState();
}

class _MiPerfilScreenState extends State<MiPerfilScreen> {
  final _authService = AuthService();
  final _favoritosService = FavoritosService();
  final _usuariosService = UsuariosService();
  final _estudioAdminService = EstudioAdminService();
  final _reservasService = ReservasService();

  bool _loadingFavoritos = true;
  bool _uploadingAvatar = false;
  int _clasesTomadas = 0;
  List<Estudio> _favoritos = const [];
  List<Map<String, dynamic>> _misEstudios = const [];
  String? _appVersion;
  final _mediaUploadService = MediaUploadService();

  bool _editandoNombre = false;
  bool _guardandoNombre = false;
  final _nombreController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarTodo();
    _cargarVersion();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    super.dispose();
  }

  /// Canjear una gift card por código. Mismo RPC atómico que Mis Créditos
  /// (canjear_regalo): no se puede canjear dos veces y acredita al ledger.
  Future<void> _canjearRegalo() async {
    final ctrl = TextEditingController();
    var enviando = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Canjear regalo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ingresá el código de tu gift card.',
                style: TextStyle(color: AppColors.grey, fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'GIFT-XXXXXXXX',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: enviando ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar',
                  style: TextStyle(color: AppColors.grey)),
            ),
            TextButton(
              onPressed: enviando
                  ? null
                  : () async {
                      final code = ctrl.text.trim();
                      if (code.isEmpty) return;
                      setD(() => enviando = true);
                      try {
                        final creditos =
                            await ReferidosService().canjearRegalo(code);
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                        if (!mounted) return;
                        await context.read<AppProvider>().refrescarUsuario();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                Text('🎁 ¡Canjeaste $creditos créditos!'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      } catch (e) {
                        setD(() => enviando = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(e
                                  .toString()
                                  .replaceFirst('Exception: ', '')),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      }
                    },
              child: const Text('Canjear',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cargarVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = 'v${info.version} (${info.buildNumber})');
    } catch (_) {}
  }

  Future<void> _cargarTodo() async {
    final provider = context.read<AppProvider>();
    await provider.cargarUsuario();
    final uid = provider.userId;
    if (uid.isNotEmpty) {
      _misEstudios = await _estudioAdminService.listMyStudios();
    } else {
      _misEstudios = const [];
    }
    await _cargarFavoritos();
    _clasesTomadas =
        await _reservasService.contarClasesTomadas(uid.isEmpty ? null : uid);
    if (mounted) setState(() {});
  }

  Future<void> _entrarAEstudio(int estudioId) async {
    final activo = _misEstudios.any(
      (e) => e['is_active'] == true && (e['estudio_id'] as num?)?.toInt() == estudioId,
    );
    if (!activo) {
      final ok = await _estudioAdminService.setActiveEstudio(estudioId);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo cambiar de estudio.')),
        );
        return;
      }
      // set_active_estudio espeja usuarios.rol al del estudio activo. Sin
      // refrescar, la UI sigue con el rol viejo cacheado (p.ej. abría el panel
      // de profe al entrar a un estudio donde sos admin).
      await context.read<AppProvider>().refrescarUsuario();
      if (!mounted) return;
    }
    if (!mounted) return;
    context.go('/estudio/dashboard');
  }

  Future<void> _cargarFavoritos() async {
    final userId = context.read<AppProvider>().userId;
    if (userId.isEmpty) return;
    final favoritos = await _favoritosService.getFavoritos(userId);
    if (!mounted) return;
    setState(() {
      _favoritos = favoritos;
      _loadingFavoritos = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          final usuario = provider.usuario;
          return SafeArea(
            child: RefreshIndicator(
              onRefresh: _cargarTodo,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Mi perfil',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: () => context.push('/configuracion'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildProfileHeader(usuario),
                  const SizedBox(height: 16),
                  // El progreso va ARRIBA (2/9/2026): es lo motivador, lo
                  // primero que se quiere ver al entrar. Antes estaba
                  // enterrado abajo, después de siete filas de menú.
                  _ProgresoCard(clasesTomadas: _clasesTomadas),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _StatBox(
                        value: '${usuario?.creditos ?? 0}',
                        label: 'Créditos',
                        icon: Icons.bolt_rounded,
                      ),
                      const SizedBox(width: 10),
                      _StatBox(
                        value: (usuario?.plan?.isNotEmpty == true)
                            ? usuario!.plan!
                            : 'Sin plan',
                        valueColor: (usuario?.plan?.isNotEmpty == true)
                            ? AppColors.primary
                            : AppColors.grey,
                        label: 'Plan',
                        icon: Icons.workspace_premium_rounded,
                      ),
                      const SizedBox(width: 10),
                      _StatBox(
                        value: usuario?.creditosVencimiento != null
                            ? DateFormat('d MMM', 'es')
                                .format(usuario!.creditosVencimiento!)
                            : '—',
                        valueColor: usuario?.creditosVencimiento != null
                            ? AppColors.black
                            : AppColors.grey,
                        label: 'Vence',
                        icon: Icons.hourglass_bottom_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_misEstudios.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _misEstudios.length == 1
                                ? 'Esta cuenta también administra un estudio.'
                                : 'Esta cuenta administra ${_misEstudios.length} estudios.',
                            style: const TextStyle(
                              color: AppColors.black,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ..._misEstudios.map((e) {
                            final id = (e['estudio_id'] as num?)?.toInt();
                            final nombre = e['nombre']?.toString() ?? 'Sin nombre';
                            final esActivo = e['is_active'] == true;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                onTap: id == null ? null : () => _entrarAEstudio(id),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: esActivo
                                        ? AppColors.primaryLight
                                        : const Color(0xFFF7F3EE),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: AppColors.white,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.storefront_outlined,
                                          color: AppColors.primary,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              nombre,
                                              style: const TextStyle(
                                                color: AppColors.black,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                            if (esActivo)
                                              const Text(
                                                'Activo',
                                                style: TextStyle(
                                                  color: AppColors.primary,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        color: AppColors.primary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Editar perfil vive SOLO acá, pegado a la identidad, que
                  // es donde se lo busca. Salió de Configuración (estaba en
                  // las dos pantallas).
                  _MenuSection(
                    items: [
                      _MenuItem(
                        icon: Icons.edit_outlined,
                        label: 'Editar perfil',
                        subtitle: 'Nombre, foto y datos básicos',
                        onTap: () => context.push('/perfil/editar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Toda la plata en un solo bloque: antes estaba repartida
                  // entre los recuadros de arriba, este menú y un botón de
                  // "Cancelar suscripción" que colgaba suelto abajo.
                  _MenuSection(
                    title: 'Créditos y plan',
                    items: [
                      _MenuItem(
                        icon: Icons.bolt_rounded,
                        label: 'Mis créditos',
                        subtitle: '${usuario?.creditos ?? 0} disponibles',
                        onTap: () => context.push('/mis-creditos'),
                      ),
                      _MenuItem(
                        icon: Icons.add_circle_outline_rounded,
                        label: 'Comprar créditos',
                        subtitle: 'Cargá packs cuando quieras',
                        onTap: () => context.push('/comprar-creditos'),
                      ),
                      _MenuItem(
                        icon: Icons.card_giftcard_rounded,
                        label: 'Regalar créditos',
                        subtitle: 'Enviá una gift card a quien quieras',
                        onTap: () =>
                            context.push('/comprar-creditos?tab=gift'),
                      ),
                      _MenuItem(
                        icon: Icons.redeem_rounded,
                        label: 'Canjear regalo',
                        subtitle: 'Tenés un código de gift card',
                        onTap: _canjearRegalo,
                      ),
                      _MenuItem(
                        icon: Icons.workspace_premium_rounded,
                        label: 'Plan mensual',
                        subtitle: usuario?.subscriptionStatus == 'active' && (usuario?.plan ?? '').isNotEmpty
                            ? 'Activo: ${usuario!.plan}'
                            : 'Opcional: suscripción automática',
                        onTap: () => context.push('/cambiar-plan'),
                      ),
                      if (usuario?.subscriptionStatus == 'active' &&
                          (usuario?.plan ?? '').isNotEmpty)
                        _MenuItem(
                          icon: Icons.cancel_outlined,
                          label: 'Cancelar suscripción',
                          color: AppColors.error,
                          onTap: _cancelarSuscripcion,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Mis reservas NO es plata: es tu actividad. Va con
                  // Referidos, que tampoco tenía dónde caer y terminaba en el
                  // cajón "Más" junto a Configuración y Cerrar sesión.
                  _MenuSection(
                    title: 'Mi actividad',
                    items: [
                      _MenuItem(
                        icon: Icons.calendar_today_rounded,
                        label: 'Mis reservas',
                        onTap: () => context.push('/mis-reservas'),
                      ),
                      _MenuItem(
                        icon: Icons.people_outline_rounded,
                        label: 'Referidos',
                        subtitle: 'Compartí tu código y acreditá beneficios',
                        onTap: () => context.push('/referidos'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _FavoritosSection(
                    estudios: _favoritos,
                    loading: _loadingFavoritos,
                  ),
                  const SizedBox(height: 16),
                  if (_appVersion != null)
                    Center(
                      child: Text(
                        'Aura ${_appVersion!}',
                        style: const TextStyle(
                          color: Color(0xFFB0A8A0),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader(Usuario? usuario) {
    final avatarUrl = usuario?.avatarUrl;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: _uploadingAvatar ? null : _seleccionarFotoPerfil,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.primaryLight,
                  backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: _uploadingAvatar
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : (avatarUrl == null || avatarUrl.isEmpty)
                          ? Text(
                              usuario?.nombre.isNotEmpty == true
                                  ? usuario!.nombre[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            )
                          : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _editandoNombre
              ? _buildNombreEditor(usuario)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        usuario?.nombre ?? '',
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        _nombreController.text = usuario?.nombre ?? '';
                        setState(() => _editandoNombre = true);
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
          const SizedBox(height: 4),
          Text(
            usuario?.email ?? '',
            style: const TextStyle(color: AppColors.grey, fontSize: 13),
          ),
          if (usuario?.creditosVencimiento != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                'Créditos vigentes hasta el ${DateFormat('d/M/yy').format(usuario!.creditosVencimiento!)}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNombreEditor(Usuario? usuario) {
    return Column(
      children: [
        TextField(
          controller: _nombreController,
          enabled: !_guardandoNombre,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.words,
          style: Theme.of(context).textTheme.titleMedium,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Tu nombre',
            filled: true,
            fillColor: AppColors.background,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _guardandoNombre
                  ? null
                  : () => setState(() => _editandoNombre = false),
              style: TextButton.styleFrom(foregroundColor: AppColors.grey),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _guardandoNombre ? null : _guardarNombre,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _guardandoNombre
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Text('Guardar'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _guardarNombre() async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<AppProvider>();
    final userId = provider.userId;
    final nuevoNombre = _nombreController.text.trim();

    if (nuevoNombre.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('El nombre no puede estar vacío.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (userId.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Iniciá sesión para editar tu nombre.')),
      );
      return;
    }

    setState(() => _guardandoNombre = true);
    try {
      await _usuariosService.updateUsuario(userId, {'nombre': nuevoNombre});
      await provider.refrescarUsuario();
      if (!mounted) return;
      setState(() {
        _editandoNombre = false;
        _guardandoNombre = false;
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Nombre actualizado'),
          backgroundColor: Color(0xFF2EAA63),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardandoNombre = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              'No se pudo actualizar el nombre: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _seleccionarFotoPerfil() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined,
                    color: AppColors.primary),
                title: const Text('Sacar una foto'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    await _subirFotoPerfil(source);
  }

  Future<void> _subirFotoPerfil(ImageSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<AppProvider>();
    final userId = provider.userId;
    if (userId.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Iniciá sesión para cambiar tu foto.')),
      );
      return;
    }

    setState(() => _uploadingAvatar = true);
    try {
      // Esta pantalla tenía su propia copia del upload: forzaba `.jpg` y
      // `image/jpeg` mientras el service respeta la extensión del archivo, o
      // sea que los dos caminos ya habían divergido. Ahora las dos pantallas
      // de perfil pasan por `MediaUploadService.uploadAvatar`, que además hace
      // el pick (por eso se le pasa `source`: acá se puede elegir cámara).
      final publicUrl = await _mediaUploadService.uploadAvatar(
        userId: userId,
        source: source,
      );
      // null = canceló el selector, no es un error.
      if (publicUrl == null) {
        if (mounted) setState(() => _uploadingAvatar = false);
        return;
      }

      await Supabase.instance.client
          .from('usuarios')
          .update({'avatar_url': publicUrl}).eq('id', userId);

      await provider.refrescarUsuario();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Foto actualizada'),
          backgroundColor: Color(0xFF2EAA63),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              'Error subiendo la foto: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _cancelarSuscripcion() async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<AppProvider>();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar suscripción'),
        content: const Text(
          '¿Estás segura? Vas a perder el acceso a los créditos automáticos al final del período actual.\n\nTus créditos existentes no se eliminan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Mantener plan'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sí, cancelar',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await _usuariosService.cancelarSuscripcion();
      if (!mounted) return;
      await provider.refrescarUsuario();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Suscripción cancelada. Tus créditos actuales siguen disponibles.'),
          backgroundColor: AppColors.blackSoft,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _cerrarSesion(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Querés salir de tu cuenta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Salir',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _authService.signOut();
      if (context.mounted) {
        context.read<AppProvider>().limpiarUsuario();
        context.go('/login');
      }
    }
  }
}

class _FavoritosSection extends StatelessWidget {
  final List<Estudio> estudios;
  final bool loading;

  const _FavoritosSection({
    required this.estudios,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Estudios favoritos',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: AppColors.grey),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              : estudios.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'Todavía no guardaste estudios favoritos. Podés hacerlo desde el detalle de cada estudio.',
                        style: TextStyle(color: AppColors.grey, height: 1.5),
                      ),
                    )
                  : Column(
                      children: estudios.asMap().entries.map((entry) {
                        final estudio = entry.value;
                        final isLast = entry.key == estudios.length - 1;
                        return Column(
                          children: [
                            ListTile(
                              onTap: () => context.push('/estudio/${estudio.id}'),
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primaryLight,
                                child: Text(
                                  estudio.nombre.isEmpty
                                      ? 'E'
                                      : estudio.nombre[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              title: Text(estudio.nombre),
                              subtitle: Text(
                                estudio.barrio?.isNotEmpty == true
                                    ? '${estudio.categoria} · ${estudio.barrio}'
                                    : estudio.categoria,
                              ),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.grey,
                              ),
                            ),
                            if (!isLast) const Divider(height: 1, indent: 72),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color? valueColor;

  const _StatBox({
    required this.value,
    required this.label,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: valueColor ?? AppColors.black,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgresoCard extends StatelessWidget {
  final int clasesTomadas;
  const _ProgresoCard({required this.clasesTomadas});

  static const int _meta = 50;

  @override
  Widget build(BuildContext context) {
    final n = clasesTomadas;
    final progreso = (n / _meta).clamp(0.0, 1.0);
    final alcanzado = n >= _meta;
    final faltan = _meta - n;

    final String mensaje;
    if (n == 0) {
      mensaje = 'Todavía no tomaste clases — ¡reservá la primera! 🧡';
    } else if (alcanzado) {
      mensaje = '¡Ganaste tu 10% off en una experiencia! 🎉';
    } else {
      mensaje =
          'Te faltan $faltan ${faltan == 1 ? 'clase' : 'clases'} para tu 10% off en una experiencia 🎁';
    }

    // Mismo patrón que _MenuSection: título de sección gris ARRIBA + card
    // blanca radius 16, padding 16. Tokens de AppColors, sin valores nuevos.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Tu progreso en Aura',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: AppColors.grey),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('$n',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          height: 1)),
                  const SizedBox(width: 6),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: Text('de $_meta clases',
                        style: TextStyle(
                            color: AppColors.black,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progreso,
                  minHeight: 12,
                  backgroundColor: AppColors.lightGrey,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                mensaje,
                style: const TextStyle(color: AppColors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuSection extends StatelessWidget {
  /// null = sin encabezado (el bloque suelto de "Editar perfil").
  final String? title;
  final List<Widget> items;

  const _MenuSection({this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title!,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: AppColors.grey),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final isLast = entry.key == items.length - 1;
              return Column(
                children: [
                  entry.value,
                  if (!isLast) const Divider(height: 1, indent: 52),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? color;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.subtitle,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color ?? AppColors.primary, size: 18),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: color ?? AppColors.black,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(fontSize: 12, color: AppColors.grey),
            ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.grey,
        size: 20,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}
