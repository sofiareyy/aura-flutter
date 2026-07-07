import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_theme.dart';

/// Abre el Instagram de un organizador (acepta @handle o URL completa).
Future<void> abrirInstagram(String value) async {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return;
  final url = (trimmed.startsWith('http://') || trimmed.startsWith('https://'))
      ? trimmed
      : 'https://instagram.com/${trimmed.replaceFirst('@', '')}';
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Fila de organizadores con @handles clickeables (para workshops/eventos).
/// Cada @ abre el Instagram correspondiente.
class OrganizadoresLinks extends StatelessWidget {
  final List organizadores;
  final double fontSize;
  const OrganizadoresLinks({
    super.key,
    required this.organizadores,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    for (final o in organizadores) {
      final m = o as Map?;
      final ig = (m?['instagram'] ?? '').toString().replaceFirst('@', '').trim();
      final nombre = (m?['nombre'] ?? '').toString().trim();
      final label = ig.isNotEmpty ? '@$ig' : nombre;
      if (label.isEmpty) continue;
      chips.add(
        GestureDetector(
          onTap: ig.isEmpty ? null : () => abrirInstagram(ig),
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.primary,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 4, children: chips);
  }
}
