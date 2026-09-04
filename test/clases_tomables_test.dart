import 'package:flutter_test/flutter_test.dart';
import 'package:aura_app/utils/clases_tomables.dart';
import 'package:aura_app/utils/volver_a_tus_estudios.dart';
import 'package:aura_app/utils/grilla_responsive.dart';

/// El "ahora" de todas las pruebas. Las fechas de la base vienen en hora
/// argentina sin marcador, así que se escriben igual que en producción.
final ahora = DateTime.utc(2026, 9, 4, 12, 0);

Map<String, dynamic> clase(
  String fecha, {
  int id = 1,
  int estudio = 1,
  int? cierreEstudio = 0,
  int? cierreClase,
  bool cancelada = false,
}) => {
  'id': id,
  'estudio_id': estudio,
  'fecha': fecha,
  'cancelada': cancelada,
  'reserva_cierre_minutos': ?cierreClase,
  'estudios': {'id': estudio, 'reserva_cierre_minutos': cierreEstudio},
};

void main() {
  group('sePuedeTomar', () {
    test('una clase que ya arrancó no se ofrece', () {
      expect(sePuedeTomar(clase('2026-09-04 11:59:00'), ahora), isFalse);
    });

    test('una que arranca en un minuto sí, si el estudio cierra al inicio', () {
      expect(sePuedeTomar(clase('2026-09-04 12:01:00'), ahora), isTrue);
    });

    test('justo a la hora de inicio ya no se ofrece', () {
      expect(sePuedeTomar(clase('2026-09-04 12:00:00'), ahora), isFalse);
    });

    test('respeta la ventana del estudio: Barre cierra 60 min antes', () {
      // Éste es el caso real: Barre Estudio es el único estudio activo con
      // ventana. Una clase suya a las 12:30 ya no se puede reservar a las 12.
      final barre = clase('2026-09-04 12:30:00', cierreEstudio: 60);
      expect(sePuedeTomar(barre, ahora), isFalse);
      // La de las 13:30 todavía entra, por un pelo.
      expect(
        sePuedeTomar(clase('2026-09-04 13:30:00', cierreEstudio: 60), ahora),
        isTrue,
      );
    });

    test('la ventana de la clase le gana a la del estudio', () {
      final suelta = clase(
        '2026-09-04 12:30:00',
        cierreEstudio: 60,
        cierreClase: 0,
      );
      expect(sePuedeTomar(suelta, ahora), isTrue);
    });

    test('una clase cancelada no se ofrece aunque sea futura', () {
      expect(
        sePuedeTomar(clase('2026-09-05 10:00:00', cancelada: true), ahora),
        isFalse,
      );
    });

    test('una fecha ilegible se descarta en vez de romper', () {
      expect(sePuedeTomar(clase('no es una fecha'), ahora), isFalse);
      expect(sePuedeTomar({'id': 1}, ahora), isFalse);
    });
  });

  group('clasesTomables', () {
    test('saca las pasadas y conserva el orden', () {
      final pozo = [
        clase('2026-09-04 09:00:00', id: 1),
        clase('2026-09-04 15:00:00', id: 2),
        clase('2026-09-04 11:00:00', id: 3),
        clase('2026-09-05 08:00:00', id: 4),
      ];
      final quedan = clasesTomables(pozo, ahora: ahora).map((c) => c['id']);
      expect(quedan, [2, 4]);
    });

    test('el hueco real: la pantalla abierta dos horas', () {
      // Reproduce lo medido en producción. El pozo se carga a las 10 y la
      // pantalla queda abierta: a las 12 las primeras ya arrancaron y antes
      // de este filtro se seguían dibujando.
      final pozo = List.generate(
        10,
        (i) => clase('2026-09-04 ${(10 + i).toString().padLeft(2, '0')}:00:00',
            id: i),
      );
      // A las 10 en punto la de las 10 ya arrancó: quedan 9.
      expect(
          clasesTomables(pozo, ahora: DateTime.utc(2026, 9, 4, 10)).length, 9);
      expect(clasesTomables(pozo, ahora: ahora).length, 7);
    });
  });

  group('la vidriera del Inicio', () {
    /// Un pozo ordenado por fecha, como el que devuelve la consulta.
    List<Map<String, dynamic>> pozo(List<int> estudiosEnOrden) => [
      for (var i = 0; i < estudiosEnOrden.length; i++)
        clase(
          '2026-09-04 ${(13 + i ~/ 2).toString().padLeft(2, '0')}:'
          '${(i.isEven ? 0 : 30).toString().padLeft(2, '0')}:00',
          id: i,
          estudio: estudiosEnOrden[i],
        ),
    ];

    test('con oferta variada muestra las próximas por fecha, tal cual', () {
      // Ninguna estudio repite 4 veces, así que el tope no toca nada: el
      // resultado tiene que ser exactamente las 6 primeras del pozo.
      final entrada = pozo([1, 2, 1, 3, 2, 4, 1, 5]);
      final salida = repartirEntreEstudios(
        entrada,
        max: clasesEnLaVidriera,
        cupo: topeVidrieraPorEstudio,
      );
      expect(salida.map((c) => c['id']), [0, 1, 2, 3, 4, 5]);
    });

    /// Cuántas clases aporta cada estudio en el resultado.
    Map<int, int> porEstudio(List<Map<String, dynamic>> salida) {
      final cuenta = <int, int>{};
      for (final c in salida) {
        cuenta.update(c['estudio_id'] as int, (v) => v + 1, ifAbsent: () => 1);
      }
      return cuenta;
    }

    test('con un estudio dominante, el resto entra igual', () {
      // El estudio 1 tiene los 6 primeros horarios. Sin tope se llevaría la
      // sección entera; con tope, 2 y 3 consiguen su lugar.
      final salida = repartirEntreEstudios(
        pozo([1, 1, 1, 1, 1, 1, 2, 3]),
        max: clasesEnLaVidriera,
        cupo: topeVidrieraPorEstudio,
      );
      expect(salida.length, clasesEnLaVidriera);
      expect(porEstudio(salida).keys, containsAll([1, 2, 3]));
      expect(porEstudio(salida)[1], lessThan(clasesEnLaVidriera));
    });

    test('el tope es preferencia, no prohibición: primero llenar', () {
      // Si NO hay con qué completar, es preferible repetir estudio a dejar la
      // vidriera corta. Con un solo estudio en el pozo, muestra sus 6: son la
      // oferta real, esconder la mitad no ayuda a nadie.
      final salida = repartirEntreEstudios(
        pozo([1, 1, 1, 1, 1, 1, 1, 1]),
        max: clasesEnLaVidriera,
        cupo: topeVidrieraPorEstudio,
      );
      expect(salida.length, clasesEnLaVidriera);
      expect(porEstudio(salida)[1], clasesEnLaVidriera);
    });

    test('repetir estudio está permitido: no fuerza seis lugares distintos', () {
      // Éste es el cambio de criterio que pidió Sofía. Con el reparto viejo
      // (una por estudio) esto habría devuelto 3 clases; ahora devuelve 6.
      final salida = repartirEntreEstudios(
        pozo([1, 2, 3, 1, 2, 3, 1, 2]),
        max: clasesEnLaVidriera,
        cupo: topeVidrieraPorEstudio,
      );
      expect(salida.length, clasesEnLaVidriera);
      expect(salida.map((c) => c['estudio_id']).toSet().length, 3);
    });

    test('sale ordenada por fecha', () {
      final salida = repartirEntreEstudios(
        pozo([1, 1, 1, 1, 2, 2, 2, 3]),
        max: clasesEnLaVidriera,
        cupo: topeVidrieraPorEstudio,
      );
      final fechas = salida.map((c) => c['fecha'] as String).toList();
      expect(fechas, List.of(fechas)..sort());
    });

    test('"Volvé a tus estudios" no cambia: sin cupo sigue repartiendo', () {
      // Un solo estudio con 8 clases tiene que seguir dando sus 6.
      final salida = repartirEntreEstudios(pozo([1, 1, 1, 1, 1, 1, 1, 1]),
          max: clasesEnLaVidriera);
      expect(salida.length, clasesEnLaVidriera);
    });
  });
}
