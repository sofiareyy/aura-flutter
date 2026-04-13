import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../services/aura_gestion_service.dart';
import '../../services/clases_service.dart';
import '../../services/reservas_service.dart';
import '../../services/usuarios_service.dart';

class ConfirmarReservaScreen extends StatefulWidget {
  final int claseId;

  const ConfirmarReservaScreen({super.key, required this.claseId});

  @override
  State<ConfirmarReservaScreen> createState() => _ConfirmarReservaScreenState();
}

class _ConfirmarReservaScreenState extends State<ConfirmarReservaScreen> {
  final _clasesService = ClasesService();
  final _reservasService = ReservasService();
  final _usuariosService = UsuariosService();
  final _auraGestionService = AuraGestionService();

  Map<String, dynamic>? _clase;
  bool _loading = true;
  bool _reservando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final clase = await _clasesService.getClase(widget.claseId);
    final estudio = clase?['estudios'] as Map<String, dynamic>?;
    final estudioId =
        (estudio?['id'] as num?)?.toInt() ?? (clase?['estudio_id'] as num?)?.toInt();
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';

    if (clase != null && estudioId != null && userEmail.isNotEmpty) {
      final esAlumnoDirecto = await _auraGestionService.esAlumnoDirecto(
        estudioId: estudioId,
        userEmail: userEmail,
      );
      if (!mounted) return;
      if (esAlumnoDirecto) {
        context.go('/reserva-gestion/${widget.claseId}');
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _clase = clase;
      _loading = false;
    });
  }

  Future<void> _confirmar() async {
    final provider = context.read<AppProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final authUserId = provider.userId;
    if (authUserId.isEmpty) return;

    var usuario = provider.usuario;
    if (usuario == null || usuario.id != authUserId) {
      await provider.refrescarUsuario();
      usuario = provider.usuario;
    }
    if (usuario == null) return;

    final creditos = (_clase?['creditos'] as num?)?.toInt() ?? 1;
    if (usuario.creditos < creditos) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No tenés suficientes créditos'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _reservando = true);

    try {
      final reserva = await _reservasService.crearReserva(
        userId: authUserId,
        claseId: widget.claseId,
        creditosUsados: creditos,
      );

      await _usuariosService.descontarCreditos(authUserId, creditos);
      await provider.refrescarUsuario();

      if (mounted && reserva != null && (reserva.codigoQr?.isNotEmpty ?? false)) {
        context.go('/reserva-confirmada/${Uri.encodeComponent(reserva.codigoQr!)}');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al reservar: ${e.toString()}'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _reservando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _clase == null
              ? const Center(child: Text('Clase no encontrada'))
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final clase = _clase!;
    final estudio = clase['estudios'] as Map<String, dynamic>?;
    final fecha = clase['fecha'] != null
        ? DateTime.tryParse(clase['fecha'].toString())
        : null;
    final cierreMinutos =
        (clase['reserva_cierre_minutos'] as num?)?.toInt() ?? 0;
    final reservaCerrada = fecha != null &&
        ReservasService.reservaCerrada(fecha, cierreMinutos);
    final creditos = (clase['creditos'] as num?)?.toInt() ?? 1;

    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final usuario = provider.usuario;
        final actuales = usuario?.creditos ?? 0;
        final restantes = actuales - creditos;

        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 54, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                          color: AppColors.black,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Confirmar reserva',
                          style: TextStyle(
                            color: AppColors.black,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x10000000),
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: SizedBox(
                              height: 154,
                              width: double.infinity,
                              child: _ReservationImage(
                                imageUrl: estudio?['foto_url']?.toString(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              estudio?['categoria']?.toString().toUpperCase() ?? 'YOGA',
                              style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            clase['nombre']?.toString() ?? 'Clase',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.black,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${estudio?['nombre'] ?? 'Studio Zen'} · ${estudio?['barrio'] ?? 'Palermo'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF8F877F),
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _MetaChip(
                                icon: Icons.calendar_today_outlined,
                                text: fecha != null
                                    ? DateFormat('EEE d MMM · h:mm a', 'es').format(fecha)
                                    : 'Lun 23 Jun · 8:00 AM',
                              ),
                              _MetaChip(
                                icon: Icons.alarm_outlined,
                                text: '${clase['duracion_min'] ?? 60} min',
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _MetaChip(
                            icon: Icons.place_outlined,
                            text: estudio?['direccion']?.toString() ??
                                'Av. Santa Fe 2450, Palermo, CABA',
                            fullWidth: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: AppColors.blackSoft,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          _CreditRow(
                            label: 'Créditos disponibles',
                            value: '$actuales créditos',
                            valueColor: AppColors.white,
                          ),
                          const SizedBox(height: 14),
                          _CreditRow(
                            label: 'Costo de la clase',
                            value: '$creditos créditos',
                            valueColor: AppColors.primary,
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Divider(color: Color(0xFF2E2B28), height: 1),
                          ),
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Créditos restantes',
                                  style: TextStyle(
                                    color: AppColors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                '$restantes',
                                style: TextStyle(
                                  color: restantes < 0
                                      ? AppColors.error
                                      : AppColors.primary,
                                  fontSize: 52,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (restantes < 0) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'No tenés suficientes créditos para esta reserva.',
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    if (reservaCerrada) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          cierreMinutos > 0
                              ? 'Las reservas ya están cerradas. Este estudio permite agendar ${ReservasService.labelCierreReserva(cierreMinutos)}.'
                              : 'Las reservas ya están cerradas para esta clase.',
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.of(context).padding.bottom + 16,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: (_reservando || restantes < 0 || reservaCerrada)
                      ? null
                      : _confirmar,
                  child: _reservando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.blackDeep,
                          ),
                        )
                      : Text('Canjear · $creditos créditos'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ReservationImage extends StatelessWidget {
  final String? imageUrl;

  const _ReservationImage({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imageUrl!,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _placeholder(),
        placeholder: (_, __) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFDDDDD9),
      child: const Center(
        child: Icon(
          Icons.self_improvement_rounded,
          size: 64,
          color: Color(0xFF7A736C),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool fullWidth;

  const _MetaChip({
    required this.icon,
    required this.text,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2EDE7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF8F877F)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF6A635D),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreditRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _CreditRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFA39B94),
              fontSize: 15,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
