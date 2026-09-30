// Cupos propios por horario y la lista única de duraciones (30/9/2026).
import 'package:aura_app/screens/clases/mis_clases_screen.dart';
import 'package:aura_app/utils/cupos_grilla.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TimeOfDay h(int hora, [int min = 0]) => TimeOfDay(hour: hora, minute: min);

void main() {
  group('cupos propios por horario', () {
    test('un cupo igual al general no se guarda como excepción', () {
      final cupos = <int, Map<int, int>>{};
      fijarCupo(cupos, dia: 1, minuto: 480, valor: 12, general: 12);
      expect(cupos, isEmpty);
    });

    test('dos horarios del mismo día pueden tener cupos distintos', () {
      final cupos = <int, Map<int, int>>{};
      fijarCupo(cupos, dia: 1, minuto: minutoClave(h(8)), valor: 2, general: 12);
      fijarCupo(cupos, dia: 1, minuto: minutoClave(h(9)), valor: 3, general: 12);
      expect(cupos[1], {480: 2, 540: 3});
      expect(cuantosConCupoPropio(cupos), 2);
    });

    test('borrar un horario borra su cupo propio', () {
      final cupos = <int, Map<int, int>>{
        1: {480: 2, 540: 3},
      };
      // Quedó sólo el de las 9.
      podarCupos(cupos, {
        1: [h(9)],
      });
      expect(cupos[1], {540: 3});
    });

    test('un día sin horarios desaparece del mapa', () {
      final cupos = <int, Map<int, int>>{
        1: {480: 2},
        2: {600: 5},
      };
      podarCupos(cupos, {
        2: [h(10)],
      });
      expect(cupos.containsKey(1), isFalse);
      expect(cupos[2], {600: 5});
    });

    test('volver a "usar el general" saca la excepción', () {
      final cupos = <int, Map<int, int>>{
        3: {480: 2},
      };
      quitarCupo(cupos, dia: 3, minuto: 480);
      expect(cupos, isEmpty);
    });
  });

  group('duraciones', () {
    test('la lista de clase incluye 30, que antes faltaba en la clase suelta', () {
      expect(kDuracionesClase, contains(30));
    });

    test('una duración guardada fuera de la lista ENTRA igual', () {
      // Esto es lo que hacía reventar la pantalla: DropdownButton exige que
      // el valor esté entre los ítems.
      final items = itemsDuracion(50, workshop: false);
      expect(items.map((i) => i.value), contains(50));
    });

    test('la duración propia no se duplica si ya está en la lista', () {
      final items = itemsDuracion(60, workshop: false);
      expect(items.where((i) => i.value == 60).length, 1);
    });

    test('siempre hay una opción "Otra…" al final', () {
      final items = itemsDuracion(60, workshop: false);
      expect(items.last.value, kDuracionOtra);
    });

    test('workshop usa su propia escala', () {
      final items = itemsDuracion(120, workshop: true);
      expect(items.map((i) => i.value), contains(240));
      expect(items.map((i) => i.value), isNot(contains(45)));
    });

    test('las etiquetas se leen en horas cuando corresponde', () {
      expect(durLabel(50), '50 min');
      expect(durLabel(60), '1 h');
      expect(durLabel(90), '1 h 30 min');
      expect(durLabel(240), '4 h');
    });
  });
}
