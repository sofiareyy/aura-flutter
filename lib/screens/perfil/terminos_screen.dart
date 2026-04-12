import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class TerminosScreen extends StatelessWidget {
  const TerminosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Términos y condiciones')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _TextSection(
            title: 'Uso de Aura',
            body:
                'Aura funciona como una plataforma para descubrir experiencias, administrar créditos y reservar actividades con estudios asociados. El uso de la app implica aceptar estas reglas básicas mientras el producto evoluciona.',
          ),
          _TextSection(
            title: 'Reservas y disponibilidad',
            body:
                'Las clases, cupos, horarios y condiciones pueden variar según cada estudio. Aura intenta reflejar esa información en tiempo real, pero cada experiencia depende de la disponibilidad final informada por el estudio.',
          ),
          _TextSection(
            title: 'Planes y créditos',
            body:
                'Los planes mensuales y los packs de créditos pueden cambiar de precio, beneficios o equivalencias. Mientras la pasarela real siga en integración, algunas compras pueden mostrarse como demo o flujo simulado.',
          ),
          _TextSection(
            title: 'Conducta del usuario',
            body:
                'Esperamos un uso responsable de la cuenta, de los referidos y de los beneficios promocionales. Aura puede limitar beneficios o suspender cuentas ante usos abusivos, automatizados o fraudulentos.',
          ),
        ],
      ),
    );
  }
}

class _TextSection extends StatelessWidget {
  final String title;
  final String body;

  const _TextSection({required this.title, required this.body});

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
