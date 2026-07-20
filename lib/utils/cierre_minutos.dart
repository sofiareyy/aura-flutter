import '../core/constants/app_constants.dart';

/// Resolucion de las dos ventanas de tiempo de una clase. Son reglas
/// distintas y se configuran por separado:
///
///  - `reserva_cierre_minutos`     -> cuantos minutos antes del inicio deja
///                                    de poder reservarse la clase.
///  - `cancelacion_cierre_minutos` -> cuantos minutos antes del inicio deja
///                                    de poder cancelarse una reserva.
///
/// Ambas se resuelven en cascada: valor de la clase, si no el default del
/// estudio, si no la constante global. Un `null` significa "no configurado"
/// y por eso las columnas son nullables: guardar 0 seria "sin ventana" y
/// pisaria el default del estudio.
class CierreMinutos {
  const CierreMinutos._();

  static int? _leer(Map? source, String columna) {
    if (source == null) return null;
    return (source[columna] as num?)?.toInt();
  }

  static int? _resolver(Map? clase, String columna) {
    final deLaClase = _leer(clase, columna);
    if (deLaClase != null) return deLaClase;
    return _leer(clase?['estudios'] as Map?, columna);
  }

  /// Minutos antes del inicio en que cierra la reserva. Default 0: se puede
  /// reservar hasta que la clase arranca, salvo que el estudio lo cambie.
  static int reserva(Map? clase) =>
      _resolver(clase, 'reserva_cierre_minutos') ?? 0;

  /// Minutos antes del inicio en que cierra la cancelacion. Default 720
  /// (12 hs): cancelar mas tarde consume los creditos.
  static int cancelacion(Map? clase) =>
      _resolver(clase, 'cancelacion_cierre_minutos') ??
      AppConstants.cancelacionCierreMinutosDefault;

  /// Formato amigable para los textos de politica y los mensajes de error.
  static String formatDuracion(int minutos) {
    if (minutos <= 0) return 'que la clase arranque';
    if (minutos % 1440 == 0) {
      final d = minutos ~/ 1440;
      return d == 1 ? '1 día' : '$d días';
    }
    if (minutos % 60 == 0) {
      final h = minutos ~/ 60;
      return h == 1 ? '1 hora' : '$h horas';
    }
    return '$minutos minutos';
  }
}
