// El contrato entre `estudio_cancelar_clase` (la RPC) y el Dart que la lee.
//
// La regresión que atrapa (medida el 9/9/2026): el 1/9, al cablear el mail de
// cancelación (commit 285ce9b), la RPC se reescribió y la clave de la respuesta
// pasó de `reservas_canceladas` a `reservas_afectadas`. El Dart siguió leyendo
// la vieja, que ya no existía, así que `afectados` era SIEMPRE 0.
//
// La cancelación, la devolución de créditos y el mail nunca se rompieron —pasan
// enteros del lado del servidor—. Lo que estaba mal era el número que se le
// informaba al estudio: "devolvimos créditos a 0 alumnas" cuando eran 3. Y ese
// mismo número alimenta la confirmación de despublicar un horario.
//
// Nadie lo vio durante 8 días porque un 0 no parece un error. Por eso el test
// no mira el valor: mira que las dos puntas usen el MISMO nombre de clave.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // El SQL que define la versión viva de la función (la que trae el mail).
  final sql = File(
    'supabase/FEAT_MAIL_CANCELACION_2026-09-02.sql',
  ).readAsStringSync();
  final dart = File('lib/services/reservas_service.dart').readAsStringSync();

  test('la RPC y el Dart usan la misma clave de respuesta', () {
    // Qué clave devuelve la RPC junto con 'ok'.
    final enSql = RegExp(
      r"jsonb_build_object\(\s*'ok',\s*true,\s*'([a-z_]+)'",
    ).firstMatch(sql);
    expect(
      enSql,
      isNotNull,
      reason: 'No encontré el return de estudio_cancelar_clase en el SQL.',
    );
    final claveSql = enSql!.group(1)!;

    // Qué clave lee cancelarClaseConDevolucion.
    final cuerpo = dart.substring(
      dart.indexOf('Future<int> cancelarClaseConDevolucion'),
    );
    final enDart = RegExp(r"map\['([a-z_]+)'\] as num").firstMatch(cuerpo);
    expect(enDart, isNotNull, reason: 'No encontré la lectura en el Dart.');
    final claveDart = enDart!.group(1)!;

    expect(
      claveDart,
      claveSql,
      reason:
          'La RPC devuelve "$claveSql" y el Dart lee "$claveDart". Si no '
          'coinciden, el estudio ve 0 alumnas afectadas pase lo que pase: la '
          'cancelación funciona pero el aviso miente.',
    );
  });

  test('la clave vieja ya no se LEE (el comentario sí la nombra)', () {
    // A propósito busca la lectura real, `map['...']`, y no el nombre suelto:
    // el comentario que documenta esta regresión menciona la clave vieja, y un
    // test que mirara el texto plano fallaría por su propia documentación.
    expect(
      dart.contains("map['reservas_canceladas']"),
      isFalse,
      reason:
          'Volvió la clave que la RPC dejó de devolver el 1/9/2026. Los SQL '
          'viejos del repo todavía la nombran: es de ahí que se copió.',
    );
  });

  test('el mail de cancelación sigue cableado en la RPC', () {
    // Si alguien saca este bloque, la alumna pierde la clase y se entera al
    // llegar al estudio. Es la condición que hace aceptable "despublicar".
    expect(sql, contains('cancelacion-email'));
    expect(
      sql.contains('notificaciones_usuario'),
      isTrue,
      reason: 'Además del mail, la RPC crea el aviso in-app.',
    );
  });
}
