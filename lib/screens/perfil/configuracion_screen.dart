import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/soporte_card.dart';

class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  final _authService = AuthService();
  bool _eliminando = false;

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
          _Section(
            title: 'Cuenta',
            items: [
              _Item(
                icon: Icons.person_outline,
                label: 'Editar perfil',
                onTap: () => context.push('/perfil/editar'),
              ),
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
              'Ayuda y soporte',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: AppColors.grey),
            ),
          ),
          const SoporteCard(),
          const SizedBox(height: 16),
          _Section(
            title: 'Información legal',
            items: [
              _Item(
                icon: Icons.help_outline_rounded,
                label: 'Ayuda',
                onTap: () => context.push('/perfil/ayuda'),
              ),
              _Item(
                icon: Icons.privacy_tip_outlined,
                label: 'Políticas de privacidad',
                onTap: () => context.push('/perfil/privacidad'),
              ),
              _Item(
                icon: Icons.article_outlined,
                label: 'Términos y condiciones',
                onTap: () => context.push('/perfil/terminos'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // ── ZONA DE PELIGRO ────────────────────────────────────────────
          // Requisito Apple App Store (5.1.1(v)): el usuario tiene que
          // poder eliminar su cuenta y datos desde dentro de la app.
          _DangerSection(
            child: _DangerItem(
              icon: Icons.delete_forever_rounded,
              label: 'Eliminar mi cuenta',
              loading: _eliminando,
              onTap: _eliminando ? null : _abrirDialogoEliminar,
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'Aura v1.0.0',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirDialogoEliminar() async {
    // Antes de abrir el dialog, vemos si el usuario es admin de algun
    // estudio para mostrar la advertencia extra.
    final esEstudio = await _authService.esAdminDeEstudio();
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          '¿Eliminar tu cuenta?',
          style: TextStyle(
            color: AppColors.black,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Esta acción es permanente. Se eliminarán todos tus datos, '
              'reservas e historial de créditos. No se puede deshacer.',
              style: TextStyle(
                color: AppColors.black,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            if (esEstudio) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1E8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: const Text(
                  'También se eliminarán todas las clases de tu estudio '
                  'y los alumnos que las hayan reservado recibirán sus '
                  'créditos de vuelta.',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: AppColors.grey),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
            ),
            child: const Text(
              'Sí, eliminar mi cuenta',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    await _ejecutarEliminacion();
  }

  Future<void> _ejecutarEliminacion() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _eliminando = true);
    try {
      await _authService.eliminarCuenta();
      if (!mounted) return;
      // Volver al login y mostrar feedback.
      context.go('/login');
      // Damos un frame para que se monte la nueva ruta antes del snackbar.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Tu cuenta fue eliminada correctamente.'),
            backgroundColor: AppColors.blackSoft,
            duration: Duration(seconds: 4),
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _eliminando = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'No pudimos eliminar la cuenta: '
            '${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> items;

  const _Section({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
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
