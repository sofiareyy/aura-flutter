import 'package:aura_app/models/estudio.dart';
import 'package:aura_app/utils/explorar_filtros.dart';
import 'package:flutter_test/flutter_test.dart';

// Filtro por barrio de Explorar (16/11/2026).
void main() {
  Estudio e(int id, String? barrio) =>
      Estudio(id: id, nombre: 'E$id', barrio: barrio);

  final estudios = [
    e(1, 'Palermo'),
    e(2, 'Pilar'),
    e(3, ' palermo '), // mismo barrio con otra escritura
    e(4, 'Núñez'),
    e(5, null),
    e(6, ''),
  ];

  test('lista cada barrio una vez, ordenado, sin vacíos', () {
    expect(barriosConEstudios(estudios), ['Núñez', 'Palermo', 'Pilar']);
  });

  test('sin barrio elegido no toca la consulta', () {
    expect(idsEstudiosDeBarrios(estudios, {}), isNull);
    expect(estudioEnBarrios(estudios[4], {}), isTrue);
  });

  test('un barrio trae todos sus estudios, aunque esté escrito distinto', () {
    expect(idsEstudiosDeBarrios(estudios, {'Palermo'}), [1, 3]);
  });

  test('varios barrios suman', () {
    expect(idsEstudiosDeBarrios(estudios, {'Pilar', 'Núñez'}), [2, 4]);
  });

  test('un barrio sin estudios da lista vacía (no "sin filtro")', () {
    expect(idsEstudiosDeBarrios(estudios, {'Recoleta'}), isEmpty);
  });
}
