import 'package:flutter_test/flutter_test.dart';
import 'package:aura_app/services/analytics/embudo.dart';

void main() {
  group('pasoDeRuta', () {
    test('clases: Explorar, la ficha de una clase y la de un estudio', () {
      expect(Embudo.pasoDeRuta('/explorar'), 'ver_clases');
      expect(Embudo.pasoDeRuta('/clase/12'), 'ver_clases');
      expect(Embudo.pasoDeRuta('/estudio/4'), 'ver_clases');
      expect(Embudo.pasoDeRuta('/estudio/4/resenas'), 'ver_clases');
    });

    test('packs', () {
      expect(Embudo.pasoDeRuta('/comprar-creditos'), 'ver_packs');
    });

    test('el panel del estudio y el resto no son pasos', () {
      expect(Embudo.pasoDeRuta('/estudio/clases'), isNull);
      expect(Embudo.pasoDeRuta('/estudio/cobros'), isNull);
      expect(Embudo.pasoDeRuta('/home'), isNull);
      expect(Embudo.pasoDeRuta('/mis-creditos'), isNull);
    });
  });

  group('esCuentaNueva (vuelta de Google / Apple)', () {
    final ahora = DateTime.utc(2026, 11, 5, 15);
    test('creada hace 2 minutos: es un registro', () {
      expect(Embudo.esCuentaNueva('2026-11-05T14:58:00Z', ahora: ahora), isTrue);
    });
    test('creada hace un día: es un login', () {
      expect(Embudo.esCuentaNueva('2026-11-04T15:00:00Z', ahora: ahora), isFalse);
    });
    test('sin fecha: no cuenta', () {
      expect(Embudo.esCuentaNueva(null, ahora: ahora), isFalse);
      expect(Embudo.esCuentaNueva('x', ahora: ahora), isFalse);
    });
  });
}
