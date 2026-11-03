import 'package:aura_app/utils/ids_detalle_cobros.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('los ids salen de las reservas que se muestran, sin repetir', () {
    final octubre = [
      {'clase_id': 10, 'usuario_id': 'malena'},
      {'clase_id': 11, 'usuario_id': 'emilie'},
      {'clase_id': 10, 'usuario_id': 'gina'},
      {'clase_id': 12, 'usuario_id': 'malena'},
    ];
    final (clases, alumnas) = idsDelDetalle(octubre);
    expect(clases.toSet(), {10, 11, 12});
    expect(alumnas.toSet(), {'malena', 'emilie', 'gina'});
    expect(alumnas.length, 3);
  });

  test('filas sin clase o sin alumna no rompen', () {
    final (clases, alumnas) = idsDelDetalle([
      {'clase_id': null, 'usuario_id': null},
      {'clase_id': 7.0, 'usuario_id': ''},
      {'usuario_id': 'sol'},
    ]);
    expect(clases, [7]);
    expect(alumnas, ['sol']);
  });

  test('sin reservas, sin ids', () {
    final (clases, alumnas) = idsDelDetalle(const []);
    expect(clases, isEmpty);
    expect(alumnas, isEmpty);
  });
}
