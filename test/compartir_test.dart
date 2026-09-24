// El texto que se comparte de una clase, y el link del mapa.
import 'package:aura_app/utils/compartir.dart';
import 'package:aura_app/utils/mapa_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('texto de compartir una clase', () {
    test('con estudio y horario', () {
      expect(
        textoCompartirClase(
          nombre: 'Barre Consciente',
          estudio: 'Citra Barre',
          cuando: 'viernes 19 de septiembre a las 21:00',
          link: 'https://somosaurapass.com/#/clase/2478',
        ),
        'Barre Consciente en Citra Barre\n'
        'viernes 19 de septiembre a las 21:00\n'
        'Reservá en Aura 🧡\n'
        'https://somosaurapass.com/#/clase/2478',
      );
    });

    test('sin estudio no deja el "en" colgado', () {
      final t = textoCompartirClase(
          nombre: 'Pilates', estudio: '  ', link: 'https://x');
      // La primera línea es el nombre solo. (Ojo: no sirve buscar " en " en
      // todo el texto, porque "Reservá en Aura" lo tiene.)
      expect(t.split('\n').first, 'Pilates');
    });

    test('sin horario no deja una línea vacía', () {
      final t = textoCompartirClase(
          nombre: 'Pilates', estudio: 'YN', cuando: null, link: 'https://x');
      expect(t.split('\n').length, 3);
      expect(t.contains('\n\n'), isFalse);
    });

    test('el link siempre va último: es lo que se pega', () {
      final t = textoCompartirClase(nombre: 'X', link: 'https://somosaurapass.com/#/clase/9');
      expect(t.split('\n').last, 'https://somosaurapass.com/#/clase/9');
    });
  });

  group('link del mapa (bug 3: sin coordenadas también tiene que servir)', () {
    test('con coordenadas usa el destino exacto', () {
      expect(mapaUrl(direccion: 'Cabrera 5100', lat: -34.58, lng: -58.43),
          'https://www.google.com/maps/dir/?api=1&destination=-34.58,-58.43');
    });

    test('sin coordenadas busca por dirección', () {
      expect(mapaUrl(direccion: 'Cabrera 5100, Palermo'),
          'https://www.google.com/maps/search/?api=1&query=Cabrera%205100%2C%20Palermo');
    });

    test('coordenadas en 0,0 no cuentan (es el defecto de la base)', () {
      expect(mapaUrl(direccion: 'Cabrera 5100', lat: 0, lng: 0),
          contains('search'));
    });
  });

  group('texto de compartir un estudio', () {
    test('con barrio', () {
      expect(
        textoCompartirEstudio(
          nombre: 'YOYO Yoga Studio',
          barrio: 'Palermo',
          link: 'https://somosaurapass.com/#/estudio/12',
        ),
        'YOYO Yoga Studio (Palermo)\n'
        'Mirá sus clases en Aura 🧡\n'
        'https://somosaurapass.com/#/estudio/12',
      );
    });

    test('sin barrio no deja el paréntesis vacío', () {
      final t = textoCompartirEstudio(
        nombre: 'Citra Barre',
        link: 'https://somosaurapass.com/#/estudio/3',
      );
      expect(t.contains('('), isFalse);
      expect(t.split('\n').first, 'Citra Barre');
    });

    test('barrio en blanco se trata como ausente', () {
      final t = textoCompartirEstudio(
        nombre: 'Citra Barre',
        barrio: '   ',
        link: 'https://somosaurapass.com/#/estudio/3',
      );
      expect(t.split('\n').first, 'Citra Barre');
    });
  });
}
