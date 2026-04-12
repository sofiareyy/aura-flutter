import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_provider.dart';

class NotificacionesScreen extends StatefulWidget {
  const NotificacionesScreen({super.key});

  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _reservas = true;
  bool _recordatorios = true;
  bool _promos = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final userId = context.read<AppProvider>().userId;
    try {
      final data = await Supabase.instance.client
          .from('usuarios')
          .select(
            'notifs_reservas, notifs_recordatorios, notifs_promos',
          )
          .eq('id', userId)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _reservas = data?['notifs_reservas'] as bool? ?? true;
        _recordatorios = data?['notifs_recordatorios'] as bool? ?? true;
        _promos = data?['notifs_promos'] as bool? ?? false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _guardar() async {
    final userId = context.read<AppProvider>().userId;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('usuarios').update({
        'notifs_reservas': _reservas,
        'notifs_recordatorios': _recordatorios,
        'notifs_promos': _promos,
      }).eq('id', userId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preferencias guardadas.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Notificaciones')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Dejamos estas preferencias listas para el lanzamiento. Aunque todavía no haya push real en todos los casos, ya podés definir cómo querés recibir avisos.',
                  style: TextStyle(color: AppColors.grey, height: 1.5),
                ),
                const SizedBox(height: 20),
                _SwitchTile(
                  title: 'Reservas confirmadas',
                  subtitle: 'Avisos cuando una reserva queda confirmada o cambia.',
                  value: _reservas,
                  onChanged: (value) => setState(() => _reservas = value),
                ),
                _SwitchTile(
                  title: 'Recordatorios',
                  subtitle: 'Mensajes previos a tus próximas clases y experiencias.',
                  value: _recordatorios,
                  onChanged: (value) => setState(() => _recordatorios = value),
                ),
                _SwitchTile(
                  title: 'Promociones y novedades',
                  subtitle: 'Lanzamientos, beneficios y recomendaciones de Aura.',
                  value: _promos,
                  onChanged: (value) => setState(() => _promos = value),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _guardar,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: AppColors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Guardar preferencias'),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: SwitchListTile(
        value: value,
        activeColor: AppColors.primary,
        onChanged: onChanged,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppColors.grey, fontSize: 12),
        ),
      ),
    );
  }
}
