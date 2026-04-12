import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class PrivacidadScreen extends StatelessWidget {
  const PrivacidadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Políticas de privacidad')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _PrivacyBlock(
            title: 'Qué datos usamos',
            body:
                'Aura utiliza datos básicos de tu cuenta, historial de reservas, créditos, favoritos y preferencias para poder mostrarte tu experiencia personalizada dentro de la app.',
          ),
          _PrivacyBlock(
            title: 'Para qué los usamos',
            body:
                'Los datos se usan para gestionar tu perfil, mantener tus reservas, mostrar disponibilidad y mejorar la operación general del producto. No se comparten públicamente dentro de la app.',
          ),
          _PrivacyBlock(
            title: 'Estudios y contacto',
            body:
                'Cuando reservás una experiencia, el estudio puede recibir la información necesaria para prestar el servicio. Los accesos de contacto del estudio aparecen dentro de la app para facilitar esa comunicación.',
          ),
          _PrivacyBlock(
            title: 'Tus controles',
            body:
                'Podés actualizar tus datos básicos, cambiar tu contraseña, ajustar notificaciones y revisar tus créditos desde Perfil. Si más adelante sumamos carga directa de fotos, se hará sobre infraestructura segura dedicada.',
          ),
        ],
      ),
    );
  }
}

class _PrivacyBlock extends StatelessWidget {
  final String title;
  final String body;

  const _PrivacyBlock({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(color: AppColors.grey, height: 1.5),
          ),
        ],
      ),
    );
  }
}
