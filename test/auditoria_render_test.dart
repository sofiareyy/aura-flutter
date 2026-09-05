// Auditoría de render (4/9/2026): los widgets de la alumna que se pueden
// dibujar sin base, en cinco anchos, del teléfono más chico al escritorio.
// Cualquier desborde tira excepción y el test falla.
import 'package:aura_app/models/estudio.dart';
import 'package:aura_app/screens/explorar/explorar_screen.dart';
import 'package:aura_app/widgets/aura_skeleton.dart';
import 'package:aura_app/widgets/texto_expandible.dart';
import 'package:aura_app/widgets/titulo_seccion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const anchos = [320.0, 390.0, 430.0, 800.0, 1280.0];

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
  'id': 8,
  'nombre': 'Ambra Espacio Holístico',
  'barrio': 'Palermo',
  'direccion': 'Av Córdoba 5151, Buenos Aires, Argentina',
  'categorias': ['Yoga', 'Holistico / Bienestar'],
  'activo': true,
});

Future<void> pumpEn(WidgetTester tester, double ancho, Widget w) async {
  tester.view.physicalSize = Size(ancho, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: ancho, child: w),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() async => initializeDateFormatting('es'));

  final piezas = <String, Widget Function()>{
    'titulo corto': () => const TituloSeccion('MÁS CLASES', accion: 'Ver todas'),
    'titulo largo': () => const TituloSeccion(
          'UN TÍTULO DE SECCIÓN BASTANTE LARGO PARA PROBAR',
          accion: 'Ver todo',
          margenLateral: false,
        ),
    'tarjeta resultado': () => debugResultCard(clase: clase),
    'tarjeta compacta': () => debugResultCard(clase: clase, fotoCompacta: true),
    // El peor caso real: la categoría más larga de producción ("Holistico /
    // Bienestar") junto con "Tu estudio". Es el que desbordaba.
    'destacado, peor caso': () => SizedBox(
          height: 180,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              debugFeaturedExploreCard(
                estudio: Estudio.fromMap({
                  'id': 9,
                  'nombre': 'YN Pilates Studio',
                  'barrio': 'Pilar',
                  'direccion': 'Ruta 8 km 50',
                  'categorias': ['Holistico / Bienestar', 'Pilates'],
                  'activo': true,
                }),
                showBadge: true,
              ),
            ],
          ),
        ),
    'destacado': () => SizedBox(
          height: 180,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [debugFeaturedExploreCard(estudio: estudio, showBadge: true)],
          ),
        ),
    'texto expandible': () => TextoExpandible('Un espacio de yoga en Pilar. ' * 30),
    'esqueleto': () => const AuraSkeletonCarrusel(alto: 180, anchoTarjeta: 166, altoFoto: 92),
  };

  for (final a in anchos) {
    for (final e in piezas.entries) {
      testWidgets('${e.key} a $a px', (tester) async {
        await pumpEn(tester, a, e.value());
        expect(tester.takeException(), isNull, reason: '${e.key} desbordó a $a px');
      });
    }
  }
}
