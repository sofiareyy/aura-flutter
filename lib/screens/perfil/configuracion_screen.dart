import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../providers/app_provider.dart';
import '../../services/auth_service.dart';

import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';
import '../../widgets/eliminar_cuenta_helper.dart';
import '../../widgets/soporte_card.dart';

class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  bool _eliminando = false;
  String? _version;

  @override
  void initState() {
    super.initState();
    _cargarVersion();
  }

  /// Antes decía `Aura v1.0.0` escrito a mano: mentía desde hacía seis
  /// versiones. Ahora sale del paquete, igual que en Mi Perfil.
  Future<void> _cargarVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = 'Aura v${info.version} (${info.buildNumber})');
    } catch (_) {
      // En web PackageInfo puede no resolver: mejor sin versión que con una
      // inventada.
    }
  }

  /// Términos y privacidad viven en la web y son la ÚNICA fuente: así se
  /// actualizan sin sacar un build, y no puede volver a pasar que la copia de
  /// la app diga algo distinto (la vieja seguía hablando de "flujo simulado"
  /// cuando Mercado Pago ya cobraba de verdad).
  Future<void> _abrirWeb(String archivo) async {
    await launchUrl(
      Uri.parse('${AppConstants.auraWebUrl}$archivo'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Configuración'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // "Editar perfil" NO va acá: vive en Mi Perfil, pegado al header,
          // que es donde se lo busca. Antes estaba en las dos pantallas.
          _Section(
            title: 'Cuenta',
            items: [
              _Item(
                icon: Icons.lock_outline,
                label: 'Cambiar contraseña',
                onTap: () => context.push('/perfil/cambiar-contrasena'),
              ),
              _Item(
                icon: Icons.notifications_outlined,
                label: 'Notificaciones',
                onTap: () => context.push('/perfil/notificaciones'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FutureBuilder<bool>(
            future: AdminService().isCurrentUserAdmin(),
            builder: (context, snapshot) {
              if (snapshot.data == true) {
                return Column(
                  children: [
                    _Section(
                      title: 'Admin Aura',
                      items: [
                        _Item(
                          icon: Icons.admin_panel_settings_outlined,
                          label: 'Abrir backoffice',
                          onTap: () => context.push('/admin/dashboard'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Ayuda',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: AppColors.grey),
            ),
          ),
          const SoporteCard(),
          const SizedBox(height: 16),
          // "Preguntas frecuentes" (antes "Ayuda") sale de acá: no es legal.
          _Section(
            items: [
              _Item(
                icon: Icons.help_outline_rounded,
                label: 'Preguntas frecuentes',
                onTap: () => context.push('/perfil/ayuda'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Legal',
            items: [
              _Item(
                icon: Icons.article_outlined,
                label: 'Términos y condiciones',
                onTap: () => _abrirWeb('terms.html'),
              ),
              _Item(
                icon: Icons.privacy_tip_outlined,
                label: 'Política de privacidad',
                onTap: () => _abrirWeb('privacy.html'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Cerrar sesión es una acción NORMAL y reversible: se ve como
          // cualquier otra fila. Lo irreversible vive mucho más abajo.
          _Section(
            items: [
              _Item(
                icon: Icons.logout_rounded,
                label: 'Cerrar sesión',
                onTap: _cerrarSesion,
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_version != null)
            Center(
              child: Text(
                _version!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.grey),
              ),
            ),
          // ── ZONA DE PELIGRO ────────────────────────────────────────────
          // Requisito Apple App Store (5.1.1(v)): el usuario tiene que poder
          // eliminar su cuenta y datos desde dentro de la app.
          //
          // Va al final de todo y con MUCHO aire por encima, para que no
          // quede al alcance del pulgar de alguien que venía a cerrar sesión.
          // Además pide escribir ELIMINAR para habilitar el botón.
          const SizedBox(height: 64),
          _DangerSection(
            child: _DangerItem(
              icon: Icons.delete_forever_rounded,
              label: 'Eliminar mi cuenta',
              loading: _eliminando,
              onTap: _eliminando ? null : _abrirDialogoEliminar,
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /// Baja desde Mi Perfil: acá queda con el resto de lo que se usa poco, y
  /// separada por 64 px de "Eliminar mi cuenta" para que no se confundan.
  Future<void> _cerrarSesion() async {
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
            child: const Text('Salir',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await AuthService().signOut();
    if (!mounted) return;
    context.read<AppProvider>().limpiarUsuario();
    context.go('/login');
  }

  Future<void> _abrirDialogoEliminar() async {
    setState(() => _eliminando = true);
    await EliminarCuentaFlow.ejecutar(context);
    if (mounted) setState(() => _eliminando = false);
  }
}

class _Section extends StatelessWidget {
  /// null = sin encabezado (el bloque suelto de "Cerrar sesión").
  final String? title;
  final List<Widget> items;

  const _Section({this.title, required this.items});

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

class _Item extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Item({
    required this.icon,
    required this.label,
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
        child: Icon(icon, color: AppColors.primary, size: 18),
      ),
      title: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
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

class _DangerSection extends StatelessWidget {
  final Widget child;
  const _DangerSection({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: child,
    );
  }
}

class _DangerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback? onTap;

  const _DangerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.error, size: 18),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.error.withValues(alpha: onTap == null ? 0.4 : 1),
        ),
      ),
      trailing: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.error,
              ),
            )
          : Icon(
              Icons.chevron_right_rounded,
              color: AppColors.error.withValues(alpha: 0.6),
              size: 20,
            ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}
