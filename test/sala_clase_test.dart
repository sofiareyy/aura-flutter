// El salón de una clase (9/9/2026).
//
// El caso que lo pidió: Rock Studios Palermo da spinning Y pilates, y puede
// tener las dos a la misma hora en salones distintos. Medido contra la base,
// dos clases simultáneas en un estudio funcionan sin conflicto (el único índice
// único de `clases` es por grilla+fecha), y el campo `sala` es texto libre.
//
// Lo que se arregló: el detalle de clase mostraba **"Sala 2" inventado** cuando
// el estudio no había cargado ninguno. Con dos clases simultáneas eso manda a
// la alumna a una sala que no existe.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Sin comentarios: el comentario que explica POR QUÉ se sacó el "Sala 2"
  /// puede nombrarlo; lo que no puede quedar es el literal en el código.
  String soloCodigo(String f) => f
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  final detalle = soloCodigo(
    File('lib/screens/clases/detalle_clase_screen.dart').readAsStringSync(),
  );
  final form = soloCodigo(
    File('lib/screens/clases/mis_clases_screen.dart').readAsStringSync(),
  );

  group('nunca se inventa un salón', () {
    test('ya no existe el "Sala 2" de relleno', () {
      expect(detalle.contains("'Sala 2'"), isFalse);
    });

    test('el chip del salón se dibuja SÓLO si el estudio lo cargó', () {
      // La condición tiene que estar antes del chip, no un `??` después.
      final i = detalle.indexOf('Icons.place_outlined');
      expect(i, greaterThan(0));
      final antes = detalle.substring(i - 320, i);
      expect(antes, contains("clase['sala']"));
      expect(antes, contains('isNotEmpty'));
    });

    test('un salón con sólo espacios cuenta como vacío', () {
      final i = detalle.indexOf('Icons.place_outlined');
      expect(detalle.substring(i - 320, i), contains('trim()'));
    });
  });

  group('el formulario invita a nombrar el salón', () {
    test('la sugerencia ya no es un número', () {
      expect(form.contains("hint: 'Sala 1'"), isFalse);
    });

    test('sugiere nombrarlo por disciplina, en los dos formularios', () {
      // Son dos: la clase suelta y la grilla.
      expect(
        "hint: 'Salón Cycle, Salón Pilates…'".allMatches(form).length,
        2,
      );
    });
  });
}
