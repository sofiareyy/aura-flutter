// La vidriera del final del Inicio ("MÁS CLASES").
//
// HISTORIA, porque la regla cambió dos veces y cada una tapó un agujero:
//
//  · 4/9/2026 — listaba las 50 clases cargadas: 21 pantallas de scroll en el
//    celular para la última sección de la pantalla. Pasó a mostrar unas
//    pocas, "las más próximas por fecha", con un tope blando por estudio
//    para que no salieran todas del mismo lugar.
//
//  · 15/10/2026 — ese recorte por fecha dejaba afuera a estudios enteros.
//    Medido con la oferta real: las ~21 tarjetas del Inicio cubrían **de las
//    07:00 a las 10:00 de la mañana siguiente**, sobre 293 clases de 18
//    estudios. Un estudio que abre a la tarde no aparecía nunca, tuviera la
//    grilla entera cargada o no. Lo destapó Pura Spot: 86 clases publicadas,
//    invisible, porque su primera es a las 17:00.
//
//    Bajar el tope no alcanzaba (simulado: tope 1 ⇒ 13 estudios y llega
//    hasta las 11:00, Pura Spot sigue afuera). Ahora se muestra la PRÓXIMA
//    clase de CADA estudio, en la misma rueda del día que los DESTACADOS.
//
// Lo que estos tests protegen: que entren todos, que la rueda sea pareja y
// estable dentro del día, y que no se repita lo que ya está más arriba.

import 'package:aura_app/utils/vidriera_inicio.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> clase(int id, int estudioId, String fecha) => {
  'id': id,
  'fecha': fecha,
  'estudios': {'id': estudioId, 'nombre': 'Estudio $estudioId'},
};

/// n clases seguidas del mismo estudio, como pasa cuando uno tiene los
/// primeros horarios del día.
List<Map<String, dynamic>> deUnEstudio(int estudioId, int n, {int desde = 1}) =>
    List.generate(
      n,
      (i) => clase(
        estudioId * 100 + i,
        estudioId,
        '2026-09-${(desde + i).toString().padLeft(2, '0')} 10:00:00',
      ),
    );

/// El pozo llega SIEMPRE ordenado por fecha, como lo entrega la consulta.
List<Map<String, dynamic>> porFecha(List<Map<String, dynamic>> l) =>
    [...l]
      ..sort((a, b) => (a['fecha'] as String).compareTo(b['fecha'] as String));

int estudioDe(Map<String, dynamic> c) => (c['estudios'] as Map)['id'] as int;

