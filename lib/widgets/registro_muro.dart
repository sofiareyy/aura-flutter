import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';

/// Por qué se le pide cuenta al invitado. Define el texto del muro.
enum MuroMotivo { reservar, listaEspera, favorito, reservas, perfil }

/// Muro de registro para el **modo visita**.
///
/// Es un pop-up CERRABLE, no una pantalla. La diferencia importa: antes esto
/// era `context.go('/register')`, y `go` **reemplaza** la ubicación — el
/// invitado quedaba sin nada a lo que volver y terminaba en el onboarding
/// eligiendo "estudio o usuario". Acá no se navega: se abre un diálogo encima
/// y al cerrarlo el invitado sigue exactamente donde estaba, con su scroll.
///
/// Se dispara SOLO ante una **acción** que requiere cuenta (reservar, guardar
/// un favorito) o al tocar una **pestaña personal** (Reservas, Perfil).
/// Navegar por el browse —Explorar, Mapa, detalle de clase, detalle de
/// estudio, Home— es libre y no debe mostrar ningún muro.
///
/// No es una frontera de seguridad: el gate real sigue siendo el `redirect`
/// de `app_router.dart`, que manda a /login si el invitado escribe una ruta
/// privada a mano. Esto es comodidad de UI.
class RegistroMuro extends StatelessWidget {
  final MuroMotivo motivo;

  const RegistroMuro({super.key, required this.motivo});

  static Future<void> mostrar(
    BuildContext context, {
    required MuroMotivo motivo,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => RegistroMuro(motivo: motivo),
    );
  }

  _MuroTexto get _texto {
    switch (motivo) {
      case MuroMotivo.reservar:
        return const _MuroTexto(
          icono: Icons.event_available_rounded,
          titulo: 'Registrate para reservar',
          detalle: 'Creá tu cuenta gratis y reservá tu primera clase.',
        );
      case MuroMotivo.listaEspera:
        return const _MuroTexto(
          icono: Icons.hourglass_bottom_rounded,
          titulo: 'Registrate para anotarte',
          detalle: 'Te avisamos apenas se libere un lugar en esta clase.',
        );
      case MuroMotivo.favorito:
        return const _MuroTexto(
          icono: Icons.favorite_rounded,
          titulo: 'Registrate para guardar favoritos',
          detalle: 'Tené a mano los estudios que más te gustan.',
        );
      case MuroMotivo.reservas:
        return const _MuroTexto(
          icono: Icons.work_outline_rounded,
          titulo: 'Acá van a estar tus reservas',
          detalle: 'Creá tu cuenta para reservar y seguir tus clases.',
        );
      case MuroMotivo.perfil:
        return const _MuroTexto(
          icono: Icons.person_outline_rounded,
          titulo: 'Creá tu cuenta',
          detalle: 'Tus créditos, tus reservas y tu perfil en un solo lugar.',
        );
    }
  }

  /// `push` y no `go`: si desde el registro tocan atrás, vuelven a donde
  /// estaban en vez de caer en el onboarding.
  void _ir(BuildContext context, String ruta) {
    Navigator.of(context).pop();
    context.push(ruta);
  }

  @override
  Widget build(BuildContext context) {
    final texto = _texto;

    return Dialog(
      backgroundColor: AppColors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cruz para cerrar: la salida explícita que faltaba.
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: AppColors.grey),
                  tooltip: 'Seguir explorando',
                ),
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(texto.icono, color: AppColors.primary, size: 26),
              ),
              const SizedBox(height: 16),
              Text(
                texto.titulo,
                style: const TextStyle(
                  color: AppColors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                texto.detalle,
                style: const TextStyle(
                  color: AppColors.grey,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => _ir(context, '/register'),
                  child: const Text('Crear cuenta'),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  onPressed: () => _ir(context, '/login'),
                  child: const Text(
                    'Ya tengo cuenta',
                    style: TextStyle(
                      color: AppColors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MuroTexto {
  final IconData icono;
  final String titulo;
  final String detalle;

  const _MuroTexto({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });
}
