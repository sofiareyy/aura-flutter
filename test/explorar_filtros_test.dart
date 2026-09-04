// E2+E3 contra producción: el predicado del feed tiene que dar EXACTAMENTE
// los mismos conteos que la SQL sobre la foto real (leída como anon, con la
// RLS que ve la app). Los números esperados vienen de la base del 1/9/2026,
// no de este archivo.
import 'dart:convert';
import 'dart:io';

import 'package:aura_app/models/estudio.dart';
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

  group('badge de precio: un servicio nunca dice PRECIO REDUCIDO', () {
    // La lógica del badge (copiada de _ResultCard): reducido = cuesta menos
    // que el techo de un estudio CON rango... salvo que sea un servicio, cuyo
    // precio es único por definición.
    bool esPrecioReducido(
        {String? tipoPrecio, int? creditos, int? min, int? max}) {
      final esServicio = tipoPrecio == 'servicio';
      return !esServicio &&
          creditos != null &&
          min != null &&
          max != null &&
          max > min &&
          creditos < max;
    }

    test('servicio de 14 en estudio con techo 18 → NO es "reducido"', () {
      expect(
          esPrecioReducido(
              tipoPrecio: 'servicio', creditos: 14, min: 12, max: 18),
          isFalse);
    });

    test('clase valle de 14 con techo 18 → sí es reducido (como siempre)', () {
      expect(
          esPrecioReducido(tipoPrecio: 'valle', creditos: 14, min: 12, max: 18),
          isTrue);
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

    test('PRIMERA PANTALLA: la experiencia aparece sin paginar (el bug del 1/9)',
        () {
      // El agujero medido en producción: con el stream unificado, la
      // experiencia del sábado quedaba en la posición 97 de 1049 y hacían
      // falta 4 "Cargar más" para verla. Con los dos streams, el cliente la
      // tiene desde la primera página.
      final clasesOrdenadas = [...planes]..sort((a, b) =>
          (a['id'] as int).compareTo(b['id'] as int));
      final primeraPagina = clasesOrdenadas.take(20).toList();
      final feed = mezclarFeed(primeraPagina, [experiencia]);

      expect(feed.any((p) => p['id'] == 9999), isTrue,
          reason: 'la experiencia tiene que estar en lo que el cliente ve');
      expect(feed.length, 21);
      // Y el filtro Experiencias ya no arranca vacío:
      expect(feed.where((p) => tipoVisible(p, 'experiencias')).length, 1);
    });

    test('sección EXPERIENCIAS: muestra las próximas y se oculta sin ninguna',
        () {
      final feed = mezclarFeed(planes.take(20).toList(), [experiencia]);
      final destacadas = experienciasDestacadas(feed);
      expect(destacadas.length, 1);
      expect(destacadas.first['id'], 9999);

      // Sin experiencias en el feed, la sección no se dibuja.
      expect(experienciasDestacadas(planes.take(20).toList()), isEmpty);

      // Con el filtro Tipo = Clases, tampoco (el feed ya viene sin workshops).
      final soloClases =
          feed.where((p) => tipoVisible(p, 'clases')).toList();
      expect(experienciasDestacadas(soloClases), isEmpty);
    });

    test('sección EXPERIENCIAS: tope de 3 y respeta el orden del feed', () {
      final tres = List.generate(
          5,
          (i) => {
                'id': 8000 + i,
                'nombre': 'Exp $i',
                'tipo': 'workshop',
                'fecha': '2026-09-0${i + 1} 20:00:00',
                'categorias': const ['Ceramica'],
              });
      final feed = mezclarFeed(const [], tres);
      final destacadas = experienciasDestacadas(feed);
      expect(destacadas.length, 3);
      expect(destacadas.map((e) => e['id']).toList(), [8000, 8001, 8002]);
    });

    test('mezclarFeed: ordena por fecha y dedup por id', () {
      final a = {'id': 1, 'fecha': '2026-09-03 10:00:00'};
      final b = {'id': 2, 'fecha': '2026-09-01 10:00:00'};
      final feed = mezclarFeed([a, b], [b, {'id': 3, 'fecha': '2026-09-02 09:00:00'}]);
      expect(feed.map((p) => p['id']).toList(), [2, 3, 1]);
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

  // ── DESTACADOS HOY: turno PAREJO (decisión de Sofía, 4/9/2026) ────────
  //
  // Nada de ponderar por cantidad de clases: muchas clases no es lo mismo que
  // más atractivo. Rueda pareja, y el primero recorre a todos antes de repetir.
  group('destacadosDelDia', () {
    Estudio e(int id, String nombre) =>
        Estudio.fromMap({'id': id, 'nombre': nombre, 'categorias': <String>[]});
    Map<String, dynamic> claseDe(int id) => {
          'id': id * 1000,
          'estudios': {'id': id, 'nombre': 'x'},
        };
    List<Map<String, dynamic>> nClases(int id, int n) =>
        List.generate(n, (i) => {'id': id * 1000 + i, 'estudios': {'id': id}});

    // Los reales, con su reparto real de clases: muy desparejo a propósito.
    final estudios = [
      e(1, 'Ambra'), e(2, 'Barre'), e(3, 'Citra'), e(4, 'Tiwar'),
      e(5, 'Yessi'), e(6, 'Yoguica'), e(7, 'Sculpt'),
    ];
    final clases = [
      ...nClases(4, 312), ...nClases(3, 194), ...nClases(5, 176),
      ...nClases(6, 125), ...nClases(1, 66), ...nClases(2, 51),
      // Sculpt (7) sin clases.
    ];
    DateTime dia(int d) => DateTime.utc(2026, 9, 4, 15).add(Duration(days: d));
    List<String> sel(int d, {int? asociadoId}) => destacadosDelDia(
          estudios: estudios,
          clases: clases,
          hoy: dia(d),
          asociadoId: asociadoId,
        ).map((x) => x.nombre).toList();

    test('muestra 4', () => expect(sel(0).length, 4));

    test('NUNCA destaca un estudio sin clases', () {
      for (var d = 0; d < 60; d++) {
        expect(sel(d), isNot(contains('Sculpt')), reason: 'día +$d');
      }
    });

    test('ESTABLE dentro del mismo día', () {
      final manana = destacadosDelDia(
          estudios: estudios, clases: clases, hoy: DateTime.utc(2026, 9, 4, 11));
      final tarde = destacadosDelDia(
          estudios: estudios, clases: clases, hoy: DateTime.utc(2026, 9, 4, 22));
      expect(tarde.map((x) => x.nombre).toList(),
          manana.map((x) => x.nombre).toList());
    });

    test('el corte es el día ARGENTINO, no el UTC', () {
      // 4/9 23:00 ART = 5/9 02:00 UTC: sigue siendo el 4 para nosotras.
      final tarde = destacadosDelDia(
          estudios: estudios, clases: clases, hoy: DateTime.utc(2026, 9, 5, 2));
      expect(tarde.map((x) => x.nombre).toList(), sel(0));
    });

    test('EL PRIMERO cambia todos los días y no repite', () {
      final primeros = [for (var d = 0; d < 6; d++) sel(d).first];
      for (var i = 1; i < primeros.length; i++) {
        expect(primeros[i], isNot(primeros[i - 1]),
            reason: 'día $i repitió a ${primeros[i]}');
      }
      // Con 6 candidatos, en 6 días fueron primeros los 6, sin repetir ninguno.
      expect(primeros.toSet().length, 6);
      // Y al séptimo vuelve a empezar la rueda.
      expect(sel(6).first, primeros.first);
    });

    test('TODOS salen la misma cantidad de días: 4 de cada 6', () {
      final veces = <String, int>{};
      for (var d = 0; d < 60; d++) {
        for (final n in sel(d)) {
          veces[n] = (veces[n] ?? 0) + 1;
        }
      }
      expect(veces.keys.toSet(),
          {'Ambra', 'Barre', 'Citra', 'Tiwar', 'Yessi', 'Yoguica'});
      // 60 días / 6 candidatos * 4 lugares = 40 para cada uno, exacto.
      for (final entrada in veces.entries) {
        expect(entrada.value, 40, reason: '${entrada.key} salió ${entrada.value}');
      }
    });

    test('LA CANTIDAD DE CLASES YA NO MANDA: Tiwar no sale más que Barre', () {
      var tiwar = 0, barre = 0;
      for (var d = 0; d < 60; d++) {
        final s = sel(d);
        if (s.contains('Tiwar')) tiwar++;
        if (s.contains('Barre')) barre++;
      }
      // Tiwar tiene 312 clases y Barre 51: antes era 27 contra 0.
      expect(tiwar, barre);
    });

    test('ser primero también es parejo', () {
      final primeros = <String, int>{};
      for (var d = 0; d < 60; d++) {
        final n = sel(d).first;
        primeros[n] = (primeros[n] ?? 0) + 1;
      }
      for (final entrada in primeros.entries) {
        expect(entrada.value, 10, reason: '${entrada.key} fue primero ${entrada.value} veces');
      }
    });

    test('tu propio estudio va primero, aunque no tenga clases', () {
      final s = sel(0, asociadoId: 7);
      expect(s.first, 'Sculpt');
      expect(s.length, 4);
      expect(s.sublist(1), isNot(contains('Sculpt')));
    });

    test('con menos candidatos que lugares, salen todos y el orden rota', () {
      final pocas = [...nClases(3, 5), ...nClases(4, 2)];
      List<String> conPocas(int d) => destacadosDelDia(
            estudios: estudios, clases: pocas, hoy: dia(d),
          ).map((x) => x.nombre).toList();
      expect(conPocas(0).length, 2);
      expect(conPocas(0).toSet(), {'Citra', 'Tiwar'});
      // Aunque salgan los dos siempre, el primero alterna.
      expect(conPocas(1).first, isNot(conPocas(0).first));
    });

    test('sin clases cargadas no destaca a nadie', () {
      expect(destacadosDelDia(estudios: estudios, clases: const [], hoy: dia(0)),
          isEmpty);
    });

    test('no rompe con clases sin estudio', () {
      final s = destacadosDelDia(estudios: estudios, hoy: dia(0), clases: [
        {'id': 1},
        {'id': 2, 'estudios': null},
        claseDe(3),
      ]);
      expect(s.single.nombre, 'Citra');
    });
  });
}
