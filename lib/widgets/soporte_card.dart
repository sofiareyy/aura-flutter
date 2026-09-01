import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_theme.dart';
import '../providers/app_provider.dart';

const String kSoporteEmail = 'aura.hola.app@gmail.com';
const String kInstagramHandle = 'somosaura.app';
const String kLinkedinUrl = 'https://ar.linkedin.com/company/aura-aurapass';

/// Card oscura con dos filas: contacto por email y por Instagram.
/// Pensada para reutilizarse en ConfiguracionScreen, AyudaScreen y donde
/// haga falta darle salida al usuario para hablar con soporte.
class SoporteCard extends StatelessWidget {
  const SoporteCard({super.key});

  Future<void> _abrirEmail(BuildContext context) async {
    final nombre = context.read<AppProvider>().usuario?.nombre.trim() ?? '';
    final subject = Uri.encodeComponent(
      'Consulta Aura Pass - ${nombre.isEmpty ? 'usuario' : nombre}',
    );
    final uri = Uri.parse('mailto:$kSoporteEmail?subject=$subject');
    await launchUrl(uri);
  }

  Future<void> _abrirInstagram() async {
    final uri = Uri.parse('https://instagram.com/$kInstagramHandle');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _abrirLinkedin() async {
    await launchUrl(Uri.parse(kLinkedinUrl),
        mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _SoporteRow(
            icon: Icons.email_outlined,
            title: 'Contactar soporte',
            subtitle: kSoporteEmail,
            onTap: () => _abrirEmail(context),
          ),
          const Divider(
            height: 1,
            thickness: 1,
            color: Color(0xFF252525),
          ),
          _SoporteRow(
            icon: Icons.photo_camera_outlined,
            title: 'Seguinos en Instagram',
            subtitle: '@$kInstagramHandle',
            onTap: _abrirInstagram,
          ),
          const Divider(
            height: 1,
            thickness: 1,
            color: Color(0xFF252525),
          ),
          _SoporteRow(
            icon: Icons.work_outline_rounded,
            title: 'Seguinos en LinkedIn',
            subtitle: 'Aura Pass',
            onTap: _abrirLinkedin,
          ),
        ],
      ),
    );
  }
}

class _SoporteRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SoporteRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFFF5F0E8),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF8F877F),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF6E6761),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Texto chico con call-to-action para escribirle a soporte. Pensado para
/// pantallas de error donde queremos un fallback de contacto.
class SoporteInlineHint extends StatelessWidget {
  const SoporteInlineHint({super.key});

  Future<void> _abrir(BuildContext context) async {
    final nombre = context.read<AppProvider>().usuario?.nombre.trim() ?? '';
    final subject = Uri.encodeComponent(
      'Consulta Aura Pass - ${nombre.isEmpty ? 'usuario' : nombre}',
    );
    final uri = Uri.parse('mailto:$kSoporteEmail?subject=$subject');
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _abrir(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text.rich(
          TextSpan(
            style: const TextStyle(
              color: AppColors.grey,
              fontSize: 12,
              height: 1.4,
            ),
            children: const [
              TextSpan(text: '¿Tuviste un problema? Escribinos a '),
              TextSpan(
                text: kSoporteEmail,
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
