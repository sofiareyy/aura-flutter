import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';

class ConfiguracionScreen extends StatelessWidget {
  const ConfiguracionScreen({super.key});

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
          _Section(
            title: 'Soporte',
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
