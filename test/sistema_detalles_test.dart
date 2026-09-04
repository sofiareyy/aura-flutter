// La pasada del sistema por las dos pantallas de detalle, y el cierre de las
// diferencias que quedaban entre el Inicio y Explorar (4/9/2026).
//
// Lo que más cuidan estos tests es lo que NO se tocó: los créditos. La regla es
// de Sofía y es fácil de romper sin querer con un reemplazo global de tamaños.
import 'dart:io';

import 'package:aura_app/core/theme/aura_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

String leer(String p) => File(p).readAsStringSync();

/// Los radios escritos a mano que quedan en un archivo.
List<String> radiosCrudos(String fuente) =>
    RegExp(r'circular\((\d+)\)')
        .allMatches(fuente)
        .map((m) => m.group(1)!)
        .toSet()
        .toList()
      ..sort();

void main() {
  final clase = leer('lib/screens/clases/detalle_clase_screen.dart');
  final estudio = leer('lib/screens/estudios/detalle_estudio_screen.dart');
  final inicio = leer('lib/screens/home/home_screen.dart');
  final explorar = leer('lib/screens/explorar/explorar_screen.dart');

  group('LOS CRÉDITOS NO SE TOCAN', () {
    test('el número grande sigue en 38', () {
      // Es el número de créditos del detalle de clase. Un reemplazo global de
      // la escala se lo habría comido.
      expect(clase.contains('fontSize: 38'), isTrue);
    });

    test('y el " créditos" que va al lado sigue en 16', () {
      final i = clase.indexOf("text: ' créditos'");
      expect(i, greaterThan(0));
      expect(clase.substring(i, i + 500).contains('fontSize: 16'), isTrue);
    });
  });

  group('el detalle de clase', () {
    test('no quedan radios a mano, salvo el de la hoja modal', () {
      expect(radiosCrudos(clase), ['24']);
    });

    test('la descripción larga se puede plegar', () {
      expect(clase.contains('TextoExpandible('), isTrue);
    });

    test('el spinner de pantalla completa es ahora una silueta', () {
      expect(clase.contains('AuraSkeleton'), isTrue);
    });

    test('pero los spinners DENTRO de los botones se quedan', () {
      // Mientras se manda la reserva, un spinner es lo correcto: una silueta
      // mentiría sobre lo que está pasando.
      expect(
        'CircularProgressIndicator'.allMatches(clase).length,
        2,
        reason: 'los dos de los botones, no el de pantalla completa',
      );
    });
  });

  group('el detalle de estudio', () {
    test('no quedan radios a mano', () {
      expect(radiosCrudos(estudio), isEmpty);
    });

    test('la descripción usa el "Ver más"', () {
      expect(estudio.contains('TextoExpandible(e.descripcion!)'), isTrue);
    });

    test('ya no queda ningún spinner', () {
      expect(estudio.contains('CircularProgressIndicator'), isFalse);
      expect(estudio.contains('AuraSkeleton'), isTrue);
    });
  });

  group('el Inicio y Explorar ya no se contradicen', () {
    test('las tarjetas tienen las mismas esquinas', () {
      // Antes: Inicio 20, Explorar 18, y el token decía 16.
      expect(radiosCrudos(inicio), ['24'], reason: 'sólo la hoja modal');
      expect(radiosCrudos(explorar), ['24']);
      expect(AuraRadio.tarjeta, 16);
    });

    test('y el mismo borde, el cálido de la marca', () {
      // El Inicio usaba un gris frío al 14%; Explorar el cálido.
      expect(inicio.contains('grey.withValues(alpha: 0.14)'), isFalse);
      expect(inicio.contains('AppColors.warmBorder'), isTrue);
      expect(explorar.contains('AppColors.warmBorder'), isTrue);
    });
  });
}
