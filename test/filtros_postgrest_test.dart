// Los filtros de Explorar traducidos a PostgREST (17/9/2026).
//
// El bug que arreglan: el chip se aplicaba en memoria sobre 20 clases traídas
// por fecha, así que "Pilates" mostraba 1 de las 155 que hay.
import 'package:aura_app/utils/filtros_postgrest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('filtro de categoría', () {
    test('"Todos" y vacío no filtran nada', () {
      expect(filtroCategoriaPostgrest('Todos', const []), isNull);
      expect(filtroCategoriaPostgrest('', const []), isNull);
      expect(filtroCategoriaPostgrest(null, const []), isNull);
    });

    test('mira el campo suelto Y la lista', () {
      expect(filtroCategoriaPostgrest('Pilates', const []),
          'categoria.eq.Pilates,categorias.cs.{"Pilates"}');
    });

    test('las que no tienen categoría propia heredan la del estudio', () {
      expect(filtroCategoriaPostgrest('Pilates', const [4, 18]),
          'categoria.eq.Pilates,categorias.cs.{"Pilates"},'
          'and(categoria.is.null,estudio_id.in.(4,18))');
    });

    test('la herencia NO arrastra las clases de otra categoría del estudio', () {
      // Rock Palermo tiene Spinning y Pilates: filtrando Pilates, su spinning
      // no entra, porque la herencia sólo aplica a las que no declaran nada.
      final f = filtroCategoriaPostgrest('Pilates', const [58])!;
      expect(f.contains('and(categoria.is.null'), isTrue);
      expect(f.contains('estudio_id.in.(58)'), isTrue);
    });

    test('una categoría con espacios se pasa entera', () {
      expect(filtroCategoriaPostgrest('Gym / Funcional', const []),
          contains('categorias.cs.{"Gym / Funcional"}'));
    });
  });

  group('filtro de texto', () {
    test('vacío no filtra', () {
      expect(filtroTextoPostgrest('', const []), isNull);
      expect(filtroTextoPostgrest('   ', const []), isNull);
    });

    test('busca en el nombre de la clase', () {
      expect(filtroTextoPostgrest('barre', const []), 'nombre.ilike.*barre*');
    });

    test('suma los estudios que matchean, para que "Citra" traiga sus clases',
        () {
      expect(filtroTextoPostgrest('citra', const [4]),
          'nombre.ilike.*citra*,estudio_id.in.(4)');
    });
  });

  group('no se puede romper la query desde el buscador', () {
    test('las comas y paréntesis se limpian', () {
      // Sin esto, un texto con comas partiría el or() en condiciones sueltas.
      final f = filtroTextoPostgrest('pilates,reformer(1)', const [])!;
      expect(f.contains('pilates reformer 1'), isTrue);
      expect(f.split(',').length, 1, reason: 'una sola condición');
    });

    test('los puntos también (separan campo.operador.valor)', () {
      expect(limpiarParaFiltro('a.b,c(d)'), 'a b c d');
    });
  });
}
