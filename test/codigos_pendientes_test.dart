// Los códigos (gift card y referido) de un registro que quedó SIN sesión.
//
// El agujero (10/9/2026): `_register()` canjeaba el regalo y vinculaba el
// referido DESPUÉS del `return` de la rama "revisá tu mail". Con la validación
// de mail apagada nunca se notó; el día que se prenda, los dos códigos se
// perderían en silencio. Se guardan atados al mail y los consume el primer
// login que funcione.
//
// La propiedad que importa: el código NUNCA puede terminar acreditado en la
// cuenta de otra persona que entre después en el mismo dispositivo.
import 'package:aura_app/utils/codigos_pendientes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ida y vuelta: lo que se escribió al registrarse llega al login', () {
    test('guarda los dos códigos y los devuelve para el mismo mail', () async {
      final guardo = await CodigosPendientes.recordar(
        mail: 'vale@gmail.com',
        regalo: 'GIFT-ABCD1234',
        referido: 'AMIGA123',
      );
      expect(guardo, isTrue);
      final c = await CodigosPendientes.tomar('vale@gmail.com');
      expect(c, isNotNull);
      expect(c!.regalo, 'GIFT-ABCD1234');
      expect(c.referido, 'AMIGA123');
    });

    test('sólo regalo: el referido viene null', () async {
      await CodigosPendientes.recordar(
        mail: 'vale@gmail.com',
        regalo: 'GIFT-ABCD1234',
      );
      final c = await CodigosPendientes.tomar('vale@gmail.com');
      expect(c!.regalo, 'GIFT-ABCD1234');
      expect(c.referido, isNull);
    });

    test('sólo referido: el regalo viene null', () async {
      await CodigosPendientes.recordar(
        mail: 'vale@gmail.com',
        referido: 'AMIGA123',
      );
      final c = await CodigosPendientes.tomar('vale@gmail.com');
      expect(c!.regalo, isNull);
      expect(c.referido, 'AMIGA123');
    });
  });

  group('es de un solo uso', () {
    test('el segundo consumo devuelve vacío', () async {
      await CodigosPendientes.recordar(
        mail: 'vale@gmail.com',
        regalo: 'GIFT-ABCD1234',
        referido: 'AMIGA123',
      );
      expect(await CodigosPendientes.tomar('vale@gmail.com'), isNotNull);
      expect(await CodigosPendientes.tomar('vale@gmail.com'), isNull);
    });
  });

  group('EL CÓDIGO NO PUEDE IR A LA CUENTA EQUIVOCADA', () {
    test('otro mail en la sesión ⇒ se descarta sin aplicar', () async {
      await CodigosPendientes.recordar(
        mail: 'vale@gmail.com',
        regalo: 'GIFT-ABCD1234',
        referido: 'AMIGA123',
      );
      expect(await CodigosPendientes.tomar('otra@gmail.com'), isNull);
    });

    test('descartado es descartado: tampoco queda esperando al mail correcto',
        () async {
      // Si sobreviviera, un tercero podría "reservarle" un canje a alguien
      // que ni sabe que existe ese código. Se borra en el primer intento.
      await CodigosPendientes.recordar(
        mail: 'vale@gmail.com',
        regalo: 'GIFT-ABCD1234',
      );
      await CodigosPendientes.tomar('otra@gmail.com');
      expect(await CodigosPendientes.tomar('vale@gmail.com'), isNull);
    });

    test('sesión sin mail (Apple con mail oculto) ⇒ se descarta', () async {
      await CodigosPendientes.recordar(
        mail: 'vale@gmail.com',
        regalo: 'GIFT-ABCD1234',
      );
      expect(await CodigosPendientes.tomar(null), isNull);
      await CodigosPendientes.recordar(
        mail: 'vale@gmail.com',
        regalo: 'GIFT-ABCD1234',
      );
      expect(await CodigosPendientes.tomar(''), isNull);
    });
  });

  group('sin nada que guardar no guarda nada', () {
    test('campos vacíos ⇒ recordar devuelve false y tomar da vacío', () async {
      expect(
        await CodigosPendientes.recordar(mail: 'vale@gmail.com'),
        isFalse,
      );
      expect(await CodigosPendientes.tomar('vale@gmail.com'), isNull);
      expect(
        await CodigosPendientes.recordar(
          mail: 'vale@gmail.com',
          regalo: '   ',
          referido: '',
        ),
        isFalse,
      );
      expect(await CodigosPendientes.tomar('vale@gmail.com'), isNull);
    });

    test('sin mail no hay contra qué comparar ⇒ no se guarda', () async {
      expect(
        await CodigosPendientes.recordar(mail: null, regalo: 'GIFT-ABCD1234'),
        isFalse,
      );
      expect(
        await CodigosPendientes.recordar(mail: '  ', regalo: 'GIFT-ABCD1234'),
        isFalse,
      );
      expect(await CodigosPendientes.tomar(''), isNull);
      expect(await CodigosPendientes.tomar(null), isNull);
    });

    test('un registro nuevo sin códigos borra los del intento anterior',
        () async {
      await CodigosPendientes.recordar(
        mail: 'vale@gmail.com',
        regalo: 'GIFT-ABCD1234',
      );
      await CodigosPendientes.recordar(mail: 'vale@gmail.com');
      expect(await CodigosPendientes.tomar('vale@gmail.com'), isNull);
    });

    test('guardar de nuevo pisa, no acumula', () async {
      await CodigosPendientes.recordar(
        mail: 'vale@gmail.com',
        regalo: 'GIFT-VIEJO0000',
        referido: 'VIEJA000',
      );
      await CodigosPendientes.recordar(
        mail: 'vale@gmail.com',
        referido: 'NUEVA000',
      );
      final c = await CodigosPendientes.tomar('vale@gmail.com');
      expect(c!.regalo, isNull, reason: 'el regalo viejo no puede sobrevivir');
      expect(c.referido, 'NUEVA000');
    });
  });

  group('trim y normalización', () {
    test('el mail se compara sin espacios ni mayúsculas', () async {
      await CodigosPendientes.recordar(
        mail: '  Vale@Gmail.com ',
        regalo: 'GIFT-ABCD1234',
      );
      expect(await CodigosPendientes.tomar('VALE@GMAIL.COM'), isNotNull);
    });

    test('los códigos salen sin espacios alrededor', () async {
      await CodigosPendientes.recordar(
        mail: 'vale@gmail.com',
        regalo: '  GIFT-ABCD1234 ',
        referido: ' AMIGA123\n',
      );
      final c = await CodigosPendientes.tomar('vale@gmail.com');
      expect(c!.regalo, 'GIFT-ABCD1234');
      expect(c.referido, 'AMIGA123');
    });

    test('normalizarMail', () {
      expect(CodigosPendientes.normalizarMail('  Vale@Gmail.com '),
          'vale@gmail.com');
      expect(CodigosPendientes.normalizarMail(null), '');
      expect(CodigosPendientes.normalizarMail('   '), '');
    });
  });
}
