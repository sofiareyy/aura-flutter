class AppConstants {
  /// Reemplazá este valor con el DSN de tu proyecto en https://sentry.io
  static const String sentryDsn = 'REEMPLAZAR_CON_TU_DSN_DE_SENTRY';

  static const String supabaseUrl =
      'https://hvgqpzvornlnxmsbqnwg.supabase.co';

  /// Dominio propio de Aura, sin barra final. La web vive acá (GitHub Pages
  /// con custom domain) y es el dominio de los mails (Resend).
  static const String auraDominio = 'https://somosaurapass.com';

  /// URL de la web. Es a donde vuelven el login con Google/Apple
  /// (`redirectTo`) y el link de confirmación de mail (`emailRedirectTo`),
  /// así que **tiene que estar en Redirect URLs del dashboard de Supabase**.
  ///
  /// Termina en '/' a propósito: Supabase le agrega el `?code=...` y así queda
  /// limpio. Como la web usa hash routing, la raíz sin '#' evita que el
  /// fragmento se ensucie.
  ///
  /// ⚠️ NO hardcodear esta URL en las pantallas. Antes login y registro la
  /// tenían escrita a mano y SIN la barra final, así que no matcheaba la
  /// allowlist de Supabase y el redirect de Google se cortaba.
  static const String auraWebUrl = '$auraDominio/';

  /// Link público a una clase, para compartir por WhatsApp, historias, etc.
  /// La web usa hash routing, de ahí el '#'.
  static String linkDeClase(int claseId) => '$auraDominio/#/clase/$claseId';
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

  /// Minutos antes del inicio en que cierra la RESERVA, si ni la clase ni el
  /// estudio configuraron `reserva_cierre_minutos`. 60 min = 1 h: por default
  /// no se puede reservar en la última hora, salvo que el estudio lo cambie.
  static const int reservaCierreMinutosDefault = 60;
}
