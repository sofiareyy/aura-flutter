// El fallback de categorías de un plan (17/9/2026).
//
// El bug: `catsBusquedaDe` miraba sólo `etiquetas` y `categorias`, mientras que
// la TARJETA usa `categoriaDeClase`, que además cae al campo suelto y al
// estudio. Resultado: una experiencia mostraba "Cerámica" en su tarjeta y
// desaparecía al tocar el chip "Cerámica".
import 'package:aura_app/utils/explorar_filtros.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('usa las etiquetas si están', () {
    expect(
        catsBusquedaDe({'etiquetas': ['Barre'], 'categorias': ['Yoga']}),
        ['Barre']);
  });

  test('si no, la lista de categorías', () {
    expect(catsBusquedaDe({'categorias': ['Pilates', 'Fitness']}),
        ['Pilates', 'Fitness']);
  });

  test('si no, el campo suelto — ACÁ ESTABA EL BUG', () {
    expect(catsBusquedaDe({'categoria': 'Ceramica'}), ['Ceramica']);
  });

  test('y si la clase no declara nada, hereda del estudio', () {
    expect(
        catsBusquedaDe({
          'estudios': {'categorias': ['Ceramica', 'Arte']},
        }),
        ['Ceramica', 'Arte']);
  });

  test('sin nada, lista vacía (no explota)', () {
    expect(catsBusquedaDe({}), isEmpty);
    expect(catsBusquedaDe({'categorias': [], 'categoria': '  '}), isEmpty);
  });

  test('la experiencia de cerámica ahora SÍ pasa su chip', () {
    // La experiencia real de Grito Cerámica, con la categoría sólo en el
    // campo suelto: antes no pasaba el chip "Ceramica".
    final experiencia = {
      'tipo': 'workshop',
      'nombre': 'Cerámica con niños y adultos 🏺',
      'categoria': 'Ceramica',
      'estudios': {'nombre': 'Grito Cerámica', 'categorias': ['Ceramica']},
    };
    expect(planVisible(experiencia, categoria: 'Ceramica'), isTrue);
    expect(planVisible(experiencia, categoria: 'Yoga'), isFalse);
  });

  group('el orden del feed no se mueve (compararPlanes)', () {
    Map<String, dynamic> plan(int id, String fecha) =>
        {'id': id, 'fecha': fecha};

    test('ordena por fecha', () {
      final xs = [plan(1, '2026-09-20 10:00:00'), plan(2, '2026-09-18 10:00:00')]
        ..sort(compararPlanes);
      expect(xs.map((p) => p['id']), [2, 1]);
    });

    test('a igual horario, desempata por id — SIEMPRE el mismo orden', () {
      // El caso real: varias clases a las 10:00 de distintos estudios.
      final a = [plan(7, '2026-09-20 10:00:00'), plan(3, '2026-09-20 10:00:00'),
                 plan(5, '2026-09-20 10:00:00')]..sort(compararPlanes);
      final b = [plan(5, '2026-09-20 10:00:00'), plan(7, '2026-09-20 10:00:00'),
                 plan(3, '2026-09-20 10:00:00')]..sort(compararPlanes);
      expect(a.map((p) => p['id']), [3, 5, 7]);
      expect(a.map((p) => p['id']), b.map((p) => p['id']),
          reason: 'la misma lista en otro orden de entrada da el mismo de salida');
    });

    test('las que no tienen fecha van al final', () {
      final xs = [plan(1, 'roto'), plan(2, '2026-09-20 10:00:00')]
        ..sort(compararPlanes);
      expect(xs.first['id'], 2);
    });
  });
}

