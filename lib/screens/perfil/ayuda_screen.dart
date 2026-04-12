import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class AyudaScreen extends StatelessWidget {
  const AyudaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Ayuda')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _InfoCard(
            title: 'Cómo reservar',
            body:
                'Explorá estudios, elegí una clase y confirmá tu reserva desde la ficha. Si no tenés créditos suficientes, Aura te va a mostrar opciones para cargar más o cambiar tu plan.',
          ),
          _InfoCard(
            title: 'Cambios y cancelaciones',
            body:
                'Desde Mis reservas podés revisar tus próximas experiencias y abrir cada ticket. Si un estudio modifica su disponibilidad, vas a verlo reflejado ahí.',
          ),
          _InfoCard(
            title: 'Planes y créditos',
            body:
                'Tus créditos y tu plan activo aparecen tanto en Home como en Perfil. Las compras de prueba pueden seguir marcadas como simuladas hasta cerrar la integración final de pagos.',
          ),
          _InfoCard(
            title: 'Contacto',
            body:
                'Para soporte general del MVP, podés centralizar consultas en el canal de ayuda de Aura o redirigir al WhatsApp/Instagram del estudio desde cada ficha.',
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String body;

  const _InfoCard({required this.title, required this.body});

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
            style: const TextStyle(
              color: AppColors.grey,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
