import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../services/usuarios_service.dart';

class PaymentResultScreen extends StatefulWidget {
  final String? pagoId;
  final String? paymentId;
  final String? status;

  const PaymentResultScreen({
    super.key,
    this.pagoId,
    this.paymentId,
    this.status,
  });

  @override
  State<PaymentResultScreen> createState() => _PaymentResultScreenState();
}

class _PaymentResultScreenState extends State<PaymentResultScreen> {
  final _usuariosService = UsuariosService();
  bool _loading = true;
  _ResultState _resultState = _ResultState.loading;

  @override
  void initState() {
    super.initState();
    _procesar();
  }

  Future<void> _procesar() async {
    // Si MP ya nos dijo que falló, mostramos el error de inmediato sin consultar
    if (widget.status == 'failure') {
      setState(() {
        _resultState = _ResultState.failure;
        _loading = false;
      });
      return;
    }

    // Si está pendiente (ej. transferencia bancaria), avisamos y volvemos al inicio
    if (widget.status == 'pending') {
      setState(() {
        _resultState = _ResultState.pending;
        _loading = false;
      });
      return;
    }

    // status == 'success' o sin status — confirmar con la edge function
    try {
      if (widget.pagoId != null && widget.pagoId!.isNotEmpty) {
        await _usuariosService.confirmarPagoManual(
          pagoId: widget.pagoId!,
          paymentId: widget.paymentId,
        );
      }

      if (!mounted) return;
      await context.read<AppProvider>().refrescarUsuario();
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      // El webhook puede no haber llegado todavía — tratar como pendiente
      setState(() {
        _resultState = _ResultState.confirmError;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: _loading
                ? const _LoadingView()
                : _buildResult(),
          ),
        ),
      ),
    );
  }

  Widget _buildResult() {
    switch (_resultState) {
      case _ResultState.failure:
        return _FailureView(
          onRetry: () => context.go('/comprar-creditos'),
          onHome: () => context.go('/home'),
        );
      case _ResultState.pending:
        return _PendingView(onHome: () => context.go('/home'));
      case _ResultState.confirmError:
        return _ConfirmErrorView(
          onRetry: () {
            setState(() {
              _resultState = _ResultState.loading;
              _loading = true;
            });
            _procesar();
          },
          onHome: () => context.go('/home'),
        );
      case _ResultState.loading:
        return const _LoadingView();
    }
  }
}

enum _ResultState { loading, failure, pending, confirmError }

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: AppColors.primary),
        SizedBox(height: 20),
        Text(
          'Confirmando tu pago…',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: AppColors.blackSoft,
          ),
        ),
      ],
    );
  }
}

class _FailureView extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onHome;

  const _FailureView({required this.onRetry, required this.onHome});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEBEB),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.credit_card_off_rounded,
            color: AppColors.error,
            size: 36,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Pago rechazado',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.black,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Tu banco no autorizó el pago. Esto puede pasar con tarjetas de débito o cuando el banco bloquea cobros recurrentes.\n\nPodés intentar con otra tarjeta o habilitarlo desde la app de tu banco.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.grey,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: onRetry,
            child: const Text('Intentar con otra tarjeta'),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: onHome,
          child: const Text('Volver al inicio'),
        ),
      ],
    );
  }
}

class _PendingView extends StatelessWidget {
  final VoidCallback onHome;

  const _PendingView({required this.onHome});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.hourglass_top_rounded,
            color: Color(0xFFF59E0B),
            size: 36,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Pago en proceso',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.black,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Tu pago está siendo procesado. Una vez acreditado, tus créditos van a aparecer automáticamente en tu cuenta.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.grey,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: onHome,
            child: const Text('Volver al inicio'),
          ),
        ),
      ],
    );
  }
}

class _ConfirmErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onHome;

  const _ConfirmErrorView({required this.onRetry, required this.onHome});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.hourglass_top_rounded,
            color: Color(0xFFF59E0B),
            size: 36,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Estamos procesando tu pago',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.black,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'El pago puede tardar unos segundos en confirmarse. Tus créditos van a aparecer en tu cuenta en breve.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.grey,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: onRetry,
            child: const Text('Verificar ahora'),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: onHome,
          child: const Text('Volver al inicio'),
        ),
      ],
    );
  }
}
