// El contraste de los colores de texto de Aura, con la fórmula estándar (WCAG).
//
// Por qué existe este test: los grises de las tarjetas de clase habían quedado
// tan claros que no se leían al sol —la categoría daba 1,5:1 sobre la crema, la
// fecha 2,2:1 y la dirección 2,5:1, contra un mínimo de 4,5:1—, y es
// exactamente la información que decide una reserva. Un color se afloja de a
// poco y nadie lo nota hasta que ya pasó; acá se nota.
//
// También fija la decisión de marca del botón: NEGRO sobre naranja, no blanco.
import 'dart:io';
import 'dart:math' as math;

import 'package:aura_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Luminancia relativa, tal cual la define WCAG 2.
double _luminancia(Color c) {
  double canal(double v) {
    final s = v / 255.0;
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * canal(c.r * 255) +
      0.7152 * canal(c.g * 255) +
      0.0722 * canal(c.b * 255);
}

/// Contraste entre dos colores: de 1:1 (iguales) a 21:1 (negro sobre blanco).
double contraste(Color a, Color b) {
  final la = _luminancia(a);
  final lb = _luminancia(b);
  final alto = math.max(la, lb);
  final bajo = math.min(la, lb);
  return (alto + 0.05) / (bajo + 0.05);
}

/// El mínimo de WCAG AA para texto normal. El de texto grande es 3.0.
const double minimoTextoNormal = 4.5;

void main() {
  // El tema NO se construye acá: `GoogleFonts` intenta descargar la fuente y
  // el test fallaría por la red, no por el diseño. Lo que depende del tema se
  // verifica leyendo el archivo, que es igual de estricto y no necesita
  // motor de fuentes.
  final fuenteDelTema =
      File('lib/core/theme/app_theme.dart').readAsStringSync();

  // Las dos superficies sobre las que vive el texto en Aura.
  const superficies = {
    'la crema del fondo': AppColors.background,
    'el blanco de las tarjetas': AppColors.cardBackground,
  };

  group('el texto secundario se lee', () {
    test('textoSecundario pasa sobre las dos superficies', () {
      superficies.forEach((donde, fondo) {
        final c = contraste(AppColors.textoSecundario, fondo);
        expect(c, greaterThanOrEqualTo(minimoTextoNormal),
            reason: 'sobre $donde da ${c.toStringAsFixed(2)}:1');
      });
    });

    test('textoSuave, el escalón más claro, TAMBIÉN pasa', () {
      superficies.forEach((donde, fondo) {
        final c = contraste(AppColors.textoSuave, fondo);
        expect(c, greaterThanOrEqualTo(minimoTextoNormal),
            reason: 'sobre $donde da ${c.toStringAsFixed(2)}:1');
      });
    });

    test('y mantienen la jerarquía: el suave es más claro que el secundario',
        () {
      expect(
        contraste(AppColors.textoSuave, AppColors.background),
        lessThan(contraste(AppColors.textoSecundario, AppColors.background)),
      );
    });
  });

  group('los que NO alcanzan, para no volver a usarlos como texto', () {
    test('los tres grises viejos de las tarjetas quedaban muy por debajo', () {
      const viejos = {
        'categoría': Color(0xFFD0C6BD),
        'fecha': Color(0xFFB2A89F),
        'dirección': Color(0xFFA49B94),
      };
      viejos.forEach((que, color) {
        expect(contraste(color, AppColors.background), lessThan(minimoTextoNormal),
            reason: '$que: si esto falla, el gris viejo ya sirve y este test sobra');
      });
    });

    test('grey y mutedText son para íconos y bordes, no para texto', () {
      for (final c in [AppColors.grey, AppColors.mutedText]) {
        expect(contraste(c, AppColors.background), lessThan(minimoTextoNormal));
      }
    });
  });

  group('LA FIRMA DE AURA: negro sobre naranja en los botones', () {
    test('el negro sobre el naranja pasa cómodo', () {
      final c = contraste(AppColors.black, AppColors.primary);
      expect(c, greaterThanOrEqualTo(minimoTextoNormal),
          reason: 'da ${c.toStringAsFixed(2)}:1');
    });

    test('el blanco NO pasaría: por eso el botón es negro y se queda así', () {
      final blanco = contraste(AppColors.white, AppColors.primary);
      final negro = contraste(AppColors.black, AppColors.primary);
      expect(blanco, lessThan(minimoTextoNormal),
          reason: 'blanco da ${blanco.toStringAsFixed(2)}:1');
      expect(negro, greaterThan(blanco));
    });

    test('el tema declara negro sobre naranja, no blanco', () {
      final boton = fuenteDelTema.substring(
        fuenteDelTema.indexOf('elevatedButtonTheme'),
        fuenteDelTema.indexOf('outlinedButtonTheme'),
      );
      expect(boton, contains('backgroundColor: AppColors.primary'));
      expect(boton, contains('foregroundColor: AppColors.black'));
      expect(boton, isNot(contains('foregroundColor: AppColors.white')));
    });
  });

  group('una sola tipografía de marca', () {
    test('el tema NO usa Inter en ningún lado', () {
      expect(fuenteDelTema, isNot(contains('GoogleFonts.inter')),
          reason: 'los textos de cuerpo, inputs y etiquetas usaban Inter');
    });

    test('y todas las tipografías que declara son DM Sans', () {
      final familias = RegExp(r'GoogleFonts\.(\w+)\(')
          .allMatches(fuenteDelTema)
          .map((m) => m.group(1))
          .toSet();
      expect(familias, {'dmSans'},
          reason: 'aparecieron otras familias: $familias');
    });
  });
}
