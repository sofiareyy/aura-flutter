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

  /// Ficha de la app en las tiendas, para el botón "Actualizar" del
  /// force-update. iOS: App Store id verificado (app "Aura Pass", SOFIA REY).
  /// Android: URL determinística por applicationId (app.somosaura.aura);
  /// funciona recién cuando la app esté publicada en Play.
  static const String appStoreUrl =
      'https://apps.apple.com/app/id6764207399';

  /// ¿Android ya está publicado en Google Play?
  ///
  /// Mientras esté en `false`, ningún lugar de la app le ofrece descargar a
  /// alguien en Android: no se frustra a nadie ofreciéndole algo que todavía
  /// no existe. **Publicar Android = poner esto en `true` y sacar un build.**
  static const bool androidPublicado = false;

  /// Link de tienda para el muro de invitados, con su propio `ct`: así se
  /// puede medir cuánta gente instaló POR EL MURO, aparte de lo que trae la
  /// pauta. Mismo `pt` que la landing de descarga.
  static const String appStoreUrlMuro =
      'https://apps.apple.com/app/apple-store/id6764207399'
      '?pt=128832642&ct=muro_web&mt=8';
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=app.somosaura.aura';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk';

  static const String tableUsuarios = 'usuarios';
  static const String tableEstudios = 'estudios';
  static const String tableClases = 'clases';
  static const String tableReservas = 'reservas';
  static const String tableNotificacionesEstudio = 'notificaciones_estudio';

  /// Fallback si `pricing_planes` no responde. Tiene que reflejar la tabla:
  /// si cambiás precios allá, actualizá acá o la app puede llegar a mostrar
  /// un precio viejo cuando falla la lectura.
  static const List<Map<String, dynamic>> planes = [
    {
      'nombre': 'Semanal',
      'creditos': 70,
      'precio': 70000,
      'descripcion': 'Para ir una vez por semana',
      'orden': 1,
    },
    {
      'nombre': 'Frecuente',
      'creditos': 120,
      'precio': 108000,
      'descripcion': 'Para entrenar seguido y variar de estudio',
      'destacado': true,
      'orden': 2,
    },
    {
      'nombre': 'Libre',
      'creditos': 160,
      'precio': 139200,
      'descripcion': 'Para quienes no paran',
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
