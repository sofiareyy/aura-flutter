// "Que todavía se pueda tomar": el filtro de las clases que se ofrecen.
//
// El hueco que tapa (4/9/2026): el Inicio filtra las clases futuras **en la
// consulta**, o sea UNA vez, al cargar. Después las dibuja tal cual. Si la app
// queda abierta un rato, las que ya arrancaron siguen en pantalla. Medido con
// la oferta real: a las dos horas de tener el Inicio abierto, **6 de las 50
// clases cargadas ya empezaron**, y con una vidriera de 6 tarjetas eso puede
// ser la sección entera ofreciendo cosas que ya pasaron.
//
// Y "futura" no alcanza: cada estudio puede cerrar la reserva N minutos antes
// del inicio (`reserva_cierre_minutos`). Una clase que arranca en 10 minutos en
// un estudio que cierra a los 60 es futura pero NO es reservable. Hoy sólo
// Barre Estudio tiene ventana (60); el resto acepta hasta el inicio.

import 'cierre_minutos.dart';

/// El "ahora" con el que trabaja toda la app: las fechas de la base vienen en
/// hora argentina sin marcador de zona, así que se compara en ese mismo marco.
DateTime ahoraEnHorarioDeAura() =>
    DateTime.now().toUtc().subtract(const Duration(hours: 3));

/// La fecha de una clase, leída con la convención de la app. Null si no se
/// puede parsear.
DateTime? fechaDe(Map<String, dynamic> clase) {
  final raw = clase['fecha']?.toString() ?? '';
  if (raw.isEmpty) return null;
  return DateTime.tryParse('${raw.replaceFirst(' ', 'T')}Z');
}

/// ¿Esta clase todavía se puede reservar en [ahora]?
///
/// Dos condiciones: que no haya arrancado, y que no haya cerrado su ventana de
/// reserva. Una clase sin fecha legible se descarta: es preferible no ofrecer
/// algo que no se puede evaluar.
bool sePuedeTomar(Map<String, dynamic> clase, DateTime ahora) {
  if (clase['cancelada'] == true) return false;
  final fecha = fechaDe(clase);
  if (fecha == null) return false;
  final cierra = fecha.subtract(Duration(minutes: CierreMinutos.reserva(clase)));
  return ahora.isBefore(cierra);
}

/// Las clases de [clases] que todavía se pueden tomar, en el mismo orden.
List<Map<String, dynamic>> clasesTomables(
  List<Map<String, dynamic>> clases, {
  DateTime? ahora,
}) {
  final momento = ahora ?? ahoraEnHorarioDeAura();
  return clases.where((c) => sePuedeTomar(c, momento)).toList();
}
