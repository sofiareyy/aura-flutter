import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';

/// Pantalla bloqueante del force-update. Se llega acá solo cuando
/// [VersionGate.hayQueActualizar] dio `true` (build por debajo del mínimo).
///
/// Es un callejón sin salida a propósito: `PopScope(canPop: false)` bloquea el
/// botón de atrás y no hay ninguna otra navegación. La única acción es ir a la
/// tienda. Al reabrir la app, el chequeo del splash vuelve a correr; si ya
/// actualizó, sigue de largo.
class ActualizarScreen extends StatelessWidget {
  const ActualizarScreen({super.key});

  Future<void> _abrirTienda(BuildContext context) async {
    final url = Platform.isIOS
        ? AppConstants.appStoreUrl
        : AppConstants.playStoreUrl;
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir la tienda. Buscá "Aura Pass".'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir la tienda. Buscá "Aura Pass".'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.blackDeep,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.system_update_alt_rounded,
                      color: AppColors.blackDeep,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Actualizá para seguir usando Aura',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFF5F0E8),
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Esta versión ya no está disponible. Actualizá a la última '
                    'para reservar tus clases sin problemas.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF8A837D),
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _abrirTienda(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.blackDeep,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Actualizar',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
