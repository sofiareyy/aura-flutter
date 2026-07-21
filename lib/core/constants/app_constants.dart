class AppConstants {
  /// Reemplazá este valor con el DSN de tu proyecto en https://sentry.io
  static const String sentryDsn = 'REEMPLAZAR_CON_TU_DSN_DE_SENTRY';

  static const String supabaseUrl =
      'https://hvgqpzvornlnxmsbqnwg.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk';

  static const String tableUsuarios = 'usuarios';
  static const String tableEstudios = 'estudios';
  static const String tableClases = 'clases';
  static const String tableReservas = 'reservas';
  static const String tableNotificacionesEstudio = 'notificaciones_estudio';

  static const List<Map<String, dynamic>> planes = [
    {
      'nombre': 'Starter',
      'creditos': 30,
      'precio': 28000,
      'descripcion': 'Un plan simple para empezar cada mes',
      'orden': 1,
    },
    {
      'nombre': 'Explorer',
      'creditos': 60,
      'precio': 52000,
      'descripcion': 'Más clases y más flexibilidad durante el mes',
      'destacado': true,
      'orden': 2,
    },
    {
      'nombre': 'Unlimited',
      'creditos': 120,
      'precio': 96000,
      'descripcion': 'Pensado para usar Aura todas las semanas',
      'orden': 3,
    },
  ];

  static const List<String> categorias = [
    'Todos',
    'Yoga',
    'Pilates',
    'Gym / funcional',
    'Ceramica + vino 3hs',
  ];

  /// Categorias que puede elegir un estudio. La fuente de verdad en runtime es
  /// la tabla `study_categories`; esta lista es el fallback si no responde.
  static const List<String> categoriasEstudio = [
    'Pilates',
    'Yoga',
    'Barre',
    'Gym / Funcional',
    'Cerámica',
    'Tufting',
    'Danza',
    'Holístico / Bienestar',
    'Meditación',
    'Otro',
  ];

  /// Estados de reserva que el estudio cobra. Un 'ausente' (reservó y no vino)
  /// se liquida igual: el crédito ya se consumió al reservar y no se devuelve.
  /// Ver `_montoPendiente` / `_montoCobrado` en cobros_screen.
  ///
  /// 'completada' TIENE que estar acá: el cron `completar-reservas` mueve las
  /// reservas a ese estado apenas termina la clase, así que sin incluirlo el
  /// estudio dejaría de cobrar todo lo que ya pasó — que es justamente lo que
  /// más cobra. Se excluyen solo 'cancelada', 'cancelada_por_estudio' (ambas
  /// devuelven créditos) y 'pre_confirmada' (todavía no consumió nada).
  static const List<String> estadosLiquidables = [
    'confirmada',
    'presente',
    'ausente',
    'completada',
  ];

  /// Minutos antes del inicio en que cierra la cancelacion, si el estudio no
  /// configuro `cancelacion_cierre_minutos`. 720 min = 12 hs.
  static const int cancelacionCierreMinutosDefault = 720;
}
