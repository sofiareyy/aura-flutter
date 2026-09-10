/// Los textos de apagar "Genera clases nuevas" en un horario fijo.
///
/// **Por qué viven acá y no dentro del diálogo:** los redactó Sofía palabra por
/// palabra y son la parte que más importa de esta pantalla — es el momento en
/// que un estudio decide si una alumna pierde su clase. Como funciones puras se
/// pueden testear sin levantar `MisClasesScreen`, que necesita Supabase.
///
/// **El bug que motivó todo esto** (9/9/2026): apagar el switch escribía
/// `activo = false` y nada más. El horario dejaba de generar clases nuevas,
/// pero las que ya había generado quedaban publicadas y reservables: el estudio
/// creía haber apagado algo que seguía vivo del lado de la alumna. Apareció en
/// YN Pilates, donde el backoffice mostraba un horario activo y la app dos.
library;

/// El nombre del switch. Nombra el mecanismo, no un estado: decide si el
/// horario sigue produciendo clases nuevas cada semana. "Activo" hacía creer
/// que apagarlo daba de baja lo ya publicado.
const String kLabelGeneraClases = 'Genera clases nuevas';

/// Lo mismo, con la aclaración que evita el malentendido.
const String kTooltipGeneraClases =
    'Genera clases nuevas. Apagarlo no da de baja las que ya están publicadas.';

/// La etiqueta de un horario apagado. El 50% de opacidad solo no explicaba
/// nada: un horario apagado se veía igual que uno deshabilitado.
const String kHorarioNoGenera = 'No genera clases nuevas';

/// Título del diálogo cuando el horario ya publicó clases.
const String kTituloApagarHorario = '¿Qué hacemos con las clases ya publicadas?';

/// Confirmación de apagar sin despublicar nada (casos 1 y "dejarlas").
const String kApagadoSinDespublicar =
    'Listo. Este horario no genera más clases nuevas.';

/// El cuerpo del diálogo. Tiene que quedar claro que las clases **están
/// reservables ahora mismo** y que el horario deja de generar nuevas en los dos
/// caminos — para que elegir "dejarlas" no se lea como "no hice nada".
String cuerpoApagarHorario({
  required int n,
  required String dia,
  required String hora,
  required String primera,
  required String ultima,
}) {
  final p = n != 1;
  return 'Este horario tiene $n clase${p ? 's' : ''} publicada${p ? 's' : ''}, '
      'del $primera al $ultima. Está${p ? 'n' : ''} visible${p ? 's' : ''} en '
      'la app y se puede${p ? 'n' : ''} reservar ahora mismo. De acá en '
      'adelante no se generan clases nuevas para el $dia a las $hora, elijas '
      'lo que elijas.';
}

/// La advertencia que aparece sólo si hay reservas. El pedazo que no puede
/// faltar es el último: **se quedan sin la clase**.
String advertenciaReservas(int x) => x == 1
    ? '1 alumna ya reservó estas clases. Si las despublicás, se cancelan: le '
          'devolvemos los créditos y le llega un mail avisando, pero se queda '
          'sin la clase.'
    : '$x alumnas ya reservaron estas clases. Si las despublicás, se cancelan: '
          'les devolvemos los créditos y les llega un mail avisando, pero se '
          'quedan sin la clase.';

/// El botón destructivo. Nunca dice "eliminar" ni "dar de baja": despublicar
/// es lo que efectivamente pasa, y con reservas nombra el costo real.
String botonDespublicar({required int n, required int x}) => x > 0
    ? 'Despublicar y cancelar $x reserva${x != 1 ? 's' : ''}'
    : 'Despublicar las $n';

/// El botón conservador. No se bloquea nunca, ni con reservas: terminar un
/// ciclo sin renovarlo es legítimo y la alumna se queda con su clase.
const String kBotonDejarPublicadas = 'Dejarlas publicadas';

/// Confirmación después de despublicar.
String confirmacionDespublicado({required int n, required int alumnas}) {
  final p = n != 1;
  return alumnas > 0
      ? 'Listo. Despublicamos $n clase${p ? 's' : ''} y les devolvimos los '
            'créditos a $alumnas alumna${alumnas != 1 ? 's' : ''}. Ya les '
            'llegó el mail.'
      : 'Listo. Despublicamos $n clase${p ? 's' : ''} y este horario no genera '
            'más clases nuevas.';
}

/// Cuando alguna clase no se pudo despublicar. Lo central: **el horario quedó
/// prendido**, porque el trabajo no terminó y el estudio tiene que verlo.
const String kTituloFallidas = 'Quedaron clases sin despublicar';

String cuerpoFallidas({required int despublicadas, required int fallidas}) =>
    'Se despublicaron $despublicadas clase'
    '${despublicadas != 1 ? 's' : ''}, pero $fallidas no se '
    'pud${fallidas != 1 ? 'ieron' : 'o'} dar de baja. El horario quedó '
    'prendido para que puedas revisarlas.';
