// El guard del "pagado" y la sección "Pendientes" del backoffice (6/9/2026).
//
// Lo que pasó: con la primera facturación real (Citra, agosto), el estudio vio
// "Pagado" sin que Aura hubiera pagado, y Sofía no encontraba la deuda en su
// backoffice. Medido en la base: no había NINGUNA liquidación de Citra. El
// "Pagado" era el inventado por la app vieja del teléfono; la deuda estaba
// escondida porque el backoffice abre siempre en el mes actual.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String leer(String p) => File(p).readAsStringSync();

void main() {
  group('el guard en la base', () {
    final sql = leer('supabase/FEAT_GUARD_LIQUIDACION_PAGADA_2026-09-06.sql');

    test('pagado exige fecha_pago', () {
      expect(sql, contains("check (estado <> 'pagado' or fecha_pago is not null)"));
    });

    test('el estado sólo puede ser pendiente o pagado', () {
      expect(sql, contains("check (estado in ('pendiente', 'pagado'))"));
    });

    test('un pago hecho no se deshace ni se mueve', () {
      expect(sql, contains('no vuelve a pendiente'));
      expect(sql, contains('no cambia de estudio ni de mes'));
      expect(sql, contains('no cambia de monto'));
      expect(sql, contains('no cambia de fecha de pago'));
    });

    test('el guard corre ANTES del sellado (orden alfabético de triggers)', () {
      // BEFORE triggers corren por nombre. 'guard' < 'sella'.
      expect('trg_liquidaciones_guard_pagado'.compareTo(
            'trg_liquidaciones_sella_comision'),
          lessThan(0));
    });
  });

  group('el backoffice', () {
    final admin = leer('lib/screens/admin/admin_liquidaciones_screen.dart');

    test('calcula la deuda de TODOS los meses cerrados, no sólo el elegido', () {
      expect(admin, contains('_cargarPendientes'));
      expect(admin, contains("where((m) => m != mesActual)"));
    });

    test('un mes cerrado SIN fila en liquidaciones también cuenta como deuda', () {
      // Es exactamente el caso de Citra. El historial viejo sólo miraba meses
      // con filas, así que un mes nunca liquidado no aparecía en ningún lado.
      expect(admin, contains("f['estado'] != 'pagado'"));
      expect(admin, contains("'estado': liq?['estado'] ?? 'pendiente'"));
    });

    test('pagar desde Pendientes usa el mes de la fila, no el del selector', () {
      expect(admin, contains("(estudio['mes'] as String?) ?? _mesSeleccionado"));
    });

    test('la sección va arriba de todo', () {
      final i = admin.indexOf('_buildPendientesSection(),');
      final j = admin.indexOf('_buildResumenCard(),');
      expect(i, greaterThan(0));
      expect(i, lessThan(j));
    });

    test('el botón sigue escribiendo pagado CON fecha (lo que el guard exige)', () {
      final i = admin.indexOf("'estado': 'pagado',");
      final bloque = admin.substring(i, i + 200);
      expect(bloque, contains("'fecha_pago': DateTime.now().toIso8601String()"));
    });
  });
}
