import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../services/usuarios_service.dart';

enum _PaymentState {
  idle,
  creating,
  waiting,
  approved,
  rejected,
  error,
}

class CheckoutScreen extends StatefulWidget {
  final Map<String, dynamic> purchase;

  const CheckoutScreen({
    super.key,
    required this.purchase,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen>
    with WidgetsBindingObserver {
  final _usuariosService = UsuariosService();

  _PaymentState _state = _PaymentState.idle;
  String? _errorMsg;
  String? _pagoId;
  Timer? _pollTimer;
  int _pollSeconds = 0;
  int _creditosIniciales = 0;
  String _planInicial = '';
  String _subscriptionStatusInicial = '';

  static const _pollMaxSeconds = 120;
  static const _pollIntervalSeconds = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _state == _PaymentState.waiting) {
      _checkPagoStatus();
    }
  }

  Future<void> _iniciarPago(AppProvider provider) async {
    if (_state != _PaymentState.idle) return;

    final purchase = widget.purchase;
    final isPlan = purchase['type'] == 'plan';
    final nombre = (purchase['nombre'] ?? '').toString();
    final creditos = (purchase['creditos'] as num?)?.toInt() ?? 0;
    final precio = (purchase['precio'] as num?)?.toInt() ?? 0;
    final vigenciaDias = (purchase['vigencia_dias'] as num?)?.toInt();

    _creditosIniciales = provider.usuario?.creditos ?? 0;
    _planInicial = provider.usuario?.plan ?? '';
    _subscriptionStatusInicial = provider.usuario?.subscriptionStatus ?? '';

    setState(() => _state = _PaymentState.creating);

    try {
      final result = isPlan
          ? await _usuariosService.crearCheckoutPlan(
              planNombre: nombre,
              planCreditos: creditos,
              planPrecio: precio,
            )
          : await _usuariosService.crearCheckoutPack(
              packNombre: nombre,
              creditos: creditos,
              amount: precio,
              vigenciaDias: vigenciaDias,
            );

      final initPoint = result['init_point'] as String?;
      _pagoId = result['pago_id'] as String?;

      if (initPoint == null || initPoint.isEmpty) {
        throw Exception('Mercado Pago no devolvió una URL de pago válida.');
      }

      final uri = Uri.parse(initPoint);
      final launched = kIsWeb
          ? await launchUrl(uri, webOnlyWindowName: '_self')
          : await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!launched) {
        throw Exception('No se pudo abrir Mercado Pago. Intentá de nuevo.');
      }

      if (!mounted) return;
      setState(() => _state = _PaymentState.waiting);
      _startPolling(provider);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _PaymentState.error;
        _errorMsg = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _startPolling(AppProvider provider) {
    _pollSeconds = 0;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: _pollIntervalSeconds),
      (_) async {
        _pollSeconds += _pollIntervalSeconds;
        if (_pollSeconds >= _pollMaxSeconds) {
          _pollTimer?.cancel();
          return;
        }
        await _checkPagoStatus(provider: provider);
      },
    );
  }

  Future<void> _checkPagoStatus({AppProvider? provider}) async {
    if (_pagoId == null) return;

    try {
      final p = provider ?? context.read<AppProvider>();
      final pagoIdFromUrl = Uri.base.queryParameters['pago_id'];
      final paymentId = Uri.base.queryParameters['payment_id'] ??
          Uri.base.queryParameters['collection_id'];
      final status = (paymentId != null && paymentId.isNotEmpty) ||
              (pagoIdFromUrl != null && pagoIdFromUrl.isNotEmpty)
          ? await _usuariosService.confirmarPagoManual(
              pagoId: pagoIdFromUrl ?? _pagoId!,
              paymentId: paymentId,
            )
          : await _usuariosService.getPagoStatus(_pagoId!);
      if (!mounted) return;

      if (status == 'approved') {
        _pollTimer?.cancel();
        await p.refrescarUsuario();
        if (!mounted) return;
        setState(() => _state = _PaymentState.approved);
        return;
      }

      if (status == 'rejected' || status == 'cancelled') {
        _pollTimer?.cancel();
        setState(() => _state = _PaymentState.rejected);
        return;
      }

      await p.refrescarUsuario();
      if (!mounted) return;

      final isPlan = widget.purchase['type'] == 'plan';
      final expectedCreditos = (widget.purchase['creditos'] as num?)?.toInt() ?? 0;
      final packAcreditado =
          !isPlan && (p.usuario?.creditos ?? 0) >= (_creditosIniciales + expectedCreditos);
      final planActivado = isPlan &&
          p.usuario?.subscriptionStatus == 'active' &&
          (p.usuario?.plan ?? '').isNotEmpty &&
          ((p.usuario?.plan ?? '') != _planInicial ||
              _subscriptionStatusInicial != 'active');

      if (packAcreditado || planActivado) {
        _pollTimer?.cancel();
        setState(() => _state = _PaymentState.approved);
      }
    } catch (_) {
      // Ignoramos errores momentáneos durante el polling.
    }
  }

