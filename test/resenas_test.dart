// Cálculos de reseñas. Están en un solo lugar a propósito: hoy el promedio
// toma toda la historia, y si mañana se quiere "últimos 90 días" se cambia
// acá y vale para las dos puntas (alumna y estudio).
import 'package:aura_app/utils/resenas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('promedio con los datos REALES de Citra: 2 reseñas de 5★', () {
    expect(Resenas.promedioDe({5: 2, 4: 0, 3: 0, 2: 0, 1: 0}), 5.0);
    expect(Resenas.totalDe({5: 2, 4: 0, 3: 0, 2: 0, 1: 0}), 2);
    expect(Resenas.formatearPromedio(5.0), '5,0');
  });

  test('SIN reseñas el promedio es null, no 0,0', () {
    // Clic Pilates quedó así al borrar la reseña de test. Mostrar "0,0"
    // parecería una nota pésima; null significa "todavía no hay".
    final vacio = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    expect(Resenas.promedioDe(vacio), isNull);
    expect(Resenas.formatearPromedio(null), '—');
    expect(Resenas.etiquetaTotal(0), 'Sin reseñas todavía');
  });

  test('promedio mezclado, con coma decimal argentina', () {
    // 5+5+4+3 = 17 / 4 = 4,25
    final d = {5: 2, 4: 1, 3: 1, 2: 0, 1: 0};
    expect(Resenas.promedioDe(d), 4.25);
    expect(Resenas.formatearPromedio(Resenas.promedioDe(d)), '4,3');
    expect(Resenas.totalDe(d), 4);
  });

  test('singular y plural', () {
    expect(Resenas.etiquetaTotal(1), '1 reseña');
    expect(Resenas.etiquetaTotal(2), '2 reseñas');
  });
}
