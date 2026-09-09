// Dos bugs de visibilidad de Explorar (9/9/2026), con los datos reales de Rock.
//
// Lo que vio Sofía: cargó Rock Palermo y Recoleta —los dos de spinning— y al
// tocar el chip "Spinning" la tira de DESTACADOS salía vacía. Sólo aparecían
// tocando "Ver todo". Medido contra la base: ninguno tenía clases cargadas, y
// `destacadosDelDia` sólo tomaba estudios CON clases.
import 'dart:io';

import 'package:aura_app/models/estudio.dart';
import 'package:aura_app/utils/explorar_filtros.dart';
import 'package:flutter_test/flutter_test.dart';

/// Los estudios reales, como están en producción.
final rockPalermo = Estudio.fromMap({
  'id': 58,
  'nombre': 'Rock Studios Palermo',
  'categorias': ['Spinning', 'Pilates'],
  'activo': true,
});
final rockRecoleta = Estudio.fromMap({
  'id': 59,
  'nombre': 'Rock Studios Recoleta',
  'categorias': ['Spinning'],
  'activo': true,
});
final citra = Estudio.fromMap({
  'id': 4,
  'nombre': 'Citra Barre',
  'categorias': ['Barre'],
  'activo': true,
});

Map<String, dynamic> claseDe(Estudio e) => {
  'id': 1000 + (e.id ?? 0),
  'estudio_id': e.id,
  'estudios': {'id': e.id, 'nombre': e.nombre, 'categorias': e.categorias},
};

final hoy = DateTime(2026, 9, 9);

void main() {
  group('el chip de categoría muestra los estudios en DESTACADOS', () {
    test('con el chip Spinning, Rock aparece aunque no tenga clases', () {
      // El caso exacto de Sofía: los dos de Rock, cero clases cargadas.
      final d = destacadosDelDia(
        estudios: [rockPalermo, rockRecoleta],
        clases: const [],
        hoy: hoy,
      );
      expect(d.map((e) => e.id), containsAll([58, 59]));
    });

    test('antes del arreglo esto daba VACÍO', () {
      // Constancia de lo que se arregló: sin clases, la tira no mostraba nada
      // y Explorar decía "no encontramos resultados".
      final d = destacadosDelDia(
        estudios: [rockPalermo, rockRecoleta],
        clases: const [],
        hoy: hoy,
      );
      expect(d, isNotEmpty);
    });

    test('pero los que TIENEN clases siguen primero', () {
      // La regla vieja existía para no mandar a la alumna a un estudio sin
      // nada que reservar. Eso no se pierde: sólo cambia que los vacíos ahora
      // entran al final, si sobra lugar.
      final d = destacadosDelDia(
        estudios: [rockPalermo, rockRecoleta, citra],
        clases: [claseDe(citra)],
        hoy: hoy,
      );
      expect(d.first.id, 4, reason: 'Citra tiene clases: va primero');
      expect(d.map((e) => e.id), containsAll([58, 59]));
    });

    test('con la tira llena, los vacíos NO desplazan a los que tienen', () {
      final conClases = [
        for (var i = 1; i <= 4; i++)
          Estudio.fromMap({
            'id': i,
            'nombre': 'Estudio $i',
            'categorias': ['Yoga'],
            'activo': true,
          }),
      ];
      final d = destacadosDelDia(
        estudios: [...conClases, rockPalermo],
        clases: conClases.map(claseDe).toList(),
        hoy: hoy,
        max: 4,
      );
      expect(d.length, 4);
      expect(
        d.map((e) => e.id),
        isNot(contains(58)),
        reason: 'con 4 estudios con oferta, Rock no entra',
      );
    });
  });

  group('el detalle del estudio muestra TODAS sus categorías', () {
    final detalle = File(
      'lib/screens/estudios/detalle_estudio_screen.dart',
    ).readAsStringSync();

    test('ya no muestra sólo la primera', () {
      // Rock Palermo es Spinning Y Pilates: en su ficha parecía ser sólo
      // spinning.
      final plano = detalle.replaceAll(RegExp(r'\s+'), ' ');
      expect(plano.contains('child: Text( e.categoria,'), isFalse);
    });

    test('recorre el array completo', () {
      // El formateo puede partir el `for` en varias líneas, así que se busca
      // sin espacios.
      final plano = detalle.replaceAll(RegExp(r'\s+'), ' ');
      expect(plano, contains('for (final cat in (e.categorias.isEmpty'));
    });

    test('si el array viene vacío, cae al escalar y no rompe', () {
      expect(detalle, contains('e.categorias.isEmpty'));
    });

    test('las tarjetas de Explorar siguen mostrando UNA sola', () {
      // Ahí el badge va sobre la foto: con varias tapaba la imagen.
      final explorar = File(
        'lib/screens/explorar/explorar_screen.dart',
      ).readAsStringSync();
      expect(explorar, contains('categoriaPrincipal'));
    });
  });
}
