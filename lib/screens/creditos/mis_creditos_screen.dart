import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/aura_tokens.dart';
import '../../providers/app_provider.dart';
import '../../services/referidos_service.dart';
import '../../services/reservas_service.dart';
import '../../widgets/ancho_maximo.dart';
import '../../services/pricing_service.dart';
import '../../services/estudios_service.dart';
import '../../utils/resumen_creditos.dart';
import '../../widgets/aura_skeleton.dart';

class MisCreditosScreen extends StatefulWidget {
  const MisCreditosScreen({super.key});

  @override
  State<MisCreditosScreen> createState() => _MisCreditosScreenState();
}

class _MisCreditosScreenState extends State<MisCreditosScreen> {
  final _reservasService = ReservasService();
  /// Histórico: todas las clases tomadas, no sólo las del mes.
  List<Map<String, dynamic>> _reservas = [];

  /// Para decir para cuánto alcanza el saldo y cuántos estudios hay.
  List<int> _preciosDeClase = const [];
  int? _estudiosActivos;
  bool _loadingReservas = true;
  String? _loadedUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = context.read<AppProvider>().usuario?.id;
    if (userId != null && userId != _loadedUserId) {
      _loadedUserId = userId;
      _loadReservas(userId);
    }
  }

  /// Diálogo simple para canjear una gift card. El canje es un RPC atómico
  /// (canjear_regalo): no se puede canjear dos veces y acredita al ledger.
  Future<void> _abrirCanjeRegalo() async {
    final ctrl = TextEditingController();
    var enviando = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
          ),
          title: const Text('Canjear regalo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ingresá el código de tu gift card.',
                style: TextStyle(
                  color: AppColors.grey,
                  fontSize: AuraTipo.cuerpo,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'GIFT-XXXXXXXX',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AuraRadio.chip),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: enviando ? null : () => Navigator.of(ctx).pop(),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: AppColors.grey),
              ),
            ),
            TextButton(
              onPressed: enviando
                  ? null
                  : () async {
                      final code = ctrl.text.trim();
                      if (code.isEmpty) return;
                      setD(() => enviando = true);
                      try {
                        final creditos = await ReferidosService().canjearRegalo(
                          code,
                        );
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                        if (mounted) {
                          await context.read<AppProvider>().refrescarUsuario();
                          final uid = context.read<AppProvider>().usuario?.id;
                          if (uid != null) _loadReservas(uid);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '🎁 ¡Canjeaste $creditos créditos!',
                                ),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        setD(() => enviando = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(
                                e.toString().replaceFirst('Exception: ', ''),
                              ),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      }
                    },
              child: const Text(
                'Canjear',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadReservas(String userId) async {
    try {
      final data = await _reservasService.getReservasHistorico(userId);
      final precios = await PricingService().preciosDeClaseVigentes();
      final estudios = await EstudiosService().contarEstudiosActivos();
      if (!mounted) return;
      setState(() {
        _reservas = data;
        _preciosDeClase = precios;
        _estudiosActivos = estudios;
        _loadingReservas = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingReservas = false);
    }
  }


  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mis créditos'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: AnchoMaximo(
        child: Consumer<AppProvider>(
          builder: (context, provider, _) {
            final usuario = provider.usuario;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // ── Credits card ──────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, Color(0xFFD4612A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Créditos disponibles',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${usuario?.creditos ?? 0}',
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 56,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8, left: 6),
                            child: Text(
                              'créditos',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (usuario?.creditosVencimiento != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              color: Colors.white54,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Próximo vencimiento: ${DateFormat("d 'de' MMMM", 'es').format(usuario!.creditosVencimiento!)}',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Badge de beneficio corporativo: solo para usuarios vinculados
                // a una empresa. Es la única diferencia visible con un usuario
                // normal.
                if (usuario?.esCorporativo == true &&
                    (usuario?.empresaNombre?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 12),
                  _BeneficioEmpresaBadge(empresa: usuario!.empresaNombre!),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
                  ),
                  child: const Text(
                    'Tus packs vencen según su vigencia. El Pack Prueba dura 30 días. Los packs Esencial, Popular y Full duran 60 días. Siempre se descuentan primero los créditos que vencen antes.',
                    style: TextStyle(
                      color: AppColors.grey,
                      fontSize: AuraTipo.secundario,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.add_circle_outline_rounded,
                        label: 'Comprar\ncréditos',
                        onTap: () => context.push('/comprar-creditos'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.people_outline_rounded,
                        label: 'Ganar\ncon referidos',
                        onTap: () => context.push('/referidos'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.card_giftcard_rounded,
                        label: 'Canjear\nregalo',
                        onTap: _abrirCanjeRegalo,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  '¿Cómo usar los créditos?',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
                  ),
                  child: const Column(
                    children: [
                      _HowItem(
                        step: '1',
                        text: 'Explorá los estudios y clases disponibles',
                      ),
                      Divider(height: 20),
                      _HowItem(
                        step: '2',
                        text: 'Elegí una clase y reservá tu lugar',
                      ),
                      Divider(height: 20),
                      _HowItem(
                        step: '3',
                        text: 'Presentá tu QR en el estudio y listo',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: () => context.push('/historial-creditos'),
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text('Ver historial de movimientos'),
                  ),
                ),

                // ── Savings section ───────────────────────────────────────────
                const SizedBox(height: 24),
                const _SectionLabel('TU AHORRO CON AURA'),
                const SizedBox(height: 12),
                _buildResumenSection(),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );
  }

  /// La tarjeta de "Mis créditos": qué podés hacer con lo que tenés, y tu
  /// recorrido histórico.
  ///
  /// Reemplaza al "Este mes ahorraste $X" (9/9/2026), que se calculaba contra
  /// una tabla de precios de mercado escrita a mano en el código, sin fuente
  /// ni fecha, que sobreestimaba ~50% contra los precios reales de los
  /// estudios. Se sacó por la misma razón que el cartel de ahorro del paywall.
  Widget _buildResumenSection() {
    if (_loadingReservas) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AuraSkeleton(height: 22, width: 180),
            SizedBox(height: AuraEspacio.m),
            AuraSkeleton(height: 15, width: 220),
          ],
        ),
      );
    }

    final saldo = context.watch<AppProvider>().usuario?.creditos ?? 0;

    if (_reservas.isEmpty) {
      final vacio = textoSinReservas(creditos: saldo);
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.calendar_today_rounded,
              color: AppColors.primary,
              size: 44,
            ),
            const SizedBox(height: AuraEspacio.m),
            Text(
              vacio.titulo,
              style: const TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: AuraTipo.cuerpo,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (vacio.bajada != null) ...[
              const SizedBox(height: AuraEspacio.xs),
              Text(
                vacio.bajada!,
                style: const TextStyle(
                  color: Color(0xFF8F877F),
                  fontSize: AuraTipo.cuerpo,
                ),
              ),
            ],
          ],
        ),
      );
    }

    final alcanza = textoSaldo(
      creditos: saldo,
      preciosDeClase: _preciosDeClase,
    );
    final oferta = textoOferta(estudiosActivos: _estudiosActivos);
    final recorrido = textoRecorrido(
      clases: _reservas.length,
      estudios: _reservas
          .map((r) => (r['clases'] as Map<String, dynamic>?)?['estudio_id'])
          .whereType<Object>()
          .toSet()
          .length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (alcanza != null || oferta != null || recorrido != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.black,
              borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (alcanza != null)
                  Text(
                    alcanza,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: AuraTipo.titulo,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (oferta != null) ...[
                  const SizedBox(height: AuraEspacio.xs),
                  Text(
                    oferta,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: AuraTipo.cuerpo,
                    ),
                  ),
                ],
                if (recorrido != null) ...[
                  const SizedBox(height: AuraEspacio.m),
                  Text(
                    recorrido,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: AuraTipo.secundario,
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: AuraEspacio.xl),
        const _SectionLabel('TUS ÚLTIMAS CLASES'),
        const SizedBox(height: AuraEspacio.m),
        ..._reservas.take(5).map(_buildReservaCard),
      ],
    );
  }

  /// Una clase del historial: la clase, el estudio y lo que costó en créditos.
  /// Sin comparación contra precios de mercado inventados (9/9/2026).
  Widget _buildReservaCard(Map<String, dynamic> reserva) {
    final clase = reserva['clases'] as Map<String, dynamic>?;
    final nombre = clase?['nombre']?.toString() ?? 'Clase';
    final estudio =
        (clase?['estudios'] as Map<String, dynamic>?)?['nombre']?.toString();
    final creditos = (reserva['creditos_usados'] as num?)?.toInt() ?? 0;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AuraEspacio.s),
      padding: const EdgeInsets.all(AuraEspacio.m),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AuraRadio.boton),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AuraTipo.cuerpo,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                if (estudio != null && estudio.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    estudio,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AuraTipo.secundario,
                      color: Color(0xFF8F877F),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AuraEspacio.m),
          Text(
            creditos == 1 ? '1 crédito' : '$creditos créditos',
            style: const TextStyle(
              fontSize: AuraTipo.secundario,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryTexto,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

/// Badge "Beneficio [Empresa]" para usuarios corporativos. Va junto a los
/// créditos para dejar claro que parte del saldo lo aporta su empresa.
class _BeneficioEmpresaBadge extends StatelessWidget {
  final String empresa;
  const _BeneficioEmpresaBadge({required this.empresa});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AuraRadio.boton),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.business_rounded,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: AppColors.black,
                  fontSize: AuraTipo.secundario,
                  height: 1.3,
                ),
                children: [
                  const TextSpan(text: 'Beneficio '),
                  TextSpan(
                    text: empresa,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF8F877F),
        fontSize: AuraTipo.secundario,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: AuraTipo.secundario,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HowItem extends StatelessWidget {
  final String step;
  final String text;

  const _HowItem({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              step,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: AuraTipo.secundario,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: AuraTipo.cuerpo,
              color: AppColors.black,
            ),
          ),
        ),
      ],
    );
  }
}