void main() {
  final hoy = DateTime(2026, 10, 15);

  test('EL CASO QUE IMPORTA: entran TODOS los estudios, uno cada uno', () {
    // El estudio 1 tiene los 10 primeros horarios. Con la regla vieja se
    // llevaba 3 lugares y empujaba a los demás; con ésta aporta uno solo.
    final pozo = porFecha([
      ...deUnEstudio(1, 10),
      ...deUnEstudio(2, 4, desde: 11),
      ...deUnEstudio(3, 4, desde: 11),
      ...deUnEstudio(4, 4, desde: 11),
      ...deUnEstudio(5, 4, desde: 11),
      ...deUnEstudio(6, 4, desde: 11),
    ]);
    final v = vidrieraDelDia(clases: pozo, hoy: hoy);
    expect(v.length, 6, reason: '6 estudios ⇒ 6 tarjetas');
    expect(v.map(estudioDe).toSet(), {1, 2, 3, 4, 5, 6});
  });

  test('el tamaño sale de cuántos estudios hay, no de un número fijo', () {
    for (final n in [1, 3, 18, 25]) {
      final pozo = porFecha([
        for (var e = 1; e <= n; e++) ...deUnEstudio(e, 2, desde: e),
      ]);
      expect(
        vidrieraDelDia(clases: pozo, hoy: hoy).length,
        n,
        reason: 'con $n estudios tienen que entrar $n',
      );
    }
  });

  test('de cada estudio sale su PRÓXIMA clase, no una cualquiera', () {
    final pozo = porFecha([
      ...deUnEstudio(1, 3, desde: 5), // 05, 06, 07
      ...deUnEstudio(2, 3, desde: 1), // 01, 02, 03
    ]);
    final v = vidrieraDelDia(clases: pozo, hoy: hoy);
    final porEstudio = {for (final c in v) estudioDe(c): c['fecha'] as String};
    expect(porEstudio[1], '2026-09-05 10:00:00');
    expect(porEstudio[2], '2026-09-01 10:00:00');
  });

  group('la rueda del día', () {
    // Mismo criterio que `destacadosDelDia`: candidatos por id, arranque en
    // `indiceDiaArgentino % n`. Que no haya dos reglas de rotación distintas
    // en la misma app fue un pedido explícito.
    final pozo = porFecha([
      for (var e = 1; e <= 5; e++) ...deUnEstudio(e, 2, desde: e),
    ]);

    test('es estable dentro del mismo día', () {
      final a = vidrieraDelDia(clases: pozo, hoy: DateTime(2026, 10, 15, 8));
      final b = vidrieraDelDia(clases: pozo, hoy: DateTime(2026, 10, 15, 23));
      expect(a.map(estudioDe), b.map(estudioDe));
    });

    test('y cambia quién encabeza al día siguiente', () {
      final hoyLista = vidrieraDelDia(
        clases: pozo,
        hoy: DateTime(2026, 10, 15),
      );
      final manana = vidrieraDelDia(clases: pozo, hoy: DateTime(2026, 10, 16));
      expect(estudioDe(hoyLista.first), isNot(estudioDe(manana.first)));
    });

    test('en 5 días encabezan los 5, sin repetir', () {
      final primeros = <int>{};
      for (var d = 15; d < 20; d++) {
        primeros.add(
          estudioDe(
            vidrieraDelDia(clases: pozo, hoy: DateTime(2026, 10, d)).first,
          ),
        );
      }
      expect(primeros, {1, 2, 3, 4, 5});
    });

    test('rote o no, están siempre todos', () {
      for (var d = 15; d < 25; d++) {
        final v = vidrieraDelDia(clases: pozo, hoy: DateTime(2026, 10, d));
        expect(v.map(estudioDe).toSet(), {1, 2, 3, 4, 5}, reason: 'día $d');
      }
    });
  });

  test('con un solo estudio, muestra su próxima y nada más', () {
    final v = vidrieraDelDia(clases: porFecha(deUnEstudio(1, 5)), hoy: hoy);
    expect(v.length, 1);
  });

  test('sin clases, la sección queda vacía y se oculta sola', () {
    expect(vidrieraDelDia(clases: const [], hoy: hoy), isEmpty);
  });

  test('no repite lo que ya está más arriba', () {
    // "Volvé a tus estudios" se saca ANTES, como hace el Inicio.
    final arriba = deUnEstudio(1, 3);
    final yaArriba = arriba.map((c) => c['id'] as int).toSet();
    final pozo = porFecha([...arriba, ...deUnEstudio(2, 5, desde: 4)]);
    final v = vidrieraDelDia(
      clases: pozo.where((c) => !yaArriba.contains(c['id'] as int)).toList(),
      hoy: hoy,
    );
    for (final c in v) {
      expect(yaArriba.contains(c['id'] as int), isFalse);
    }
  });

  group('"Ver más clases" sigue siendo cronológico', () {
    final pozo = porFecha([
      ...deUnEstudio(1, 4),
      ...deUnEstudio(2, 4, desde: 5),
    ]);

    test('suma las que siguen por fecha, sin repetir la vidriera', () {
      final base = vidrieraDelDia(clases: pozo, hoy: hoy);
      final mas = masClasesDespuesDe(pozo, base, cuantas: 3);
      final yaVistas = base.map((c) => c['id']).toSet();
      expect(mas.length, 3);
      for (final c in mas) {
        expect(yaVistas.contains(c['id']), isFalse);
      }
      final fechas = mas.map((c) => c['fecha'] as String).toList();
      expect(fechas, [...fechas]..sort(), reason: 'tienen que venir por fecha');
    });

    test('sin toques, no suma nada', () {
      expect(masClasesDespuesDe(pozo, const [], cuantas: 0), isEmpty);
    });

    test('no devuelve más de las que quedan', () {
      final base = vidrieraDelDia(clases: pozo, hoy: hoy);
      expect(masClasesDespuesDe(pozo, base, cuantas: 999).length, 6);
    });
  });
}
