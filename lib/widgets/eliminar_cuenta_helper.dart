import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../services/auth_service.dart';

/// Flujo compartido para eliminar la cuenta del usuario logueado.
///
/// Usado por:
///   - ConfiguracionScreen (lado usuario, requisito Apple 5.1.1).
///   - PerfilEstudioScreen (panel del estudio).
///
/// `contextoEstudio` cambia el copy del dialog para advertir que tambien
/// se eliminaran las clases del estudio. Si es null, lo detectamos
/// automaticamente via AuthService.esAdminDeEstudio.
/// Lo que hay que escribir para habilitar el borrado definitivo.
const String kPalabraConfirmacion = 'ELIMINAR';

class EliminarCuentaFlow {
  EliminarCuentaFlow._();

  /// Abre el dialog de confirmacion y, si el usuario confirma, dispara
  /// la eliminacion. En exito vuelve a /login con un SnackBar; en error
  /// muestra SnackBar rojo y deja al usuario en la pantalla actual.
  static Future<void> ejecutar(
    BuildContext context, {
    bool? contextoEstudio,
  }) async {
    final auth = AuthService();
    final esEstudio = contextoEstudio ?? await auth.esAdminDeEstudio();
    if (!context.mounted) return;

    // 2/9/2026: además del texto de advertencia, hay que ESCRIBIR "ELIMINAR"
    // para habilitar el botón. Un botón se puede tocar sin querer —sobre todo
    // pegado a "Cerrar sesión"—; escribir una palabra, no. Patrón de GitHub y
    // Stripe para lo irreversible. El costo son 5 segundos una vez en la vida.
    final palabraCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
      final habilitado =
          palabraCtrl.text.trim().toUpperCase() == kPalabraConfirmacion;
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          '¿Eliminar tu cuenta?',
          style: TextStyle(
            color: AppColors.black,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Esta acción es permanente. Se eliminarán todos tus datos, '
              'reservas e historial de créditos. No se puede deshacer.',
              style: TextStyle(
                color: AppColors.black,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            if (esEstudio) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1E8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: const Text(
                  'También se eliminarán todas las clases de tu estudio. '
                  'Los alumnos con reservas futuras recibirán sus '
                  'créditos de vuelta.',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Para confirmar, escribí $kPalabraConfirmacion:',
              style: TextStyle(
                color: AppColors.black,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: palabraCtrl,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setDialogState(() {}),
              decoration: InputDecoration(
                hintText: kPalabraConfirmacion,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE0DBD6)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.error),
                ),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: AppColors.grey),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed:
                habilitado ? () => Navigator.of(ctx).pop(true) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE0DBD6),
              disabledForegroundColor: const Color(0xFF9A928B),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
            ),
            child: const Text(
              'Sí, eliminar mi cuenta',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      );
        },
      ),
    );
    palabraCtrl.dispose();

    if (confirm != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    // Loader bloqueante mientras corre la edge function.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    try {
      await auth.eliminarCuenta();
      if (!context.mounted) return;
      // Cerrar loader + navegar a login.
      Navigator.of(context, rootNavigator: true).pop();
      router.go('/login');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Tu cuenta fue eliminada correctamente.'),
            backgroundColor: AppColors.blackSoft,
            duration: Duration(seconds: 4),
          ),
        );
      });
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'No pudimos eliminar la cuenta: '
            '${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
}
