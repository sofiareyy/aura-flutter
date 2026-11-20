import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/aura_tokens.dart';
import '../services/analytics/embudo.dart';

/// "Explorar sin cuenta" (20/11/2026): botón con borde y sin relleno, del
/// mismo alto y ancho que el botón principal de la pantalla, justo debajo.
///
/// Va en la landing (arriba y en el cierre), en Registrarse y en Ingresar,
/// que es donde la gente se traba. Antes (16/11) era un link de texto
/// subrayado y sólo estaba en la landing.
///
/// [boton] es el parámetro `boton` de `clic_explorar_sin_cuenta` en GA4:
/// 'principal', 'cierre', 'registro' o 'ingreso'.
class BotonExplorarSinCuenta extends StatelessWidget {
  final String boton;

  /// El alto del botón principal de la pantalla: 54 en la landing, 48 en
  /// Registrarse e Ingresar.
  final double alto;

  const BotonExplorarSinCuenta({
    super.key,
    required this.boton,
    this.alto = 54,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: alto,
      child: OutlinedButton(
        onPressed: () {
          Embudo.clicExplorarSinCuenta(boton);
          context.go('/explorar');
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.white,
          backgroundColor: Colors.transparent,
          side: const BorderSide(color: AppColors.white, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AuraRadio.boton),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: const Text('Explorar sin cuenta'),
      ),
    );
  }
}
