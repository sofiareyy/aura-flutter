// El cartel "Tu estudio está oculto" del panel de clases: se muestra SOLO con
// activo == false. Null (cuenta vieja o carga a medias) no dispara nada —
// nunca un falso positivo asustando a un estudio activo.
import 'package:flutter_test/flutter_test.dart';

// La regla es trivial pero es la que decide si un estudio real ve un cartel
// alarmante: se fija acá para que nadie la "simplifique" a `!activo`.
bool bannerVisible(Map<String, dynamic>? estudio) =>
    estudio != null && estudio['activo'] == false;

void main() {
  test('inactivo explícito → se muestra', () {
    expect(bannerVisible({'activo': false}), isTrue);
  });
  test('activo → no', () {
    expect(bannerVisible({'activo': true}), isFalse);
  });
  test('sin el campo (app vieja / carga a medias) → no', () {
    expect(bannerVisible({}), isFalse);
    expect(bannerVisible({'activo': null}), isFalse);
    expect(bannerVisible(null), isFalse);
  });
}
