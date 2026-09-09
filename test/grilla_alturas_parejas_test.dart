// La grilla de "TODOS LOS RESULTADOS" con portadas de distinta proporción.
//
// **El bug que atrapa** (9/9/2026): la tarjeta pasó de alto FIJO a
// `minHeight` + `IntrinsicHeight`, para que creciera con la letra del sistema.
// Pero `IntrinsicHeight` mide el alto NATURAL de sus hijos, y una imagen ya
// cargada reporta el alto que le toca por la proporción del archivo. Con las
// portadas reales —de 1290×716 a 900×1600— cada tarjeta medía distinto, de 124
// a 331 px, y la grilla de dos columnas quedaba escalonada con huecos.
//
// **Por qué el test viejo no lo vio, y cómo se resuelve acá.** En un test las
// imágenes no se descargan: el placeholder no tiene alto intrínseco y todas las
// tarjetas medían igual. Intenté servir PNG reales con `HttpOverrides`, pero
// `FotoRed` usa caché en disco (cached_network_image → sqflite + path_provider)
// y eso no corre en un test. Así que el bug se ataca por donde de verdad vive:
//
//  1. `alturaSegunProporcion` reproduce la ESTRUCTURA de la tarjeta con un hijo
//     que sí tiene alto intrínseco (`AspectRatio`, que es justo lo que reporta
//     una `Image` cargada) y exige que el alto NO dependa de la proporción.
//  2. Un test estructural sobre el código, que falla si alguien vuelve a poner
//     `IntrinsicHeight` o a sacar el alto fijo.
import 'dart:io';

import 'package:aura_app/utils/grilla_responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Las proporciones REALES de las portadas cargadas en producción.
const portadas = {
  'Yoguica 1290×716': 1290 / 716, // 1,80 — la más horizontal
  'Citra 1290×910': 1290 / 910, // 1,42
  'Tiwar 1024×1024': 1.0, // cuadrada (un logo)
  'YN Pilates 960×1280': 960 / 1280, // 0,75 — vertical
  'Yessi 900×1600': 900 / 1600, // 0,56 — la más vertical
};

/// La estructura de `_ResultCard`: alto fijo, Row con `stretch`, foto de ancho
/// fijo a la izquierda y texto a la derecha. El `AspectRatio` ocupa el lugar de
/// la imagen y aporta el alto intrínseco de su proporción, igual que una
/// `Image` ya decodificada.
Widget tarjeta({required double proporcion, required double alto}) => SizedBox(
  height: alto,
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        width: anchoFotoBuscador(530),
        child: AspectRatio(aspectRatio: proporcion),
      ),
      const Expanded(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('VIE 5 · 11:00'),
              Text('Clase pilates'),
              Text('Estudio'),
            ],
          ),
        ),
      ),
    ],
  ),
);

Future<double> alturaSegunProporcion(WidgetTester t, double proporcion) async {
  t.view.physicalSize = const Size(1400, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 530,
              child: Container(
                key: const Key('k'),
                child: tarjeta(
                  proporcion: proporcion,
                  alto: altoCardBuscador(530),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pump();
  return t.getSize(find.byKey(const Key('k'))).height;
}

void main() {
  testWidgets('todas las portadas dan la MISMA altura de tarjeta', (t) async {
    final medidas = <String, double>{};
    for (final p in portadas.entries) {
      medidas[p.key] = await alturaSegunProporcion(t, p.value);
    }
    final distintas = medidas.values.toSet();
    expect(
      distintas.length,
      1,
      reason:
          'la proporción de la portada cambia el alto de la tarjeta y la '
          'grilla queda escalonada: $medidas',
    );
    // Y es el alto de diseño, no uno cualquiera.
    expect(distintas.single, altoCardBuscador(530));
  });

  testWidgets('la más vertical no estira la tarjeta', (t) async {
    // El caso de la captura: Yessi (900×1600) hacía una tarjeta de 331 px al
    // lado de una de 124.
    final yessi = await alturaSegunProporcion(t, 900 / 1600);
    final yoguica = await alturaSegunProporcion(t, 1290 / 716);
    expect(yessi, yoguica);
    expect(yessi, lessThan(200));
  });

  test('la tarjeta usa alto FIJO escalado, no IntrinsicHeight', () {
    // Defensa estructural: si alguien vuelve a poner minHeight +
    // IntrinsicHeight buscando la accesibilidad, el escalonado vuelve. La
    // forma correcta es escalar el alto fijo por la letra del sistema.
    final fuente = File(
      'lib/screens/explorar/explorar_screen.dart',
    ).readAsStringSync();
    final cuerpo = fuente
        .substring(fuente.indexOf('class _ResultCard'))
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(
      cuerpo.contains('IntrinsicHeight'),
      isFalse,
      reason: 'IntrinsicHeight deja que la foto mande la altura',
    );
    expect(cuerpo, contains('height: altoCard'));
    expect(
      cuerpo,
      contains('conEscalaDeTexto'),
      reason: 'el alto tiene que seguir creciendo con la letra del sistema',
    );
  });
}
