// El alta de un estudio con cuenta, hecha por Aura desde el backoffice.
//
// Lo que se rompió y estos tests cuidan (4/9/2026): la edge function creaba el
// estudio y la cuenta pero NO la fila en `estudio_admins`, que es de donde
// `list_my_studios` decide si entrás a tu panel. Medido en rollback con el
// estado exacto que dejaba: devolvía [] y el estudio caía en /home como una
// alumna más.
//
// Son aserciones sobre el FUENTE porque lo que se protege es que estas tres
// piezas no se separen: la función que crea el vínculo, el botón que deja
// cambiar la contraseña temporal, y el aviso de usar el mail real.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('la edge function deja la cuenta lista para entrar', () {
    final fuente = File(
      'supabase/functions/admin-crear-estudio/index.ts',
    ).readAsStringSync();

    test('crea el vínculo en estudio_admins', () {
      expect(fuente.contains("from('estudio_admins')"), isTrue);
      expect(fuente.contains('usuario_id: newUserId'), isTrue);
    });

    test('con el rol que usa el sistema, no el legacy', () {
      // Los 15 accesos reales de producción son 'admin_estudio'. Y sobre todo:
      // studio_promote_user_to_admin sólo corrige el rol cuando es 'usuario',
      // así que 'estudio' quedaba pegado para siempre.
      expect(
        fuente.contains("rol: 'admin_estudio'"),
        isTrue,
        reason: 'la fila de usuarios y la de acceso van con admin_estudio',
      );
      expect(
        RegExp(r"rol: 'admin_estudio'").allMatches(fuente).length,
        2,
        reason: 'una en usuarios y otra en estudio_admins',
      );
    });

    test('si el vínculo falla, no deja una cuenta a medias', () {
      // Una cuenta sin acceso es peor que ninguna: el email queda tomado y hay
      // que borrarlo a mano para reintentar.
      final i = fuente.indexOf('accesoErr');
      expect(i, greaterThan(0));
      final bloque = fuente.substring(i);
      expect(bloque.contains('deleteUser(newUserId)'), isTrue);
      expect(bloque.contains("from('estudios').delete()"), isTrue);
    });

    test('sigue siendo sólo para admins', () {
      expect(fuente.contains("from('admin_users')"), isTrue);
      expect(fuente.contains('Solo admins pueden crear estudios'), isTrue);
    });
  });

  group('el estudio puede cambiar la contraseña temporal', () {
    final panel = File(
      'lib/screens/estudios/perfil_estudio_screen.dart',
    ).readAsStringSync();

    test('el panel del estudio ofrece cambiarla', () {
      expect(panel.contains("'/perfil/cambiar-contrasena'"), isTrue);
      expect(panel.contains('Cambiar contraseña'), isTrue);
    });

    test('la ruta a la que apunta existe y es de primer nivel', () {
      final router = File(
        'lib/core/router/app_router.dart',
      ).readAsStringSync();
      expect(router.contains("path: '/perfil/cambiar-contrasena'"), isTrue);
    });
  });

  group('el aviso del mail real', () {
    final backoffice = File(
      'lib/screens/admin/admin_estudios_screen.dart',
    ).readAsStringSync();

    test('ya no dice que el mail puede ser inventado', () {
      // Si el mail es inventado, el estudio queda sin forma de recuperar la
      // contraseña: "olvidé mi contraseña" manda un mail a esa casilla.
      expect(backoffice.contains('puede ser inventado'), isFalse);
    });

    test('y explica por qué conviene el real', () {
      expect(backoffice.contains('recuperar la '), isTrue);
    });
  });
}
