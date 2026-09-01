// El link de mapa que se abre al tocar una dirección. Mismo criterio que el
// mail de confirmación: si hay coordenadas, mandan; si no, se busca el texto.
import 'package:aura_app/utils/mapa_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('con coordenadas usa lat/lng (exacto, no depende de la calle)', () {
    expect(
      mapaUrl(direccion: 'Malabia 1510', lat: -34.5889, lng: -58.4331),
      'https://www.google.com/maps/dir/?api=1&destination=-34.5889,-58.4331',
    );
  });

  test('sin coordenadas busca por texto, escapado', () {
    expect(
      mapaUrl(direccion: 'Defensa 1234, San Telmo'),
      'https://www.google.com/maps/search/?api=1'
      '&query=Defensa%201234%2C%20San%20Telmo',
    );
  });

  test('lat/lng en 0,0 no cuentan: cae a la búsqueda por texto', () {
    // 0,0 es el Golfo de Guinea. Un estudio sin geocodificar suele quedar así
    // y mandaría a la gente al Atlántico.
    expect(mapaUrl(direccion: 'Malabia 1510', lat: 0, lng: 0),
        contains('search/?api=1'));
  });

  test('sin dirección ni coordenadas no abre nada', () async {
    expect(await abrirMapa(), isFalse);
    expect(await abrirMapa(direccion: '   '), isFalse);
  });
}
