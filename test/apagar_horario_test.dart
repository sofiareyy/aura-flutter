// Apagar "Genera clases nuevas" en un horario fijo.
//
// El bug que cierra (9/9/2026): el switch escribía `activo = false` y nada más.
// El horario dejaba de generar clases nuevas —los dos generadores, el de Dart y
// el `generar_clases_estudio` del cron, saltan los inactivos— pero las clases
// que ya había generado quedaban publicadas y reservables. El estudio creía
// haber apagado algo que seguía vivo del lado de la alumna.
//
// Apareció en YN Pilates: el horario del miércoles 11:00 estaba apagado con 8
// clases futuras vivas, así que el backoffice mostraba un solo día activo y la
// app ofrecía dos.
//
// Los textos los redactó Sofía palabra por palabra: son el momento en que un
// estudio decide si una alumna pierde su clase. Estos tests los fijan.
import 'package:aura_app/utils/textos_apagar_horario.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('el nombre del switch dice qué hace, no un estado', () {
    test('se llama "Genera clases nuevas"', () {
      expect(kLabelGeneraClases, 'Genera clases nuevas');
    });

    test('ni el nombre ni el tooltip hablan de "activo" ni de "baja"', () {
      // "Activo" hacía creer que apagarlo daba de baja lo ya publicado.
      for (final t in [kLabelGeneraClases, kHorarioNoGenera]) {
        expect(t.toLowerCase(), isNot(contains('activo')));
        expect(t.toLowerCase(), isNot(contains('baja')));
      }
    });

    test('el tooltip aclara justo el malentendido', () {
      expect(kTooltipGeneraClases, contains('no da de baja'));
      expect(kTooltipGeneraClases, contains('ya están publicadas'));
    });
  });

  group('el cuerpo del diálogo (caso real de YN: 8 clases, miércoles 11)', () {
    final texto = cuerpoApagarHorario(
      n: 8,
      dia: 'Miércoles',
      hora: '11:00',
      primera: '16/9',
      ultima: '4/11',
    );

    test('sale palabra por palabra como lo escribió Sofía', () {
      expect(
        texto,
        'Este horario tiene 8 clases publicadas, del 16/9 al 4/11. Están '
        'visibles en la app y se pueden reservar ahora mismo. De acá en '
        'adelante no se generan clases nuevas para el Miércoles a las 11:00, '
        'elijas lo que elijas.',
      );
    });

    test('dice que se pueden reservar AHORA: es el punto del aviso', () {
      expect(texto, contains('se pueden reservar ahora mismo'));
    });

    test('aclara que el horario deja de generar en los dos caminos', () {
      // Sin esto, elegir "dejarlas publicadas" se lee como "no hice nada".
      expect(texto, contains('elijas lo que elijas'));
    });

    test('con una sola clase concuerda en singular', () {
      expect(
        cuerpoApagarHorario(
          n: 1,
          dia: 'Viernes',
          hora: '11:00',
          primera: '11/9',
          ultima: '11/9',
        ),
        'Este horario tiene 1 clase publicada, del 11/9 al 11/9. Está visible '
        'en la app y se puede reservar ahora mismo. De acá en adelante no se '
        'generan clases nuevas para el Viernes a las 11:00, elijas lo que '
        'elijas.',
      );
    });
  });

  group('la advertencia de reservas', () {
    test('con varias alumnas', () {
      expect(
        advertenciaReservas(3),
        '3 alumnas ya reservaron estas clases. Si las despublicás, se '
        'cancelan: les devolvemos los créditos y les llega un mail avisando, '
        'pero se quedan sin la clase.',
      );
    });

    test('con una sola concuerda en singular', () {
      expect(
        advertenciaReservas(1),
        '1 alumna ya reservó estas clases. Si las despublicás, se cancelan: le '
        'devolvemos los créditos y le llega un mail avisando, pero se queda '
        'sin la clase.',
      );
    });

    test('nunca omite que la alumna se queda sin la clase', () {
      // Es el pedazo que no puede faltar: los créditos no reemplazan la clase.
      for (final x in [1, 2, 17]) {
        expect(advertenciaReservas(x), contains('sin la clase'));
        expect(advertenciaReservas(x), contains('mail'));
        expect(advertenciaReservas(x), contains('créditos'));
      }
    });
  });

  group('los botones', () {
    test('sin reservas, el destructivo dice cuántas clases', () {
      expect(botonDespublicar(n: 8, x: 0), 'Despublicar las 8');
    });

    test('con reservas, nombra el costo real', () {
      expect(botonDespublicar(n: 8, x: 3), 'Despublicar y cancelar 3 reservas');
      expect(botonDespublicar(n: 8, x: 1), 'Despublicar y cancelar 1 reserva');
    });

    test('el conservador es "Dejarlas publicadas"', () {
      expect(kBotonDejarPublicadas, 'Dejarlas publicadas');
    });

    test('ningún botón dice "eliminar" ni "dar de baja"', () {
      // Decisión de redacción de Sofía: despublicar dice lo que pasa.
      final botones = [
        botonDespublicar(n: 8, x: 0),
        botonDespublicar(n: 8, x: 3),
        kBotonDejarPublicadas,
      ];
      for (final b in botones) {
        expect(b.toLowerCase(), isNot(contains('eliminar')));
        expect(b.toLowerCase(), isNot(contains('dar de baja')));
        expect(b.toLowerCase(), isNot(contains('borrar')));
      }
    });
  });

  group('las confirmaciones', () {
    test('apagar sin despublicar nada', () {
      expect(
        kApagadoSinDespublicar,
        'Listo. Este horario no genera más clases nuevas.',
      );
    });

    test('despublicar sin reservas', () {
      expect(
        confirmacionDespublicado(n: 8, alumnas: 0),
        'Listo. Despublicamos 8 clases y este horario no genera más clases '
        'nuevas.',
      );
    });

    test('despublicar con reservas cuenta las alumnas y el mail', () {
      expect(
        confirmacionDespublicado(n: 8, alumnas: 3),
        'Listo. Despublicamos 8 clases y les devolvimos los créditos a 3 '
        'alumnas. Ya les llegó el mail.',
      );
    });

    test('con una sola alumna concuerda', () {
      expect(
        confirmacionDespublicado(n: 1, alumnas: 1),
        'Listo. Despublicamos 1 clase y les devolvimos los créditos a 1 '
        'alumna. Ya les llegó el mail.',
      );
    });
  });

  group('cuando alguna clase no se pudo despublicar', () {
    test('el título y el cuerpo dicen que el horario quedó PRENDIDO', () {
      expect(kTituloFallidas, 'Quedaron clases sin despublicar');
      final texto = cuerpoFallidas(despublicadas: 6, fallidas: 2);
      expect(
        texto,
        'Se despublicaron 6 clases, pero 2 no se pudieron dar de baja. El '
        'horario quedó prendido para que puedas revisarlas.',
      );
      // Lo central: el trabajo no terminó y el estudio tiene que verlo.
      expect(texto, contains('quedó prendido'));
    });

    test('con una sola fallida concuerda', () {
      expect(
        cuerpoFallidas(despublicadas: 7, fallidas: 1),
        'Se despublicaron 7 clases, pero 1 no se pudo dar de baja. El horario '
        'quedó prendido para que puedas revisarlas.',
      );
    });
  });
}
