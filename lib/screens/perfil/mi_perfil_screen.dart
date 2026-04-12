import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../models/estudio.dart';
import '../../models/usuario.dart';
import '../../providers/app_provider.dart';
import '../../services/auth_service.dart';
import '../../services/favoritos_service.dart';

class MiPerfilScreen extends StatefulWidget {
  const MiPerfilScreen({super.key});

  @override
  State<MiPerfilScreen> createState() => _MiPerfilScreenState();
}

class _MiPerfilScreenState extends State<MiPerfilScreen> {
  final _authService = AuthService();
  final _favoritosService = FavoritosService();

  bool _loadingFavoritos = true;
  List<Estudio> _favoritos = const [];
  int? _estudioVinculadoId;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    final provider = context.read<AppProvider>();
    await provider.cargarUsuario();
    final uid = provider.userId;
    if (uid.isNotEmpty) {
      final row = await Supabase.instance.client
          .from('usuarios')
          .select('estudio_id')
          .eq('id', uid)
          .maybeSingle();
      _estudioVinculadoId = (row?['estudio_id'] as num?)?.toInt();
    }
    await _cargarFavoritos();
    if (mounted) setState(() {});
  }

  Future<void> _cargarFavoritos() async {
    final userId = context.read<AppProvider>().userId;
    if (userId.isEmpty) return;
    final favoritos = await _favoritosService.getFavoritos(userId);
    if (!mounted) return;
    setState(() {
      _favoritos = favoritos;
      _loadingFavoritos = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          final usuario = provider.usuario;
          return SafeArea(
            child: RefreshIndicator(
              onRefresh: _cargarTodo,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Mi perfil',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: () => context.push('/configuracion'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildProfileHeader(usuario),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _StatBox(
                        value: '${usuario?.creditos ?? 0}',
                        label: 'Créditos',
                        icon: Icons.bolt_rounded,
                      ),
                      const SizedBox(width: 10),
                      _StatBox(
                        value: usuario?.creditosVencimiento != null ? 'Sí' : 'No',
                        label: 'Vencimiento',
                        icon: Icons.hourglass_bottom_rounded,
                      ),
                      const SizedBox(width: 10),
                      _StatBox(
                        value: '${_favoritos.length}',
                        label: 'Favoritos',
                        icon: Icons.favorite_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_estudioVinculadoId != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.storefront_outlined,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Esta cuenta también administra un estudio.',
                              style: TextStyle(
                                color: AppColors.black,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton(
                            onPressed: () => context.go('/estudio/dashboard'),
                            child: const Text('Cambiar al lado estudio'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _MenuSection(
                    title: 'Mi cuenta',
                    items: [
                      _MenuItem(
                        icon: Icons.edit_outlined,
                        label: 'Editar perfil',
                        subtitle: 'Nombre, foto y datos básicos',
                        onTap: () => context.push('/perfil/editar'),
                      ),
                      _MenuItem(
                        icon: Icons.bolt_rounded,
                        label: 'Mis créditos',
                        subtitle: '${usuario?.creditos ?? 0} disponibles',
                        onTap: () => context.push('/mis-creditos'),
                      ),
                      _MenuItem(
                        icon: Icons.add_circle_outline_rounded,
                        label: 'Comprar créditos',
                        subtitle: 'Cargá packs cuando quieras',
                        onTap: () => context.push('/comprar-creditos'),
                      ),
                      _MenuItem(
                        icon: Icons.workspace_premium_rounded,
                        label: 'Plan mensual',
                        subtitle: 'Opcional: suscripción automática',
                        onTap: () => context.push('/cambiar-plan'),
                      ),
                      _MenuItem(
                        icon: Icons.calendar_today_rounded,
                        label: 'Mis reservas',
                        onTap: () => context.push('/mis-reservas'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _FavoritosSection(
                    estudios: _favoritos,
                    loading: _loadingFavoritos,
                  ),
                  const SizedBox(height: 16),
                  _MenuSection(
                    title: 'Más',
                    items: [
                      _MenuItem(
                        icon: Icons.people_outline_rounded,
                        label: 'Referidos',
                        subtitle: 'Compartí tu código y acreditá beneficios',
                        onTap: () => context.push('/referidos'),
                      ),
                      _MenuItem(
                        icon: Icons.settings_outlined,
                        label: 'Configuración',
                        onTap: () => context.push('/configuracion'),
                      ),
                      _MenuItem(
                        icon: Icons.logout_rounded,
                        label: 'Cerrar sesión',
                        color: AppColors.error,
                        onTap: () => _cerrarSesion(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader(Usuario? usuario) {
    final avatarUrl = usuario?.avatarUrl;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: AppColors.primaryLight,
            backgroundImage:
                avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null || avatarUrl.isEmpty
                ? Text(
                    usuario?.nombre.isNotEmpty == true
                        ? usuario!.nombre[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          Text(
            usuario?.nombre ?? '',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            usuario?.email ?? '',
            style: const TextStyle(color: AppColors.grey, fontSize: 13),
          ),
          if (usuario?.creditosVencimiento != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                'Créditos vigentes hasta el ${DateFormat('d/M/yy').format(usuario!.creditosVencimiento!)}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _cerrarSesion(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Querés salir de tu cuenta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Salir',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _authService.signOut();
      if (context.mounted) {
        context.read<AppProvider>().limpiarUsuario();
        context.go('/login');
      }
    }
  }
}

class _FavoritosSection extends StatelessWidget {
  final List<Estudio> estudios;
  final bool loading;

  const _FavoritosSection({
    required this.estudios,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Estudios favoritos',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: AppColors.grey),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              : estudios.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'Todavía no guardaste estudios favoritos. Podés hacerlo desde el detalle de cada estudio.',
                        style: TextStyle(color: AppColors.grey, height: 1.5),
                      ),
                    )
                  : Column(
                      children: estudios.asMap().entries.map((entry) {
                        final estudio = entry.value;
                        final isLast = entry.key == estudios.length - 1;
                        return Column(
                          children: [
                            ListTile(
                              onTap: () => context.push('/estudio/${estudio.id}'),
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primaryLight,
                                child: Text(
                                  estudio.nombre.isEmpty
                                      ? 'E'
                                      : estudio.nombre[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              title: Text(estudio.nombre),
                              subtitle: Text(
                                estudio.barrio?.isNotEmpty == true
                                    ? '${estudio.categoria} · ${estudio.barrio}'
                                    : estudio.categoria,
                              ),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.grey,
                              ),
                            ),
                            if (!isLast) const Divider(height: 1, indent: 72),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const _StatBox({
    required this.value,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.black,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuSection extends StatelessWidget {
  final String title;
  final List<Widget> items;

  const _MenuSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: AppColors.grey),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final isLast = entry.key == items.length - 1;
              return Column(
                children: [
                  entry.value,
                  if (!isLast) const Divider(height: 1, indent: 52),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? color;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.subtitle,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color ?? AppColors.primary, size: 18),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: color ?? AppColors.black,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(fontSize: 12, color: AppColors.grey),
            ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.grey,
        size: 20,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}
