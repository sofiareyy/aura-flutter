// Superposición de horarios entre clases de un mismo estudio (18/11/2026).
//
// Regla: si una clase se cruza en horario con otra clase del estudio, el
// campo "Sala" es obligatorio. Si no se cruza con ninguna, sigue opcional.
// Sin la sala, dos clases a la misma hora no se pueden distinguir: ni la
// alumna sabe a cuál ir, ni un sistema de turnos externo (Kumaly) sabe de
// cuál le hablamos.
//
// "Se cruzan" = los intervalos [inicio, inicio + duración) se tocan. Una
// clase que empieza justo cuando termina la otra NO se cruza.
//
// Todo acá es puro (sin red): los formularios traen las filas y preguntan.

/// Mensaje que muestran los formularios cuando falta la sala.
const String kMsgSalaObligatoria =
    'Esta clase se cruza en horario con otra del estudio. '
    'Completá la sala para que se distingan.';

int _durSegura(int? min) => (min == null || min <= 0) ? 1 : min;

/// ¿Se cruzan dos clases con fecha concreta?
bool franjasSeCruzan(
  DateTime inicioA,
  int? durA,
  DateTime inicioB,
  int? durB,
) {
  final finA = inicioA.add(Duration(minutes: _durSegura(durA)));
  final finB = inicioB.add(Duration(minutes: _durSegura(durB)));
  return inicioA.isBefore(finB) && inicioB.isBefore(finA);
}

/// ¿Se cruzan dos franjas del MISMO día, dadas en minutos desde las 00:00?
bool minutosSeCruzan(int inicioA, int? durA, int inicioB, int? durB) {
  return inicioA < inicioB + _durSegura(durB) &&
      inicioB < inicioA + _durSegura(durA);
}

/// "08:30" o "08:30:00" → 510. null si no se entiende.
int? minutoDelDia(Object? horaInicio) {
  final partes = (horaInicio?.toString() ?? '').split(':');
  if (partes.length < 2) return null;
  final h = int.tryParse(partes[0]);
  final m = int.tryParse(partes[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
    return null;
  }
  return h * 60 + m;
}

int? _int(Object? v) => (v as num?)?.toInt();

DateTime? _fecha(Object? v) => DateTime.tryParse(v?.toString() ?? '');

bool _cancelada(Map<String, dynamic> c) => c['cancelada'] == true;

/// Clases (filas de `clases`) que se cruzan con una clase de fecha concreta.
/// Ignora las canceladas y la propia clase ([excluirId], al editar).
List<Map<String, dynamic>> clasesQueSeCruzan({
  required DateTime inicio,
  required int? duracionMin,
  required Iterable<Map<String, dynamic>> clases,
  int? excluirId,
}) {
  final out = <Map<String, dynamic>>[];
  for (final c in clases) {
    if (_cancelada(c)) continue;
    if (excluirId != null && _int(c['id']) == excluirId) continue;
    final f = _fecha(c['fecha']);
    if (f == null) continue;
    if (franjasSeCruzan(inicio, duracionMin, f, _int(c['duracion_min']))) {
      out.add(c);
    }
  }
  return out;
}

/// ¿Un horario fijo (día 1=lunes … 7=domingo, minuto del día, duración) se
/// cruza con otro horario fijo activo del mismo día, o con alguna clase
/// futura que cae ese día de la semana?
///
/// Al editar un horario, [excluirHorarioId] saca de la cuenta al propio
/// horario y a las clases que él mismo generó.
bool horarioFijoSeCruza({
  required int dia,
  required int minuto,
  required int? duracionMin,
  required Iterable<Map<String, dynamic>> horarios,
  required Iterable<Map<String, dynamic>> clasesFuturas,
  int? excluirHorarioId,
}) {
  for (final h in horarios) {
    if (h['activo'] == false) continue;
    final id = _int(h['id']);
    if (excluirHorarioId != null && id == excluirHorarioId) continue;
    if (_int(h['dia_semana']) != dia) continue;
    final m = minutoDelDia(h['hora_inicio']);
    if (m == null) continue;
    if (minutosSeCruzan(minuto, duracionMin, m, _int(h['duracion_min']))) {
      return true;
    }
  }
  for (final c in clasesFuturas) {
    if (_cancelada(c)) continue;
    if (excluirHorarioId != null &&
        _int(c['horario_fijo_id']) == excluirHorarioId) {
      continue;
    }
    final f = _fecha(c['fecha']);
    if (f == null || f.weekday != dia) continue;
    if (minutosSeCruzan(
      minuto,
      duracionMin,
      f.hour * 60 + f.minute,
      _int(c['duracion_min']),
    )) {
      return true;
    }
  }
  return false;
}

/// Grilla: ¿alguna de las franjas nuevas se cruza con otra franja nueva del
/// mismo día, con un horario fijo existente o con una clase futura?
/// [minutosPorDia]: día → minutos del día de cada franja.
bool grillaSeCruza({
  required Map<int, Iterable<int>> minutosPorDia,
  required int duracionMin,
  required Iterable<Map<String, dynamic>> horarios,
  required Iterable<Map<String, dynamic>> clasesFuturas,
}) {
  for (final entry in minutosPorDia.entries) {
    final minutos = entry.value.toSet().toList()..sort();
    for (var i = 0; i < minutos.length; i++) {
      // Entre franjas nuevas del mismo día (ordenadas: alcanza con la vecina).
      if (i + 1 < minutos.length &&
          minutosSeCruzan(minutos[i], duracionMin, minutos[i + 1], duracionMin)) {
        return true;
      }
      if (horarioFijoSeCruza(
        dia: entry.key,
        minuto: minutos[i],
        duracionMin: duracionMin,
        horarios: horarios,
        clasesFuturas: clasesFuturas,
      )) {
        return true;
      }
    }
  }
  return false;
}
