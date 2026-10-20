// La cola de asistencia sin conexión, y qué cuenta como "sin conexión"
// (20/10/2026).
//
// EL RACIMO QUE ARREGLA. La pantalla de Asistencia tenía cinco defectos que
// son el mismo error visto de cinco maneras: **informaba éxito sin mirar qué
// hizo la base**.
//
//   1. El snackbar "✓ marcado como presente" y el cambio de la fila estaban
//      FUERA del try. El estudio veía el tilde verde aunque el UPDATE hubiera
//      fallado.
//   2. CUALQUIER excepción al escanear se leía como "sin conexión": un 42501
//      de RLS, un 400 o un guard de la base mostraban el popup verde
//      "Guardado offline".
//   3. La cola guardaba sólo el código QR, y al sincronizar escribía
//      `'estado': 'presente'` hardcodeado. Un "marcar ausente" que falló
//      volvía como PRESENTE.
//   4. La cola se vaciaba entera aunque el UPDATE afectara 0 filas — RLS
//      filtra, no tira error —, así que la asistencia se perdía en silencio.
//   5. `_cargar` no tenía try/catch: si fallaba, spinner para siempre.
//
// Acá viven las dos piezas que se pueden probar sin levantar la pantalla: la
// clasificación del error y el modelo de lo encolado. El resto es cableado.

import 'package:supabase_flutter/supabase_flutter.dart';

/// ¿Esto fue "no hay internet" o "el servidor contestó que no"?
///
/// La distinción es la que faltaba. Si PostgREST **contestó** —aunque haya
/// sido para rechazar— hubo conexión, y guardarlo para "sincronizar después"
/// no arregla nada: va a volver a fallar igual, y mientras tanto el estudio
/// cree que la asistencia quedó tomada.
///
/// Se clasifica por lo que respondió, no por el texto del mensaje: un
/// `PostgrestException` o un `AuthException` sólo existen si hubo respuesta.
bool esFallaDeRed(Object error) {
  if (error is PostgrestException) return false;
  if (error is AuthException) return false;
  if (error is StorageException) return false;
  // Lo que queda —SocketException, ClientException, timeouts— es la red.
  return true;
}

/// Una asistencia esperando a que vuelva la conexión.
///
/// Guarda el ESTADO buscado y no sólo el código: una marca de "ausente" que
/// se encoló tiene que sincronizar como ausente. Antes se escribía siempre
/// `presente` y la cola daba vuelta la decisión del estudio.
class PendienteAsistencia {
  final String codigoQr;

  /// 'presente' | 'ausente' | 'confirmada'
  final String estado;

  /// Cuándo lo marcó el estudio. Para 'presente' es el check-in real; se
  /// manda al sincronizar para no sellar la hora de la SINCRONIZACIÓN.
  final DateTime cuando;

  const PendienteAsistencia({
    required this.codigoQr,
    required this.estado,
    required this.cuando,
  });

  Map<String, dynamic> aJson() => {
    'codigo_qr': codigoQr,
    'estado': estado,
    'timestamp': cuando.toIso8601String(),
  };

  /// Tolera lo encolado por la versión vieja, que sólo tenía `codigo_qr`:
  /// esos se asumen 'presente', que es lo que hacía antes. Si no, una cola
  /// guardada antes de actualizar la app se perdería entera.
  static PendienteAsistencia? deJson(Map<String, dynamic> j) {
    final codigo = j['codigo_qr']?.toString() ?? '';
    if (codigo.isEmpty) return null;
    return PendienteAsistencia(
      codigoQr: codigo,
      estado: j['estado']?.toString() ?? 'presente',
      cuando:
          DateTime.tryParse(j['timestamp']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  /// El payload del UPDATE. `checked_in_at` va en null salvo para presente:
  /// es lo que distingue "vino" de "no vino".
  Map<String, dynamic> aUpdate() => {
    'estado': estado,
    'checked_in_at': estado == 'presente' ? cuando.toIso8601String() : null,
  };
}

/// Lee la cola, tolerando basura: una entrada rota no puede impedir que
/// sincronicen las demás.
List<PendienteAsistencia> leerCola(List<dynamic> crudo) {
  final out = <PendienteAsistencia>[];
  for (final e in crudo) {
    if (e is! Map) continue;
    final p = PendienteAsistencia.deJson(Map<String, dynamic>.from(e));
    if (p != null) out.add(p);
  }
  return out;
}

/// Encola, reemplazando lo que hubiera para el mismo QR.
///
/// Si el estudio marca presente, se arrepiente y marca ausente sin conexión,
/// lo que tiene que viajar es lo ÚLTIMO que decidió, no las dos cosas.
List<PendienteAsistencia> encolar(
  List<PendienteAsistencia> cola,
  PendienteAsistencia nuevo,
) => [...cola.where((p) => p.codigoQr != nuevo.codigoQr), nuevo];
