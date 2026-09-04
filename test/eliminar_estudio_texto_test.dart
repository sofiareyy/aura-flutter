// Las palabras del cartel de borrado de un estudio. Es lo que decide si Sofía
// se entera de que está por borrar historial de plata.
import 'package:aura_app/utils/eliminar_estudio_texto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Lo que devolvió la base de verdad el 4/9 (rollback), tal cual.
  final citra = ResumenBorrado.fromJson({
    'id': 4, 'nombre': 'Citra Barre', 'activo': true,
    'clases': 391, 'clases_futuras': 189, 'reservas': 5,
    'reservas_futuras_vivas': 1, 'creditos_a_devolver': 18,
    'alumnas_afectadas': 1, 'liquidaciones': 0, 'liquidaciones_pagadas': 0,
    'monto_pagado': 0, 'resenas': 2, 'accesos': 3, 'tiene_historial': true,
  });
  final hotClic = ResumenBorrado.fromJson({
    'id': 3, 'nombre': 'Hot Clic', 'activo': false,
    'clases': 0, 'reservas': 0, 'liquidaciones': 1, 'liquidaciones_pagadas': 1,
    'monto_pagado': 8400, 'accesos': 1, 'tiene_historial': true,
  });
  final limpio = ResumenBorrado.fromJson({
    'id': 7, 'nombre': 'BB Estudio Urquiza', 'activo': true,
    'clases': 0, 'reservas': 0, 'liquidaciones': 0, 'accesos': 2,
    'tiene_historial': false,
  });

  group('el nombre escrito', () {
    test('coincide sin importar mayúsculas ni espacios de más', () {
      expect(nombreCoincide('  citra barre ', 'Citra Barre'), isTrue);
      expect(nombreCoincide('CITRA BARRE', 'Citra Barre'), isTrue);
    });
    test('no coincide si falta parte o está vacío', () {
      expect(nombreCoincide('Citra', 'Citra Barre'), isFalse);
      expect(nombreCoincide('', 'Citra Barre'), isFalse);
      expect(nombreCoincide('Citra Barr', 'Citra Barre'), isFalse);
    });
  });

  group('la advertencia de historial', () {
    test('con reservas: dice cuántas, y las futuras con sus créditos', () {
      final a = advertenciaHistorial(citra)!;
      expect(a, contains('5 reservas'));
      expect(a, contains('se pierde ese historial de plata'));
      expect(a, contains('1 alumna tiene 1 reserva futura'));
      expect(a, contains('se les devuelven 18 créditos'));
      expect(a, contains('mejor desactivalo'));
    });
    test('con liquidaciones pagadas: lo dice con número', () {
      final a = advertenciaHistorial(hotClic)!;
      expect(a, contains('1 liquidación (1 pagada)'));
      expect(a, isNot(contains('reserva')));
    });
    test('sin historial: no hay advertencia, se borra limpio', () {
      expect(advertenciaHistorial(limpio), isNull);
    });
    test('si la base no manda el flag, se asume que HAY historial', () {
      final r = ResumenBorrado.fromJson({'nombre': 'X'});
      expect(r.tieneHistorial, isTrue);
    });
  });

  test('qué se borra, en una línea', () {
    expect(detalleQueSeBorra(citra),
        'Se borran 391 clases, 2 reseñas, 3 accesos vinculados. No se puede deshacer.');
    expect(detalleQueSeBorra(limpio),
        'Se borran 0 clases, 2 accesos vinculados. No se puede deshacer.');
  });

  test('el aviso después de borrar, con lo que devolvió la base', () {
    final m = resumenBorradoHecho({
      'ok': true, 'nombre': 'Citra Barre', 'clases': 391, 'reservas': 5,
      'liquidaciones': 0, 'reservas_canceladas': 1, 'creditos_devueltos': 18,
      'alumnas_avisadas': 1,
    });
    expect(m, 'Citra Barre eliminado. 391 clases y 5 reservas borradas, 18 créditos devueltos a 1 alumna.');
    expect(resumenBorradoHecho({'nombre': 'BB', 'clases': 0, 'reservas': 0}),
        'BB eliminado. 0 clases y 0 reservas borradas.');
  });
}
