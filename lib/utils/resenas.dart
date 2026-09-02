/// Cálculos de reseñas, en UN solo lugar.
///
/// El promedio hoy toma TODA la historia. Si algún día se quiere "últimos 90
/// días" (para que un mal arranque no pese para siempre), se cambia acá y
/// vale para las dos puntas: la alumna que decide una reserva y el estudio
/// que mira sus reseñas.
class Resenas {
  Resenas._();

  /// Promedio a partir del desglose {estrella: cantidad}. Null si no hay
  /// ninguna: mejor no mostrar nada que mostrar un 0,0 que parece una nota
  /// pésima. (Es lo que pasaba con Clic Pilates al revés: una sola reseña de
  /// test lo dejaba en 5,0 en Explorar.)
  static double? promedioDe(Map<int, int> desglose) {
    var suma = 0;
    var total = 0;
    desglose.forEach((estrella, cantidad) {
      suma += estrella * cantidad;
      total += cantidad;
    });
    if (total == 0) return null;
    return suma / total;
  }

  static int totalDe(Map<int, int> desglose) =>
      desglose.values.fold(0, (a, b) => a + b);

  /// '5,0' — coma decimal, como se escribe en Argentina.
  static String formatearPromedio(double? promedio) =>
      promedio == null ? '—' : promedio.toStringAsFixed(1).replaceAll('.', ',');

  /// "2 reseñas" / "1 reseña" / "Sin reseñas todavía".
  static String etiquetaTotal(int total) => total == 0
      ? 'Sin reseñas todavía'
      : '$total reseña${total == 1 ? '' : 's'}';
}
