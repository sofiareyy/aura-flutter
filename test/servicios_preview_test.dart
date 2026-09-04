// El cartel que ve Sofía antes de cambiar un precio de servicio. Es la única
// pieza de la feature que habla de PLATA en palabras, así que se fija acá:
// siempre dice qué cambia y qué NO cambia, con número.
import 'package:aura_app/utils/servicios_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Lo que devolvió la base de verdad el 3/9 (Citra, Barre a 20, en rollback).
  final citra = ServicioPreview.fromJson({
    'ok': true,
    'preview': true,
    'servicio': 'Barre',
    'creditos': 20,
    'activo': true,
    'precio_anterior': null,
    'activo_anterior': null,
    'clases_afectadas': 188,
    'clases_selladas': 1,
    'clases_pasadas': 202,
    'horarios_actualizados': 23,
  });

  test('lee el jsonb de la RPC tal cual', () {
    expect(citra.afectadas, 188);
    expect(citra.selladas, 1);
    expect(citra.pasadas, 202);
    expect(citra.horarios, 23);
    expect(citra.esNuevo, isTrue);
    expect(citra.cambiaPrecio, isFalse);
  });

  test('el cartel dice las tres cosas de la regla, con número', () {
    final m = mensajeConfirmacionServicio(citra);
    expect(m, contains('188 clases futuras sin reserva pasan a 20 cr'));
    expect(m, contains('1 clase futura ya reservada NO cambia'));
    expect(m, contains('queda al precio con el que se cobró'));
    expect(m, contains('202 clases pasadas no se tocan'));
    expect(m, contains('23 horarios de la grilla'));
    expect(m, contains('Ninguna reserva ni liquidación cambia'));
  });

  test('sin reservadas lo dice igual, no calla', () {
    final p = ServicioPreview.fromJson({
      'servicio': 'Spa', 'creditos': 8, 'activo': true,
      'clases_afectadas': 3, 'clases_selladas': 0, 'clases_pasadas': 0,
    });
    final m = mensajeConfirmacionServicio(p);
    expect(m, contains('3 clases futuras sin reserva pasan a 8 cr'));
    expect(m, contains('No hay clases futuras ya reservadas'));
    expect(m, contains('0 clases pasadas no se tocan'));
  });

  test('singular y plural', () {
    final p = ServicioPreview.fromJson({
      'servicio': 'Spa', 'creditos': 8, 'activo': true,
      'clases_afectadas': 1, 'clases_selladas': 1, 'clases_pasadas': 1,
      'horarios_actualizados': 1,
    });
    final m = mensajeConfirmacionServicio(p);
    expect(m, contains('1 clase futura sin reserva pasa a 8 cr'));
    expect(m, contains('1 clase futura ya reservada NO cambia: queda al precio'));
    expect(m, contains('1 clase pasada no se toca'));
    expect(m, contains('1 horario de la grilla nace'));
  });

  test('cambio de precio: el título muestra de cuánto a cuánto', () {
    final p = ServicioPreview.fromJson({
      'servicio': 'Barre', 'creditos': 25, 'activo': true,
      'precio_anterior': 20, 'activo_anterior': true,
      'clases_afectadas': 188, 'clases_selladas': 1, 'clases_pasadas': 202,
    });
    expect(p.cambiaPrecio, isTrue);
    expect(tituloConfirmacionServicio(p, 'Citra'), 'Barre: de 20 cr a 25 cr');
  });

  test('desactivar: no toca clases y lo dice', () {
    final p = ServicioPreview.fromJson({
      'servicio': 'Barre', 'creditos': 20, 'activo': false,
      'precio_anterior': 20, 'activo_anterior': true,
      'clases_afectadas': 0, 'clases_selladas': 1, 'clases_pasadas': 202,
    });
    expect(tituloConfirmacionServicio(p, 'Citra'), 'Desactivar Barre en Citra');
    final m = mensajeConfirmacionServicio(p);
    expect(m, contains('conservan su precio'));
    expect(m, contains('Ninguna reserva cambia'));
    expect(resumenAplicadoServicio(p), 'Barre desactivado.');
  });

  test('gratis a 0 se lee bien', () {
    final p = ServicioPreview.fromJson({
      'servicio': 'Running club', 'creditos': 0, 'activo': true,
      'clases_afectadas': 4, 'clases_selladas': 0, 'clases_pasadas': 0,
    });
    expect(mensajeConfirmacionServicio(p),
        contains('4 clases futuras sin reserva pasan a 0 cr'));
    expect(resumenAplicadoServicio(p),
        'Running club a 0 cr. 4 clases actualizadas.');
  });

  test('un jsonb incompleto no rompe el cartel', () {
    final p = ServicioPreview.fromJson({'servicio': 'X', 'creditos': 5});
    expect(p.afectadas, 0);
    expect(p.activo, isTrue);
    expect(() => mensajeConfirmacionServicio(p), returnsNormally);
  });
}
