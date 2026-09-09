// Los textos de "Mis créditos" (9/9/2026).
//
// Reemplazan al "Este mes ahorraste $X", que se calculaba contra una tabla de
// precios de mercado escrita a mano y sin fuente. Los casos son los de las
// cuentas REALES: las dos únicas alumnas que reservaron lo hicieron en un solo
// estudio, y ese es justo el caso que no hay que exponer.
import 'dart:io';

import 'package:aura_app/utils/resumen_creditos.dart';
import 'package:flutter_test/flutter_test.dart';

/// Los créditos de las clases cargadas hoy.
const preciosReales = [11, 13, 14, 18];

void main() {
  group('lo que puede hacer con su saldo', () {
    test('24 créditos: alcanza para 1 o 2', () {
      expect(
        textoSaldo(creditos: 24, preciosDeClase: preciosReales),
        'Te alcanza para entre 1 y 2 clases',
      );
    });

    test('18 créditos: exactamente una, dicho cálido', () {
      expect(
        textoSaldo(creditos: 18, preciosDeClase: preciosReales),
        'Te alcanza para una clase',
      );
    });

    test('sin saldo, no dice nada (va el estado vacío)', () {
      expect(textoSaldo(creditos: 0, preciosDeClase: preciosReales), isNull);
    });

    test('con saldo que no alcanza, dice cuánto le falta', () {
      // El caso real de malekuipers: 4 créditos, clases desde 11.
      expect(
        textoSaldo(creditos: 4, preciosDeClase: preciosReales),
        'Te faltan 7 créditos para tu próxima clase',
      );
    });

    test('si le falta uno solo, en singular', () {
      expect(
        textoSaldo(creditos: 10, preciosDeClase: preciosReales),
        'Te falta 1 crédito para tu próxima clase',
      );
    });

    test('sin precios cargados NO inventa un rango', () {
      expect(textoSaldo(creditos: 50, preciosDeClase: const []), isNull);
    });
  });

  group('la oferta disponible', () {
    test('con 15 estudios lo dice', () {
      expect(textoOferta(estudiosActivos: 15), 'Elegí entre 15 estudios');
    });

    test('con uno solo se calla', () {
      expect(textoOferta(estudiosActivos: 1), isNull);
    });

    test('si no se pudo contar, se calla', () {
      expect(textoOferta(estudiosActivos: null), isNull);
    });
  });

  group('el recorrido histórico', () {
    test('malekuipers: 3 clases en 1 estudio → NO menciona el estudio', () {
      // El caso real. Decir "en 1 estudio" le diría en la cara que fue a un
      // solo lugar, que es lo contrario de lo que se quiere comunicar.
      expect(
        textoRecorrido(clases: 3, estudios: 1),
        'Llevás 3 clases con Aura',
      );
    });

    test('juanita: 1 clase, en singular', () {
      expect(textoRecorrido(clases: 1, estudios: 1), 'Llevás 1 clase con Aura');
    });

    test('con 2 estudios o más, ahí SÍ lo dice', () {
      expect(
        textoRecorrido(clases: 5, estudios: 3),
        'Llevás 5 clases en 3 estudios',
      );
      expect(
        textoRecorrido(clases: 2, estudios: 2),
        'Llevás 2 clases en 2 estudios',
      );
    });

    test('sin clases, no hay recorrido', () {
      expect(textoRecorrido(clases: 0, estudios: 0), isNull);
    });
  });

  group('la que nunca reservó', () {
    test('con créditos, se le recuerda que los tiene', () {
      final t = textoSinReservas(creditos: 24);
      expect(t.titulo, 'Reservá tu primera clase');
      expect(t.bajada, 'Tenés 24 créditos esperando');
    });

    test('con uno solo, en singular', () {
      expect(textoSinReservas(creditos: 1).bajada, 'Tenés 1 crédito esperando');
    });

    test('sin créditos, sólo la invitación', () {
      expect(textoSinReservas(creditos: 0).bajada, isNull);
    });
  });

  test('en ningún texto aparece un precio en pesos', () {
    // La razón de ser de este archivo: se acabaron los números de mercado
    // inventados.
    final todos = [
      textoSaldo(creditos: 24, preciosDeClase: preciosReales),
      textoOferta(estudiosActivos: 15),
      textoRecorrido(clases: 5, estudios: 3),
      textoSinReservas(creditos: 24).bajada,
    ].whereType<String>();
    for (final t in todos) {
      expect(t.contains(r'$'), isFalse, reason: t);
    }
  });

  group('la coherencia con el paywall', () {
    final pantalla = File(
      'lib/screens/creditos/mis_creditos_screen.dart',
    ).readAsStringSync();

    test('la tabla de precios inventados ya no existe', () {
      // Decía yoga $30.000 / pilates $20.000 / gym $12.000, sin fuente ni
      // fecha, y sobreestimaba ~50% contra los precios reales.
      expect(pantalla.contains('_preciosMercado'), isFalse);
      expect(pantalla.contains('30000'), isFalse);
      expect(pantalla.contains('12000'), isFalse);
    });

    test('ni las funciones que la usaban', () {
      for (final f in ['_precioMercadoPara', '_ahorroPor', '_totalAhorro']) {
        expect(pantalla.contains('$f('), isFalse, reason: f);
      }
    });

    test('no queda ningún monto en pesos en la pantalla', () {
      // Si sacamos el ahorro inventado del paywall, no tiene sentido dejarlo
      // acá: es la misma decisión.
      // El comentario que documenta POR QUÉ se sacó sí puede nombrarlo; lo
      // que no puede quedar es un texto que se le muestre a la usuaria.
      final codigo = pantalla
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(codigo.contains('ahorraste'), isFalse);
      expect(codigo.contains('ahorrado'), isFalse);
    });
  });
}
