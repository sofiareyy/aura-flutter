import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../utils/eliminar_estudio_texto.dart';

/// Lo que decidió Sofía en el cartel.
enum DecisionEliminarEstudio { eliminar, desactivar, cancelar }

/// El cartel de borrado permanente de un estudio (4/9/2026).
///
/// Tres capas contra el accidente, en este orden en pantalla:
///   1. si hay historial de plata, un aviso rojo con los números y el empujón
///      a desactivar (que además tiene su propio botón acá mismo);
///   2. qué se borra, en una línea;
///   3. el nombre del estudio escrito a mano: el botón rojo está deshabilitado
///      hasta que coincida. Es imposible borrar con un solo toque.
///
/// Es un widget público a propósito: se testea sin levantar Supabase.
class EliminarEstudioDialog extends StatefulWidget {
  final ResumenBorrado resumen;

  const EliminarEstudioDialog({super.key, required this.resumen});

  static Future<DecisionEliminarEstudio> show(
    BuildContext context,
    ResumenBorrado resumen,
  ) async {
    final r = await showDialog<DecisionEliminarEstudio>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EliminarEstudioDialog(resumen: resumen),
    );
    return r ?? DecisionEliminarEstudio.cancelar;
  }

  @override
  State<EliminarEstudioDialog> createState() => _EliminarEstudioDialogState();
}

class _EliminarEstudioDialogState extends State<EliminarEstudioDialog> {
  final _nombreCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nombreCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.resumen;
    final advertencia = advertenciaHistorial(r);
    final habilitado = nombreCoincide(_nombreCtrl.text, r.nombre);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        '¿Eliminar ${r.nombre} para siempre?',
        style: const TextStyle(
          color: AppColors.black,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (advertencia != null) ...[
              Container(
                key: const Key('advertencia_historial'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.45),
                  ),
                ),
                child: Text(
                  advertencia,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              detalleQueSeBorra(r),
              style: const TextStyle(
                color: AppColors.black,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Para confirmar, escribí el nombre del estudio: ${r.nombre}',
              style: const TextStyle(
                color: AppColors.black,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('campo_nombre'),
              controller: _nombreCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: r.nombre,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(DecisionEliminarEstudio.cancelar),
          style: TextButton.styleFrom(foregroundColor: AppColors.grey),
          child: const Text('Cancelar'),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (r.activo)
              OutlinedButton(
                key: const Key('boton_desactivar'),
                onPressed: () => Navigator.of(context)
                    .pop(DecisionEliminarEstudio.desactivar),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                ),
                child: const Text('Mejor desactivar'),
              ),
            const SizedBox(width: 8),
            ElevatedButton(
              key: const Key('boton_eliminar'),
              onPressed: habilitado
                  ? () => Navigator.of(context)
                      .pop(DecisionEliminarEstudio.eliminar)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: AppColors.white,
                disabledBackgroundColor: AppColors.lightGrey,
              ),
              child: const Text('Eliminar para siempre'),
            ),
          ],
        ),
      ],
    );
  }
}
