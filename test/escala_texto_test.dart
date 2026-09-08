// Accesibilidad: la app con la letra del sistema agrandada (9/9/2026).
//
// El caso real: la mamá de Sofía usa la letra grande y la app se rompía. Medido
// antes del arreglo, la tarjeta de clase desbordaba desde x1.05 — el primer
// clic de "letra más grande".
//
// Estos tests renderizan los widgets REALES a cada escala y exigen que nada
// desborde hasta el tope de 1,5x.
import 'package:aura_app/models/estudio.dart';
import 'package:aura_app/screens/explorar/explorar_screen.dart';
import 'package:aura_app/widgets/escala_texto.dart';
import 'package:aura_app/widgets/texto_expandible.dart';
import 'package:aura_app/widgets/titulo_seccion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// El peor texto real de producción.
final clase = <String, dynamic>{
  'id': 1,
  'nombre': 'Yin Yoga + Mindfulness',
  'creditos': 18,
  'tipo': 'clase',
  'tipo_precio': 'normal',
  'fecha': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
  'estudios': {
    'id': 8,
    'nombre': 'Ambra Espacio Holístico',
    'barrio': 'Palermo',
    'direccion': 'Colectora Panamericana avenida 12 de octubre, Felix De '
        'Olazabal 1141, B1629 Buenos Aires, Provincia de Buenos Aires',
    'categorias': ['Yoga', 'Holistico / Bienestar'],
    'creditos_min': 11,
    'creditos_max': 18,
    'foto_url': null,
  },
};

final estudio = Estudio.fromMap({
  'id': 9,
  'nombre': 'YN Pilates Studio',
  'barrio': 'Pilar',
  'direccion': 'Ruta 8 km 50',
  'categorias': ['Holistico / Bienestar', 'Pilates'],
  'activo': true,
});

/// Las escalas que importan: normal, la que usa la mayoría, y el tope.
const escalas = [1.0, 1.15, 1.3, 1.5];

void main() {
  setUpAll(() async => initializeDateFormatting('es'));

  group('el tope', () {
    testWidgets('con la letra en normal NO cambia nada', (t) async {
      await t.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.0)),
          child: MaterialApp(
            home: EscalaTextoAcotada(
              child: Builder(
                builder: (c) => Text('${MediaQuery.of(c).textScaler.scale(10)}'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('10.0'), findsOneWidget);
    });

    testWidgets('respeta el ajuste POR DEBAJO del tope', (t) async {
      await t.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: MaterialApp(
            home: EscalaTextoAcotada(
              child: Builder(
                builder: (c) => Text('${MediaQuery.of(c).textScaler.scale(10)}'),
              ),
            ),
          ),
        ),
      );
      // 1.3 pasa tal cual: la letra crece, que es lo que la usuaria pidió.
      expect(find.text('13.0'), findsOneWidget);
    });

    testWidgets('con el máximo de iOS (3.1x) lo baja a 1.5x', (t) async {
      await t.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(3.1)),
          child: MaterialApp(
            home: EscalaTextoAcotada(
              child: Builder(
                builder: (c) => Text('${MediaQuery.of(c).textScaler.scale(10)}'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('15.0'), findsOneWidget);
    });
  });

  group('nada se desborda hasta el tope', () {
    final piezas = <String, Widget Function()>{
      'tarjeta de clase': () => debugResultCard(clase: clase),
      'tarjeta de experiencia': () =>
          debugResultCard(clase: clase, fotoCompacta: true),
      'tarjeta de estudio': () => SizedBox(
        height: 180,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            debugFeaturedExploreCard(estudio: estudio, showBadge: true),
          ],
        ),
      ),
      'título de sección': () =>
          const TituloSeccion('MÁS CLASES', accion: 'Ver todas'),
      'descripción larga': () =>
          TextoExpandible('Un espacio de yoga en Pilar. ' * 30),
    };

    for (final escala in escalas) {
      for (final e in piezas.entries) {
        testWidgets('${e.key} @ x$escala', (t) async {
          t.view.physicalSize = const Size(390, 2400);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          await t.pumpWidget(
            MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(escala)),
              child: MaterialApp(
                home: EscalaTextoAcotada(
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: SizedBox(width: 350, child: e.value()),
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.pump();
          expect(
            t.takeException(),
            isNull,
            reason: '${e.key} se rompe con la letra a x$escala',
          );
        });
      }
    }
  });

  group('las pantallas más cargadas de texto', () {
    // Cobros y el detalle de clase no se pueden levantar enteras sin base,
    // pero sus piezas de texto sí: son las que se cortaban.
    final piezas = <String, Widget Function()>{
      'fila de cobros (mes · reservas · monto · estado)': () => Row(
        children: const [
          Expanded(child: Text('Septiembre 2026')),
          SizedBox(
            width: 80,
            child: Text('3', textAlign: TextAlign.center),
          ),
          SizedBox(
            width: 120,
            child: Text('\$54.000', textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 90,
            child: Text('A cobrar el 5', textAlign: TextAlign.center),
          ),
        ],
      ),
      'encabezado con acción larga': () => const TituloSeccion(
        'TODOS LOS RESULTADOS',
        accion: 'Ver todas',
        margenLateral: false,
      ),
      'descripción del estudio más larga de producción': () =>
          TextoExpandible('Somos un espacio de yoga en Pilar. ' * 28),
    };

    for (final escala in escalas) {
      for (final e in piezas.entries) {
        testWidgets('${e.key} @ x$escala', (t) async {
          t.view.physicalSize = const Size(390, 2400);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          await t.pumpWidget(
            MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(escala)),
              child: MaterialApp(
                home: EscalaTextoAcotada(
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: SizedBox(width: 350, child: e.value()),
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.pump();
          expect(t.takeException(), isNull, reason: '${e.key} @ x$escala');
        });
      }
    }
  });
}
