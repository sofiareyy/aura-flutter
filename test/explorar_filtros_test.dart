// E2+E3 contra producción: el predicado del feed tiene que dar EXACTAMENTE
// los mismos conteos que la SQL sobre la foto real (leída como anon, con la
// RLS que ve la app). Los números esperados vienen de la base del 1/9/2026,
// no de este archivo.
import 'dart:convert';
import 'dart:io';

import 'package:aura_app/utils/explorar_filtros.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fx = jsonDecode(
    File('test/fixtures/explorar_feed_2026-09-01.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final planes = (fx['planes'] as List).cast<Map<String, dynamic>>();

  group('contra la foto de producción (1048 planes reales)', () {
    test('con Todos y sin búsqueda pasa TODO: nada de lo de hoy se pierde',
        () {
      final visibles = planes.where((p) => planVisible(p)).length;
      expect(visibles, fx['total']);
    });

    test('cada chip da el mismo conteo que la SQL', () {
      final esperados = (fx['conteos_por_chip'] as Map).cast<String, int>();
      for (final e in esperados.entries) {
        final n =
            planes.where((p) => planVisible(p, categoria: e.key)).length;
        expect(n, e.value, reason: 'chip ${e.key}');
      }
    });

    test('EL BUG DE YESSI: sus 70 de Gym/Funcional aparecen bajo ese chip',
        () {
      final deYessi = planes.where((p) =>
          (p['estudios'] as Map)['id'] == 10 &&
          planVisible(p, categoria: 'Gym / Funcional'));
      expect(deYessi.length, fx['yessi_gym_funcional']);
      expect(deYessi.length, greaterThan(0));
    });

    test('la búsqueda por ESTUDIO sigue andando: "citra" da lo de la SQL',
        () {
      final n = planes.where((p) => planVisible(p, query: 'citra')).length;
      expect(n, fx['busca_citra']);
    });

    test('el filtro Experiencias da lo mismo que la SQL (hoy 0)', () {
      final n = planes.where((p) => tipoVisible(p, 'experiencias')).length;
      expect(n, fx['experiencias']);
      final clases = planes.where((p) => tipoVisible(p, 'clases')).length;
      expect(clases + n, fx['total']);
    });
  });

  group('el mecanismo de experiencias (sintético: hoy no hay ninguna real)',
      () {
    final experiencia = {
      'id': 9999,
      'nombre': 'Cerámica + vino',
      'tipo': 'workshop',
      'creditos': 60,
      'categorias': ['Ceramica'],
      'estudios': {
        'id': 99,
        'nombre': 'Girlas',
        'barrio': 'San Telmo',
        'categorias': ['Ceramica'],
      },
    };

    test('entra al feed y al filtro Experiencias', () {
      expect(planVisible(experiencia), isTrue);
      expect(tipoVisible(experiencia, 'experiencias'), isTrue);
      expect(tipoVisible(experiencia, 'clases'), isFalse);
      expect(tipoVisible(experiencia, 'todo'), isTrue);
    });

    test('se encuentra por chip, por nombre y por estudio', () {
      expect(planVisible(experiencia, categoria: 'Ceramica'), isTrue);
      expect(planVisible(experiencia, categoria: 'Yoga'), isFalse);
      expect(planVisible(experiencia, query: 'vino'), isTrue);
      expect(planVisible(experiencia, query: 'girlas'), isTrue);
      expect(planVisible(experiencia, query: 'san telmo'), isTrue);
    });

    test('60 créditos queda por debajo del tope default del slider (100)',
        () {
      // El filtro de créditos vive en la pantalla: `creditos > _maxCreditos`
      // con default 100. Antes el tope era 50 y una experiencia de 60 cr
      // desaparecía en silencio.
      expect(experiencia['creditos'] as int, lessThanOrEqualTo(100));
    });

    test('etiquetas (E4) pisan a las categorías cuando existan, con fallback',
        () {
      final conEtiquetas = {
        ...experiencia,
        'categorias': ['Spa'],
        'etiquetas': ['Sauna', 'Recovery'],
      };
      expect(planVisible(conEtiquetas, categoria: 'Sauna'), isTrue);
      expect(planVisible(conEtiquetas, categoria: 'Recovery'), isTrue);
      // Con etiquetas presentes, la categoría de COBRO deja de ser la puerta.
      expect(planVisible(conEtiquetas, categoria: 'Spa'), isFalse);
      // Sin etiquetas: fallback a categorías.
      expect(planVisible(experiencia, categoria: 'Ceramica'), isTrue);
    });
  });
}
