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

  static const List<Map<String, dynamic>> packsCreditos = [
    {
      'nombre': 'Pack Prueba',
      'creditos': 20,
      'precio': 25000,
      'descripcion': 'Ideal para probar Aura',
      'vigencia_dias': 60,
    },
    {
      'nombre': 'Pack Esencial',
      'creditos': 50,
      'precio': 55000,
      'descripcion': 'El pack base para usar durante el trimestre',
      'vigencia_dias': 90,
    },
    {
      'nombre': 'Pack Popular',
      'creditos': 100,
      'precio': 100000,
      'descripcion': 'El mas elegido para entrenar con frecuencia',
      'popular': true,
      'vigencia_dias': 90,
    },
    {
      'nombre': 'Pack Full',
      'creditos': 200,
      'precio': 180000,
      'descripcion': 'La opcion mas conveniente para cargar saldo',
      'vigencia_dias': 90,
    },
  ];

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
}
