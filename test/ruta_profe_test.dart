// Qué puede abrir una profe y qué no (10/10/2026).
//
// Existe porque es la SEGUNDA vez que este guard rompe uso legítimo. El 20/8
// fueron los guards de la grilla, validados sólo contra el exploit: de 5 usos
// buenos rompieron 2. Acá el gate era `loc.startsWith('/estudio')`, que
// también es el prefijo de la ficha PÚBLICA de un estudio, así que una profe
// logueada no podía abrir el perfil de ninguno —ni el del estudio donde da
// clases—, algo que cualquier invitada sin cuenta sí podía hacer.
//
// La regla que fija este test: se veda el PANEL, nunca el marketplace.

import 'package:aura_app/core/router/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('la profe SÍ puede entrar', () {
    test('a la ficha pública de un estudio', () {
      expect(rutaVedadaParaProfe('/estudio/42'), isFalse);
      // El estudio donde da clases: Sitio Pilates y BB Estudio Colegiales,
      // los dos que hoy tienen una profe de verdad.
      expect(rutaVedadaParaProfe('/estudio/64'), isFalse);
      expect(rutaVedadaParaProfe('/estudio/6'), isFalse);
    });

    test('a las reseñas de un estudio, que son tan públicas como la ficha', () {
      expect(rutaVedadaParaProfe('/estudio/42/resenas'), isFalse);
    });

    test('a sus dos pantallas del panel', () {
      expect(rutaVedadaParaProfe('/estudio/clases'), isFalse);
      expect(rutaVedadaParaProfe('/estudio/asistencia'), isFalse);
    });

    test('a lo que cuelga de esas dos pantallas', () {
      expect(rutaVedadaParaProfe('/estudio/clases/nueva'), isFalse);
    });

    test('a todo lo que no es del estudio', () {
      for (final ruta in ['/home', '/explorar', '/mapa', '/clase/5', '/perfil']) {
        expect(rutaVedadaParaProfe(ruta), isFalse, reason: ruta);
      }
    });
  });

  group('la profe NO puede entrar', () {
    test('a ninguna pantalla de plata ni de administración', () {
      for (final ruta in [
        '/estudio/dashboard',
        '/estudio/cobros',
        '/estudio/reservas',
        '/estudio/perfil',
        '/estudio/gestion',
      ]) {
        expect(rutaVedadaParaProfe(ruta), isTrue, reason: ruta);
      }
    });

    test('a una ruta del panel que todavía no existe (fail-closed)', () {
      // El gate no lista las rutas del panel a propósito: veda todo lo que no
      // sea la ficha pública o sus dos pantallas. Así, el día que se agregue
      // /estudio/finanzas, queda protegida sola.
      expect(rutaVedadaParaProfe('/estudio/finanzas'), isTrue);
    });
  });

  // OJO, borde conocido: el gate mira `startsWith('/estudio')` sin barra, así
  // que `/estudios` en plural también cae adentro. Hoy no existe esa ruta. Si
  // algún día se agrega un listado público de estudios, hay que sacarlo del
  // gate o la profe no va a poder abrirlo — el mismo bug de arriba otra vez.
  test('el borde del prefijo queda anotado, no suelto', () {
    expect(rutaVedadaParaProfe('/estudios'), isTrue);
  });
}
