// La vidriera del final del Inicio ("MÁS CLASES").
//
// Antes listaba las 50 clases cargadas: medido con las medidas reales de la
// tarjeta, 21 pantallas de scroll en el celular para la última sección de la
// pantalla. Ahora muestra 6, elegidas para que se vean VARIADAS.
//
// Reutiliza `repartirEntreEstudios`, el mismo reparto de "Volvé a tus
// estudios": la regla vive en un solo lugar.
import 'package:aura_app/utils/grilla_responsive.dart';
import 'package:aura_app/utils/volver_a_tus_estudios.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> clase(int id, int estudioId, String fecha) => {
      'id': id,
      'fecha': fecha,
      'estudios': {'id': estudioId, 'nombre': 'Estudio $estudioId'},
    };

/// n clases seguidas del mismo estudio, como pasa cuando uno tiene los
/// primeros horarios del día.
List<Map<String, dynamic>> deUnEstudio(int estudioId, int n, {int desde = 1}) =>
    List.generate(
      n,
      (i) => clase(estudioId * 100 + i, estudioId,
          '2026-09-${(desde + i).toString().padLeft(2, '0')} 10:00:00'),
    );

void main() {
  test('la vidriera son 6, un solo número para las dos vistas', () {
    expect(clasesEnLaVidriera, 6);
  });

  test('EL CASO QUE IMPORTA: 6 estudios distintos, no 6 del mismo', () {
    // 6 estudios, y el 1 tiene los primeros 10 horarios: sin reparto, la
    // vidriera serían 6 clases del estudio 1.
    final pozo = [
      ...deUnEstudio(1, 10),
      ...deUnEstudio(2, 4, desde: 11),
      ...deUnEstudio(3, 4, desde: 11),
      ...deUnEstudio(4, 4, desde: 11),
      ...deUnEstudio(5, 4, desde: 11),
      ...deUnEstudio(6, 4, desde: 11),
    ];
    final v = repartirEntreEstudios(pozo, max: clasesEnLaVidriera);
    expect(v.length, 6);
    final estudios = v
        .map((c) => (c['estudios'] as Map)['id'] as int)
        .toSet();
    expect(estudios.length, 6, reason: 'salieron de $estudios');
  });

  test('con pocos estudios, se completa con una segunda de cada uno', () {
    final pozo = [...deUnEstudio(1, 5), ...deUnEstudio(2, 5, desde: 6)];
    final v = repartirEntreEstudios(pozo, max: clasesEnLaVidriera);
    expect(v.length, 6);
    final porEstudio = <int, int>{};
    for (final c in v) {
      final id = (c['estudios'] as Map)['id'] as int;
      porEstudio[id] = (porEstudio[id] ?? 0) + 1;
    }
    expect(porEstudio, {1: 3, 2: 3});
  });

  test('con menos clases que lugares, muestra las que hay', () {
    expect(repartirEntreEstudios(deUnEstudio(1, 2), max: clasesEnLaVidriera)
        .length, 2);
  });

  test('sin clases, la sección queda vacía y se oculta sola', () {
    expect(repartirEntreEstudios(const [], max: clasesEnLaVidriera), isEmpty);
  });

  test('queda ordenada por fecha: lo más próximo primero', () {
    final pozo = [
      ...deUnEstudio(1, 4),
      ...deUnEstudio(2, 4, desde: 5),
      ...deUnEstudio(3, 4, desde: 9),
    ];
    final v = repartirEntreEstudios(pozo, max: clasesEnLaVidriera);
    final fechas = v.map((c) => c['fecha'] as String).toList();
    expect(fechas, [...fechas]..sort());
  });

  group('no repite lo que ya está más arriba', () {
    test('las de "Volvé a tus estudios" quedan afuera', () {
      final arriba = deUnEstudio(1, 3);
      final pozo = [...arriba, ...deUnEstudio(2, 5, desde: 4)];
      final yaArriba = arriba.map((c) => c['id'] as int).toSet();

      final v = repartirEntreEstudios(
        pozo.where((c) => !yaArriba.contains(c['id'] as int)).toList(),
        max: clasesEnLaVidriera,
      );
      for (final c in v) {
        expect(yaArriba.contains(c['id'] as int), isFalse,
            reason: 'la clase ${c['id']} está repetida');
      }
      expect(v.length, 5); // quedaban 5 después de sacar las 3 de arriba
    });
  });
}
