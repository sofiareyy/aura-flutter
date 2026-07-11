import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../services/estudio_admin_service.dart';

/// Selector "¿Con qué querés entrar?" para usuarios con roles múltiples
/// (admin de un estudio + profe de otro, etc.). Solo se muestra cuando el
/// usuario tiene acceso a más de un estudio.
class SeleccionarAccesoScreen extends StatefulWidget {
  const SeleccionarAccesoScreen({super.key});

  @override
  State<SeleccionarAccesoScreen> createState() =>
      _SeleccionarAccesoScreenState();
}

class _SeleccionarAccesoScreenState extends State<SeleccionarAccesoScreen> {
  final _service = EstudioAdminService();
  bool _loading = true;
  bool _entrando = false;
  List<Map<String, dynamic>> _estudios = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final estudios = await _service.listMyStudios();
    if (!mounted) return;
    // Si no hay estudios, no hay nada que elegir: modo usuario.
    if (estudios.isEmpty) {
      context.go('/home');
      return;
    }
    setState(() {
      _estudios = estudios;
      _loading = false;
    });
  }

  static String _rolLabel(String? rol) {
    switch (rol) {
      case 'profe':
        return 'Profe';
      case 'estudio':
      case 'admin_estudio':
        return 'Administrador';
      default:
        return 'Estudio';
    }
  }

  Future<void> _entrarEstudio(Map<String, dynamic> e) async {
    if (_entrando) return;
    final eid = (e['estudio_id'] as num?)?.toInt();
    if (eid == null) return;
    setState(() => _entrando = true);
    final ok = await _service.setActiveEstudio(eid);
    if (!mounted) return;
    if (!ok) {
      setState(() => _entrando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo entrar a ese estudio.')),
      );
      return;
    }
    // Refrescar el rol activo antes de navegar para que el shell del estudio
    // aplique el gating correcto (profe vs admin).
    await context.read<AppProvider>().refrescarUsuario();
    if (!mounted) return;
    final esProfe = e['rol']?.toString() == 'profe';
    context.go(esProfe ? '/estudio/clases' : '/estudio/dashboard');
  }

  void _entrarComoUsuario() => context.go('/home');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 12),
                  const Text(
                    '¿Con qué querés entrar?',
                    style: TextStyle(
                      color: AppColors.black,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tenés acceso a varios lugares. Elegí con cuál seguir.',
                    style: TextStyle(color: AppColors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  ..._estudios.map((e) {
                    final nombre = e['nombre']?.toString() ?? 'Estudio';
                    final rol = e['rol']?.toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _AccesoCard(
                        icon: Icons.storefront_rounded,
                        titulo: nombre,
                        subtitulo: _rolLabel(rol),
                        onTap: _entrando ? null : () => _entrarEstudio(e),
                      ),
                    );
                  }),
                  const SizedBox(height: 4),
                  _AccesoCard(
                    icon: Icons.explore_outlined,
                    titulo: 'Modo usuario',
                    subtitulo: 'Explorar clases',
                    onTap: _entrando ? null : _entrarComoUsuario,
                  ),
                ],
              ),
      ),
    );
  }
}

class _AccesoCard extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String subtitulo;
  final VoidCallback? onTap;

  const _AccesoCard({
    required this.icon,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: AppColors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        color: AppColors.grey,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
