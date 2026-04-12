import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/aura_gestion_design.dart';
import '../../providers/app_provider.dart';
import '../../services/aura_gestion_service.dart';
import '../../services/clases_service.dart';
import '../../services/reservas_service.dart';

class ReservaGestionScreen extends StatefulWidget {
  final int claseId;

  const ReservaGestionScreen({
    super.key,
    required this.claseId,
  });

  @override
  State<ReservaGestionScreen> createState() => _ReservaGestionScreenState();
}

class _ReservaGestionScreenState extends State<ReservaGestionScreen> {
  final _clasesService = ClasesService();
  final _gestionService = AuraGestionService();
  final _reservasService = ReservasService();

  Map<String, dynamic>? _clase;
  bool _loading = true;
  bool _confirmando = false;
  bool _esAlumnoDirecto = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final clase = await _clasesService.getClase(widget.claseId);
      final estudio = clase?['estudios'] as Map<String, dynamic>?;
      final estudioId =
          (estudio?['id'] as num?)?.toInt() ?? (clase?['estudio_id'] as num?)?.toInt();
      final email = Supabase.instance.client.auth.currentUser?.email ?? '';

      final esAlumno = estudioId != null && email.isNotEmpty
          ? await _gestionService.esAlumnoDirecto(
              estudioId: estudioId,
              userEmail: email,
            )
          : false;

      if (!mounted) return;
      setState(() {
        _clase = clase;
        _esAlumnoDirecto = esAlumno;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      AuraGestionDesign.showErrorSnackBar(
        context,
        'No pudimos cargar esta reserva.',
      );
    }
  }

  Future<void> _confirmarReservaGratis() async {
    final userId = context.read<AppProvider>().userId;
    if (userId.isEmpty) return;

    setState(() => _confirmando = true);
    try {
      // TODO: reemplazar por ReservasService.confirmarReserva() si se crea esa API específica.
      final reserva = await _reservasService.crearReserva(
        userId: userId,
        claseId: widget.claseId,
        creditosUsados: 0,
      );
      if (!mounted) return;
      if (reserva != null && (reserva.codigoQr?.isNotEmpty ?? false)) {
        context.go('/reserva-confirmada/${Uri.encodeComponent(reserva.codigoQr!)}');
      } else {
        AuraGestionDesign.showSuccessSnackBar(
          context,
          'Reserva confirmada.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      AuraGestionDesign.showErrorSnackBar(
        context,
        'No pudimos confirmar la reserva.',
      );
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuraGestionDesign.background,
      appBar: AppBar(
        backgroundColor: AuraGestionDesign.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
          color: AuraGestionDesign.textPrimary,
        ),
        title: Text(
          'Confirmar reserva',
          style: AuraGestionDesign.titleStyle(),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: AuraGestionDesign.accent,
              ),
            )
          : _clase == null
              ? Center(
                  child: Text(
                    'No encontramos esta clase.',
                    style: AuraGestionDesign.bodyStyle(),
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final clase = _clase!;
    final estudio = clase['estudios'] as Map<String, dynamic>?;
    final fecha = clase['fecha'] != null
        ? DateTime.tryParse(clase['fecha'].toString())
        : null;
    final imageUrl =
        clase['imagen_url']?.toString() ?? estudio?['foto_url']?.toString();
    final categoria =
        (clase['categoria'] ?? estudio?['categoria'] ?? 'Clase').toString();
    final nombreClase = clase['nombre']?.toString() ?? 'Clase';
    final nombreEstudio = estudio?['nombre']?.toString() ?? 'Estudio';
    final ubicacion = estudio?['barrio']?.toString() ??
        clase['sala']?.toString() ??
        'Sin ubicación';

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AuraGestionDesign.horizontalPadding,
        8,
        AuraGestionDesign.horizontalPadding,
        28,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AuraGestionDesign.card,
            borderRadius: BorderRadius.circular(AuraGestionDesign.cardRadius),
            boxShadow: const [AuraGestionDesign.softShadow],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: imageUrl != null && imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _imagePlaceholder(),
                        )
                      : _imagePlaceholder(),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AuraGestionDesign.softBadge,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  categoria,
                  style: AuraGestionDesign.bodyStyle(
                    color: AuraGestionDesign.accent,
                    size: 12,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                nombreClase,
                style: AuraGestionDesign.titleStyle(size: 18),
              ),
              const SizedBox(height: 4),
              Text(
                nombreEstudio,
                style: AuraGestionDesign.bodyStyle(
                  color: AuraGestionDesign.textSecondary,
                  size: 14,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoPill(
                    icon: Icons.calendar_today_outlined,
                    text: fecha != null
                        ? DateFormat('d MMM · HH:mm', 'es').format(fecha)
                        : 'Fecha pendiente',
                  ),
                  _InfoPill(
                    icon: Icons.schedule_rounded,
                    text: '${(clase['duracion_min'] as num?)?.toInt() ?? 60} min',
                  ),
                  _InfoPill(
                    icon: Icons.place_outlined,
                    text: ubicacion,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AuraGestionDesign.sectionSpacing),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AuraGestionDesign.premiumCard,
            borderRadius: BorderRadius.circular(AuraGestionDesign.cardRadius),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: AuraGestionDesign.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sos alumno de este estudio',
                      style: AuraGestionDesign.bodyStyle(
                        color: AuraGestionDesign.creamText,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _esAlumnoDirecto
                          ? 'Esta reserva es gratuita para vos'
                          : 'No encontramos tu acceso directo para este estudio.',
                      style: AuraGestionDesign.bodyStyle(
                        color: AuraGestionDesign.creamText.withOpacity(0.72),
                        size: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AuraGestionDesign.accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'GRATIS',
                  style: AuraGestionDesign.bodyStyle(
                    color: Colors.white,
                    size: 12,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AuraGestionDesign.sectionSpacing),
        Text(
          'POLÍTICA DE CANCELACIÓN',
          style: AuraGestionDesign.sectionLabelStyle(),
        ),
        const SizedBox(height: 12),
        _PolicyBullet(
          text: 'Podés cancelar desde Mis reservas si cambiás de planes.',
        ),
        const SizedBox(height: 10),
        _PolicyBullet(
          text:
              'Si el estudio modifica o reprograma la clase, te lo vamos a informar.',
        ),
        const SizedBox(height: AuraGestionDesign.sectionSpacing),
        ElevatedButton(
          onPressed: _esAlumnoDirecto && !_confirmando
              ? _confirmarReservaGratis
              : null,
          style: AuraGestionDesign.primaryButtonStyle(),
          child: Text(
            _confirmando ? 'Confirmando...' : 'Confirmar reserva gratis',
          ),
        ),
      ],
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: AuraGestionDesign.softBadge,
      child: const Center(
        child: Icon(
          Icons.image_outlined,
          color: AuraGestionDesign.accent,
          size: 32,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoPill({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AuraGestionDesign.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: AuraGestionDesign.accent,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: AuraGestionDesign.bodyStyle(
                size: 12,
                weight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyBullet extends StatelessWidget {
  final String text;

  const _PolicyBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: AuraGestionDesign.textSecondary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AuraGestionDesign.bodyStyle(
              color: AuraGestionDesign.textSecondary,
              size: 14,
            ),
          ),
        ),
      ],
    );
  }
}
