// Espejo Dart vs base: PricingCalculator tiene que dar EXACTAMENTE el número
// que guarda `calcular_precio_clase`. Los valores esperados de acá NO se
// inventaron: se le pidieron a la base de producción el 30/8/2026 (los de
// servicio y experiencia dentro de `begin … rollback` sobre Hot Clic, estudio
// de prueba). Si este test falla, la que manda es la base y el espejo está mal.
import 'dart:convert';
import 'dart:io';

import 'package:aura_app/utils/pricing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hot Clic (id 3): modo fijo 12, con dos servicios activos y uno inactivo.
Map<String, dynamic> hotClic({
  int? min = 12,
  int? max = 12,
  String tipoEstudio = 'fitness',
  bool conServicios = true,
}) =>
    {
      'id': 3,
      'tipo_estudio': tipoEstudio,
      'tipo_precio': 'fijo',
      'creditos_min': min,
      'creditos_max': max,
      'precio_config': <String, dynamic>{},
      'horarios_config': {'valle': <dynamic>[]},
      'estudio_servicios_precio': conServicios
          ? [
              {'servicio': 'Spa', 'creditos': 8, 'activo': true},
              {'servicio': 'Recovery', 'creditos': 5, 'activo': true},
              {'servicio': 'Meditación', 'creditos': 99, 'activo': false},
            ]
          : <dynamic>[],
    };

PricingResult calc(Map<String, dynamic> e, List<String>? cats,
        {int dia = 1, String hora = '19:00'}) =>
    PricingCalculator.calcular(
        estudio: e, hora: hora, dia: dia, categorias: cats);

/// `tipo` que devuelve la base ↔ enum del espejo. Para modo fijo la base dice
/// 'normal' y el Dart `fijo`; el número es el mismo y esa diferencia de
/// etiqueta es anterior a todo esto.
const tipoBase = {
  'servicio': [TipoPrecio.servicio],
  'valle': [TipoPrecio.valle],
  'pico': [TipoPrecio.pico],
  'experiencia': [TipoPrecio.experiencia],
  'normal': [TipoPrecio.fijo, TipoPrecio.normal],
};

void main() {
  group('servicio de precio fijo — medido en la base el 30/8', () {
    test('servicio solo → 8 / servicio', () {
      final r = calc(hotClic(), ['Spa']);
      expect(r.creditos, 8);
      expect(r.tipo, TipoPrecio.servicio);
      expect(r.conflicto, isNull);
    });

    test('servicio + genérica → gana el servicio, 8', () {
      final r = calc(hotClic(), ['Pilates', 'Spa']);
      expect(r.creditos, 8);
      expect(r.tipo, TipoPrecio.servicio);
    });

    test('genérica sola → precio del estudio, 12', () {
      final r = calc(hotClic(), ['Pilates']);
      expect(r.creditos, 12);
      expect(r.tipo, TipoPrecio.fijo);
    });

    test('servicio inactivo → no cuenta, 12', () {
      final r = calc(hotClic(), ['Meditación']);
      expect(r.creditos, 12);
      expect(r.tipo, TipoPrecio.fijo);
    });

    test('sin categorías y null → 12', () {
      expect(calc(hotClic(), []).creditos, 12);
      expect(calc(hotClic(), null).creditos, 12);
    });

    test('match exacto de string: "spa" no es "Spa"', () {
      expect(calc(hotClic(), ['spa']).creditos, 12);
      expect(calc(hotClic(), ['Spa ']).creditos, 12);
    });

    test('dos servicios → conflicto, mismo texto que la base', () {
      final r = calc(hotClic(), ['Spa', 'Recovery']);
      expect(r.creditos, isNull);
      expect(r.tipo, TipoPrecio.servicio);
      expect(
        r.conflicto,
        'Elegiste dos servicios con precio fijo: Recovery (5 cr) y Spa (8 cr). '
        'Dejá uno solo, o pedile a Aura una categoría combinada.',
      );
    });

    test('sin precio configurado: el servicio igual vale (8)', () {
      final e = hotClic(min: null, max: null);
      expect(calc(e, ['Spa']).creditos, 8);
      final sinServ = calc(e, ['Pilates']);
      expect(sinServ.creditos, isNull);
      expect(sinServ.conflicto, isNull);
    });

    test('experiencia: genérica → 12/experiencia, servicio → 8/servicio', () {
      final e = hotClic(tipoEstudio: 'experiencia');
      final g = calc(e, ['Pilates']);
      expect(g.creditos, 12);
      expect(g.tipo, TipoPrecio.experiencia);
      final s = calc(e, ['Spa']);
      expect(s.creditos, 8);
      expect(s.tipo, TipoPrecio.servicio);
    });

    test('compat: `categoria` suelta equivale a [categoria]', () {
      final r = PricingCalculator.calcular(
          estudio: hotClic(), hora: '19:00', dia: 1, categoria: ' Spa ');
      expect(r.creditos, 8);
    });

    test('badge y detalle del servicio', () {
      final r = calc(hotClic(), ['Spa']);
      expect(r.badge, 'Precio único');
      expect(r.detalle, contains('no cambia por horario'));
      expect(r.esServicio, isTrue);
    });
  });

  group('casos reales de producción (foto del 30/8/2026)', () {
    final fx = jsonDecode(
      File('test/fixtures/pricing_casos_reales_2026-08-30.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final estudios = {
      for (final e in fx['estudios'] as List)
        (e as Map<String, dynamic>)['id'] as int: e,
    };
    final clases = (fx['clases'] as List).cast<Map<String, dynamic>>();

    test('la foto tiene lo que dice tener', () {
      expect(estudios.length, 9);
      expect(clases.length, 974);
    });

    test('puntuales medidos con calcular_precio_clase', () {
      final sculpt = estudios[9]!;
      final citra = estudios[4]!;
      final tiwar = estudios.values
          .firstWhere((e) => e['nombre'] == 'Tiwar Fitness');
      expect(calc(sculpt, null, dia: 1, hora: '09:15').creditos, 14);
      expect(calc(sculpt, null, dia: 1, hora: '09:15').tipo, TipoPrecio.valle);
      expect(calc(sculpt, null, dia: 1, hora: '19:00').creditos, 16);
      expect(calc(sculpt, null, dia: 6, hora: '09:00').creditos, 16);
      expect(calc(sculpt, null, dia: 1, hora: '08:59').creditos, 16);
      expect(calc(citra, null, dia: 3, hora: '18:00').creditos, 18);
      expect(calc(tiwar, null, dia: 1, hora: '08:30').creditos, 11);
      expect(calc(tiwar, null, dia: 1, hora: '12:30').creditos, 14);
    });

    test('las 974 clases futuras: el espejo da lo que la base guardó', () {
      final fallas = <String>[];
      for (final c in clases) {
        final e = estudios[c['estudio_id'] as int]!;
        final cats = (c['categorias'] as List?)?.cast<String>();
        final r = calc(e, cats,
            dia: c['dia'] as int, hora: c['hora'] as String);
        final tipoOk = tipoBase[c['tipo_precio']]?.contains(r.tipo) ?? false;
        if (r.creditos != c['creditos'] || !tipoOk) {
          fallas.add('${e['nombre']} ${c['dia']} ${c['hora']} $cats: '
              'base=${c['creditos']}/${c['tipo_precio']} '
              'dart=${r.creditos}/${r.tipo.name}');
        }
      }
      expect(fallas, isEmpty, reason: fallas.take(10).join('\n'));
    });
  });
}
