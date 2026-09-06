import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/aura_tokens.dart';
import '../../providers/app_provider.dart';
import '../../services/referidos_service.dart';
import '../../widgets/ancho_maximo.dart';

class ReferidosScreen extends StatefulWidget {
  const ReferidosScreen({super.key});

  @override
  State<ReferidosScreen> createState() => _ReferidosScreenState();
}

class _ReferidosScreenState extends State<ReferidosScreen> {
  final _service = ReferidosService();
  final _codigoCtrl = TextEditingController();
  String _codigoPropio = '--------';
  String? _codigoUsado;
  int _referidosCount = 0;
  bool _loading = true;
  bool _applying = false;
  bool _haCompradoPack = false;
  bool _tienePlan = false;

  static const int _maxReferidos = 2;

  /// El código se desbloquea si el usuario tiene un plan asignado o ya compró
  /// su primer pack de créditos.
  bool get _puedeVerCodigo => _tienePlan || _haCompradoPack;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final appProvider = context.read<AppProvider>();
    final userId = appProvider.userId;
    final results = await Future.wait([
      _service.obtenerOCrearCodigo(userId),
      _service.codigoYaUsado(userId),
      _service.contarReferidos(userId),
      _service.haCompradoPack(userId),
    ]);
    if (!mounted) return;
    final plan = (appProvider.usuario?.plan ?? '').trim();
    setState(() {
      _codigoPropio = results[0] as String;
      _codigoUsado = results[1] as String?;
      _referidosCount = results[2] as int;
      _haCompradoPack = results[3] as bool;
      _tienePlan = plan.isNotEmpty && plan.toLowerCase() != 'sin plan';
      _loading = false;
    });
  }

  Future<void> _aplicarCodigo() async {
    final code = _codigoCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    final appProvider = context.read<AppProvider>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _applying = true);
    try {
      final mensaje = await _service.aplicarCodigo(
        usuarioId: appProvider.userId,
        codigo: code,
      );
      await appProvider.refrescarUsuario();
      if (!mounted) return;
      setState(() => _codigoUsado = code);
      messenger.showSnackBar(
        SnackBar(content: Text(mensaje), backgroundColor: AppColors.success),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Referidos'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: AnchoMaximo(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: AppColors.black,
                        borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.card_giftcard_rounded,
                            color: AppColors.primary,
                            size: 48,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Invitá hasta 2 amigos y ganá créditos',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Quien refiere gana 20 créditos y el nuevo usuario gana 15. Se acreditan cuando el referido hace su primera compra (pack o plan).',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: AuraTipo.cuerpo,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _codigoPropioCard(),
                    const SizedBox(height: 16),
                    _aplicarCodigoCard(),
                    const SizedBox(height: 28),
                    _pasosCard(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _codigoPropioCard() {
    if (!_puedeVerCodigo) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
          border: Border.all(color: const Color(0xFFE5E0DA)),
        ),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFF2EDE8),
                borderRadius: BorderRadius.circular(AuraRadio.boton),
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: AppColors.grey,
                size: 26,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Tu código está bloqueado',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: AuraTipo.titulo,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Activá un plan o comprá tu primer pack de créditos para desbloquear tu código y empezar a invitar amigos.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.grey,
                fontSize: AuraTipo.secundario,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => context.push('/comprar-creditos'),
                child: const Text('Ver packs de créditos'),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tu código de referido',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _codigoPropio,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                    color: AppColors.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, color: AppColors.grey),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _codigoPropio));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Código copiado.'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4EC),
              borderRadius: BorderRadius.circular(AuraRadio.boton),
            ),
            child: Builder(
              builder: (_) {
                final restantes = _maxReferidos - _referidosCount;
                final msg = restantes > 0
                    ? 'Podés invitar hasta $_maxReferidos amigos. '
                          '${restantes == 1 ? 'Te queda 1 invitación disponible' : 'Te quedan $restantes invitaciones disponibles'} '
                          '($_referidosCount/$_maxReferidos usadas).'
                    : '¡Ya invitaste a tus $_maxReferidos amigos! Gracias por compartir Aura.';
                return Text(
                  msg,
                  style: const TextStyle(
                    fontSize: AuraTipo.secundario,
                    color: AppColors.black,
                    height: 1.35,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _referidosCount >= _maxReferidos
                  ? null
                  : () {
                      Share.share(
                        'Te invito a Aura. Usá mi código $_codigoPropio cuando crees tu cuenta y activamos créditos para los dos.',
                        subject: 'Tu invitación a Aura',
                      );
                    },
              icon: const Icon(Icons.share_rounded),
              label: const Text('Compartir código'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aplicarCodigoCard() {
    final yaUsado = _codigoUsado != null && _codigoUsado!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿Te invitó un amigo?',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            yaUsado
                ? 'Ya aplicaste el código $_codigoUsado en esta cuenta.'
                : 'Podés cargar un código una sola vez. Si es válido, vos recibís 15 créditos y la otra cuenta suma 20.',
            style: const TextStyle(color: AppColors.grey, height: 1.5),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _codigoCtrl,
            enabled: !yaUsado && !_applying,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Código de referido',
              hintText: 'Ej: AURA2026',
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: yaUsado || _applying ? null : _aplicarCodigo,
              child: _applying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: AppColors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(yaUsado ? 'Código ya aplicado' : 'Aplicar código'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pasosCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
      ),
      child: const Column(
        children: [
          _Step(
            num: '1',
            title: 'Compartí tu código',
            desc: 'Mandalo por WhatsApp o redes desde esta misma pantalla.',
          ),
          Divider(height: 20),
          _Step(
            num: '2',
            title: 'Tu amigo lo carga',
            desc: 'Se aplica una sola vez por cuenta nueva.',
          ),
          Divider(height: 20),
          _Step(
            num: '3',
            title: 'Los dos suman créditos',
            desc: 'La persona que refiere gana 20 y la nueva cuenta gana 15.',
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String num;
  final String title;
  final String desc;

  const _Step({required this.num, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              num,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: AuraTipo.cuerpo,
                ),
              ),
              Text(
                desc,
                style: const TextStyle(
                  color: AppColors.grey,
                  fontSize: AuraTipo.secundario,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
