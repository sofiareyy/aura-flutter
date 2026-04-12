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
  String? _error;

  @override
  void initState() {
    super.initState();
    _confirmar();
  }

  Future<void> _confirmar() async {
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
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Confirmando pago'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text(
                      'Estamos confirmando tu pago.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.error,
                      size: 44,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error ?? 'No pudimos confirmar el pago todavía.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.black,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _error = null;
                          });
                          _confirmar();
                        },
                        child: const Text('Reintentar'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => context.go('/home'),
                      child: const Text('Volver al inicio'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