  void _reintentar() {
    _pollTimer?.cancel();
    setState(() {
      _state = _PaymentState.idle;
      _errorMsg = null;
      _pagoId = null;
      _pollSeconds = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isPlan = widget.purchase['type'] == 'plan';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isPlan ? 'Suscripción' : 'Comprar créditos'),
        leading: _state == _PaymentState.waiting
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              ),
        automaticallyImplyLeading: false,
      ),
      body: switch (_state) {
        _PaymentState.approved => _ApprovedView(
            isPlan: isPlan,
            onContinue: () => context.go('/home'),
          ),
        _PaymentState.rejected => _RejectedView(
            onRetry: _reintentar,
            onBack: () => context.pop(),
          ),
        _PaymentState.waiting => _WaitingView(
            pollSeconds: _pollSeconds,
            maxSeconds: _pollMaxSeconds,
            onManualCheck: () => _checkPagoStatus(
              provider: context.read<AppProvider>(),
            ),
            onBack: () {
              _pollTimer?.cancel();
              context.pop();
            },
          ),
        _PaymentState.error => _ErrorView(
            message: _errorMsg ?? 'Ocurrió un error inesperado.',
            onRetry: _reintentar,
            onBack: () => context.pop(),
          ),
        _ => _IdleView(
            purchase: widget.purchase,
            isPlan: isPlan,
            loading: _state == _PaymentState.creating,
            provider: provider,
            onPay: () => _iniciarPago(provider),
          ),
      },
    );
  }
}

class _IdleView extends StatelessWidget {
  final Map<String, dynamic> purchase;
  final bool isPlan;
  final bool loading;
  final AppProvider provider;
  final VoidCallback onPay;

  const _IdleView({
    required this.purchase,
    required this.isPlan,
    required this.loading,
    required this.provider,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final nombre = (purchase['nombre'] ?? '').toString();
    final creditos = (purchase['creditos'] as num?)?.toInt() ?? 0;
    final precio = (purchase['precio'] as num?)?.toInt() ?? 0;
    final vigenciaDias = (purchase['vigencia_dias'] as num?)?.toInt() ?? 90;
    final descripcion = (purchase['descripcion'] ?? '').toString();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.black,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      isPlan ? 'Suscripción mensual' : 'Pack de créditos',
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      nombre,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      descripcion,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: Text(
                            '$creditos créditos',
                            style: const TextStyle(
                              color: AppColors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          isPlan ? '\$${_fmt(precio)}/mes' : '\$${_fmt(precio)}',
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Método de pago',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.primary, width: 1.6),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet_rounded,
                      color: AppColors.primary,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mercado Pago',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'Tarjeta, débito, efectivo o saldo MP',
                            style: TextStyle(fontSize: 12, color: AppColors.grey),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.check_circle_rounded, color: AppColors.primary),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.warmBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tu pago se procesa de forma segura en Mercado Pago. Aura nunca accede a los datos de tu tarjeta.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.grey,
                              height: 1.5,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.warmBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isPlan ? Icons.autorenew_rounded : Icons.event_busy_outlined,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPlan ? 'Renovación del plan' : 'Vigencia del pack',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppColors.black,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isPlan
                                ? 'Si lo activás, Mercado Pago renueva el cobro automáticamente cada mes hasta que lo canceles.'
                                : 'Este pack vence a los $vigenciaDias días desde la compra.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.grey,
                                  height: 1.45,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Tu saldo actual: ${provider.usuario?.creditos ?? 0} créditos',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.grey),
              ),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
          color: AppColors.white,
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: loading ? null : onPay,
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: AppColors.white, strokeWidth: 2),
                    )
                  : Text(
                      isPlan
                          ? 'Suscribirme con Mercado Pago'
                          : 'Pagar con Mercado Pago',
                    ),
            ),
          ),
        ),
      ],
    );
  }

  String _fmt(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      );
}

class _WaitingView extends StatelessWidget {
  final int pollSeconds;
  final int maxSeconds;
  final VoidCallback onManualCheck;
  final VoidCallback onBack;

  const _WaitingView({
    required this.pollSeconds,
    required this.maxSeconds,
    required this.onManualCheck,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final timedOut = pollSeconds >= maxSeconds;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!timedOut)
              const CircularProgressIndicator(color: AppColors.primary)
            else
              const Icon(Icons.hourglass_empty_rounded, size: 48, color: AppColors.grey),
            const SizedBox(height: 24),
            Text(
              timedOut ? 'Tu pago todavía está pendiente' : 'Verificando tu pago...',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              timedOut
                  ? 'Completá el pago en Mercado Pago y volvé aquí. Cuando se confirme, tus créditos se acreditarán solos.'
                  : 'Completá el pago en Mercado Pago y volvé a la app. Confirmamos automáticamente cuando el pago se apruebe.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.grey,
                    height: 1.55,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: onManualCheck,
                child: const Text('Ya pagué, verificar ahora'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onBack,
              child: const Text(
                'Volver',
                style: TextStyle(color: AppColors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovedView extends StatelessWidget {
  final bool isPlan;
  final VoidCallback onContinue;

  const _ApprovedView({
    required this.isPlan,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: AppColors.white, size: 36),
            ),
            const SizedBox(height: 24),
            Text(
              isPlan ? '¡Suscripción activada!' : '¡Créditos acreditados!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              isPlan
                  ? 'Tu plan quedó activo. La acreditación automática puede tardar unos instantes en reflejarse por completo.'
                  : 'Tus créditos ya están disponibles en tu saldo.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.grey,
                    height: 1.55,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: onContinue,
                child: const Text('Ir al inicio'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RejectedView extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onBack;

  const _RejectedView({required this.onRetry, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, color: AppColors.error, size: 36),
            ),
            const SizedBox(height: 24),
            Text(
              'Pago no aprobado',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'El pago fue rechazado o cancelado. Podés intentarlo de nuevo con otro medio de pago desde Mercado Pago.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.grey,
                    height: 1.55,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: onRetry,
                child: const Text('Intentar de nuevo'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onBack,
              child: const Text(
                'Volver',
                style: TextStyle(color: AppColors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 24),
            Text(
              'No se pudo iniciar el pago',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.grey,
                    height: 1.55,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: onRetry,
                child: const Text('Reintentar'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onBack,
              child: const Text(
                'Volver',
                style: TextStyle(color: AppColors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
