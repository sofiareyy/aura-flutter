// Qué chips de categoría se muestran en el Inicio.
//
// La propiedad: NINGÚN chip puede llevar a una pantalla vacía. Se calcula
// sobre las clases que el Inicio ya tiene cargadas, así que la promesa del
// chip y lo que se ve al tocarlo no se pueden separar.
import 'package:aura_app/utils/categorias_con_oferta.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> clase(List<String> categoriasDelEstudio) => {
      'id': 1,
      'estudios': {'id': 1, 'categorias': categoriasDelEstudio},
    };

void main() {
  // El catálogo real de producción al 4/9: 13 categorías, y sólo 7 con clases.
  const catalogo = [
    'Todos', 'Barre', 'Ceramica', 'Danza', 'Fitness', 'GRATIS',
    'Gym / Funcional', 'Holistico / Bienestar', 'Meditación', 'Pilates',
    'Recovery', 'Running club', 'Spa', 'Yoga',
  ];

  test('EL BUG: se caen los 6 chips sin clases, incluida GRATIS', () {
    final visibles = categoriasConOferta(
      catalogo: catalogo,
      clases: [
        clase(['Barre']),
        clase(['Fitness', 'Gym / Funcional']),
        clase(['Yoga', 'Holistico / Bienestar']),
        clase(['Pilates']),
        clase(['Meditación']),
      ],
    );
    expect(visibles, [
      'Todos', 'Barre', 'Fitness', 'Gym / Funcional',
      'Holistico / Bienestar', 'Meditación', 'Pilates', 'Yoga',
    ]);
    for (final vacia in ['Ceramica', 'Danza', 'GRATIS', 'Recovery', 'Running club', 'Spa']) {
      expect(visibles, isNot(contains(vacia)), reason: vacia);
    }
  });

  test('"Todos" siempre está y siempre primero', () {
    expect(categoriasConOferta(catalogo: catalogo, clases: const []),
        [kCategoriaTodos]);
    final v = categoriasConOferta(catalogo: catalogo, clases: [clase(['Yoga'])]);
    expect(v.first, kCategoriaTodos);
    expect(v, ['Todos', 'Yoga']);
  });

  test('respeta el orden del catálogo y no repite', () {
    final v = categoriasConOferta(
      catalogo: catalogo,
      clases: [clase(['Yoga']), clase(['Barre']), clase(['Yoga'])],
    );
    expect(v, ['Todos', 'Barre', 'Yoga']);
  });

  test('tolera clases sin estudio o sin categorías', () {
    final v = categoriasConOferta(catalogo: catalogo, clases: [
      {'id': 1},
      {'id': 2, 'estudios': null},
      {'id': 3, 'estudios': {'id': 9, 'categorias': <String>[]}},
      clase(['Barre']),
    ]);
    expect(v, ['Todos', 'Barre']);
  });

  test('no le importa la mayúscula ni el espacio de más', () {
    final v = categoriasConOferta(
      catalogo: const ['Todos', 'Yoga'],
      clases: [clase(['  yoga  '])],
    );
    expect(v, ['Todos', 'Yoga']);
  });

  group('la categoría elegida', () {
    test('si sigue teniendo clases, se respeta', () {
      expect(categoriaValida('Yoga', const ['Todos', 'Yoga']), 'Yoga');
    });

    test('si se quedó sin clases, vuelve a Todos', () {
      expect(categoriaValida('Danza', const ['Todos', 'Yoga']), 'Todos');
      expect(categoriaValida('GRATIS', const ['Todos']), 'Todos');
    });
  });
}
