// El reparto de "VOLVÉ A TUS ESTUDIOS".
//
// El caso que le da sentido: medido contra producción, una cuenta que reservó
// sólo en Citra recibía OCHO tarjetas casi idénticas. La sección tiene que
// mostrar variedad cuando la hay y no quedar a medias cuando no.
import 'package:aura_app/utils/volver_a_tus_estudios.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> clase(int id, int estudioId, String fecha) => {
      'id': id,
      'fecha': fecha,
      'estudios': {'id': estudioId, 'nombre': 'Estudio $estudioId'},
    };

/// n clases del mismo estudio, una por día.
List<Map<String, dynamic>> serie(int estudioId, int n, {int desde = 1}) =>
    List.generate(
      n,
      (i) => clase(
        estudioId * 100 + i,
        estudioId,
        '2026-09-${(desde + i).toString().padLeft(2, '0')} 10:00:00',
      ),
    );

void main() {
  group('el cupo por estudio', () {
    test('reparte los 6 lugares entre los estudios que haya', () {
      expect(cupoPorEstudio(1), 6);
      expect(cupoPorEstudio(2), 3);
      expect(cupoPorEstudio(3), 2);
      expect(cupoPorEstudio(4), 2); // techo: nadie se queda en 1
      expect(cupoPorEstudio(6), 1);
    });

    test('nunca da 0 ni rompe con 0 estudios', () {
      expect(cupoPorEstudio(0), 0);
      expect(cupoPorEstudio(20), 1);
    });
  });

  group('el reparto', () {
    test('EL CASO DE MALENA: un solo estudio, 8 clases → 6', () {
      final r = repartirEntreEstudios(serie(1, 8));
      expect(r.length, 6);
      expect(r.map((c) => c['id']), serie(1, 8).take(6).map((c) => c['id']));
    });

    test('dos estudios: 3 y 3, no 6 del primero', () {
      final r = repartirEntreEstudios([...serie(1, 8), ...serie(2, 8)]);
      expect(r.length, 6);
      final porEstudio = <int, int>{};
      for (final c in r) {
        final id = (c['estudios'] as Map)['id'] as int;
        porEstudio[id] = (porEstudio[id] ?? 0) + 1;
      }
      expect(porEstudio, {1: 3, 2: 3});
    });

    test('tres estudios: 2 de cada uno', () {
      final r = repartirEntreEstudios(
          [...serie(1, 5), ...serie(2, 5), ...serie(3, 5)]);
      expect(r.length, 6);
      final porEstudio = <int, int>{};
      for (final c in r) {
        final id = (c['estudios'] as Map)['id'] as int;
        porEstudio[id] = (porEstudio[id] ?? 0) + 1;
      }
      expect(porEstudio, {1: 2, 2: 2, 3: 2});
    });

    test('si un estudio tiene poco, el otro RELLENA: no queda a medias', () {
      // Estudio 2 tiene una sola clase. Sin la segunda pasada quedarían 4.
      final r = repartirEntreEstudios([...serie(1, 8), ...serie(2, 1)]);
      expect(r.length, 6);
      final delDos = r.where((c) => (c['estudios'] as Map)['id'] == 2).length;
      expect(delDos, 1);
    });

    test('siempre queda ordenado por fecha, aunque haya rellenado', () {
      final r = repartirEntreEstudios([...serie(1, 8), ...serie(2, 1)]);
      final fechas = r.map((c) => c['fecha'] as String).toList();
      final ordenadas = [...fechas]..sort();
      expect(fechas, ordenadas);
    });

    test('con menos clases que lugares, muestra las que hay', () {
      expect(repartirEntreEstudios(serie(1, 2)).length, 2);
    });

    test('sin clases devuelve vacío: la sección se oculta', () {
      expect(repartirEntreEstudios(const []), isEmpty);
    });

    test('tolera el estudio_id suelto, sin embed', () {
      final r = repartirEntreEstudios([
        {'id': 1, 'fecha': '2026-09-01 10:00:00', 'estudio_id': 7},
        {'id': 2, 'fecha': '2026-09-02 10:00:00', 'estudio_id': 7},
      ]);
      expect(r.length, 2);
    });

    test('descarta las clases sin estudio en vez de romper', () {
      final r = repartirEntreEstudios([
        {'id': 1, 'fecha': '2026-09-01 10:00:00'},
        ...serie(1, 2),
      ]);
      expect(r.length, 2);
      expect(r.every((c) => c['estudios'] != null), isTrue);
    });

    test('max configurable', () {
      expect(repartirEntreEstudios(serie(1, 8), max: 3).length, 3);
      expect(repartirEntreEstudios(serie(1, 8), max: 0), isEmpty);
    });
  });
}
