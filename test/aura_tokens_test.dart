// El sistema de diseño: que los tokens existan, que los dos lados de la app
// usen LOS MISMOS, y que las siluetas de carga se dibujen sin romper nada.
//
// Contexto: hasta el 4/9/2026 el lado de la alumna no tenía sistema (6
// márgenes de página, 14 radios, 19 tamaños de letra, 8 sombras distintas) y
// el del estudio sí. Estos tests fijan que ahora sea uno solo.
import 'package:aura_app/core/theme/aura_gestion_design.dart';
import 'package:aura_app/core/theme/aura_tokens.dart';
import 'package:aura_app/widgets/aura_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('un solo sistema para los dos lados', () {
    test('el del estudio delega en los tokens compartidos', () {
      expect(AuraGestionDesign.horizontalPadding, AuraEspacio.margen);
      expect(AuraGestionDesign.sectionSpacing, AuraEspacio.seccion);
      expect(AuraGestionDesign.cardRadius, AuraRadio.tarjeta);
      expect(AuraGestionDesign.buttonRadius, AuraRadio.boton);
      expect(AuraGestionDesign.softShadow, AuraSombra.suave);
    });

    test('el espaciado es una escala de 4', () {
      for (final v in [
        AuraEspacio.xs, AuraEspacio.s, AuraEspacio.m, AuraEspacio.l,
        AuraEspacio.margen, AuraEspacio.xl, AuraEspacio.seccion,
        AuraEspacio.xxl,
      ]) {
        expect(v % 4, 0, reason: '$v no es múltiplo de 4');
      }
    });

    test('los radios son cuatro, no catorce', () {
      final radios = {
        AuraRadio.chip, AuraRadio.boton, AuraRadio.tarjeta, AuraRadio.pastilla,
      };
      expect(radios.length, 4);
      expect(AuraRadio.chip, lessThan(AuraRadio.boton));
      expect(AuraRadio.boton, lessThan(AuraRadio.tarjeta));
    });

    test('la escala tipográfica tiene saltos de verdad', () {
      final escala = [
        AuraTipo.etiqueta, AuraTipo.secundario, AuraTipo.cuerpo,
        AuraTipo.titulo, AuraTipo.display,
      ];
      // Ordenada y sin escalones de 1 px (que era el problema: 11,12,13,14…).
      for (var i = 1; i < escala.length; i++) {
        expect(escala[i], greaterThan(escala[i - 1]));
        expect(escala[i] - escala[i - 1], greaterThanOrEqualTo(2),
            reason: 'entre ${escala[i - 1]} y ${escala[i]} casi no hay salto');
      }
    });
  });

  group('las siluetas de carga', () {
    testWidgets('una tarjeta se dibuja y no desborda', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: AuraSkeletonTarjetaVidriera(),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(AuraSkeleton), findsWidgets);
    });

    testWidgets('el carrusel entra en su alto', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: AuraSkeletonCarrusel(alto: 340, altoFoto: 180),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a lo ancho de la pantalla tampoco desborda', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.symmetric(horizontal: AuraEspacio.margen),
            child: AuraSkeletonTarjetaVidriera(
              ancho: double.infinity,
              altoFoto: 160,
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('late: la animación corre y se limpia al salir', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AuraSkeleton(height: 20, width: 100)),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      expect(tester.takeException(), isNull);
    });
  });
}
