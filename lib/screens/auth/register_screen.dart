import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _authService = AuthService();

  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final response = await _authService.signUp(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        nombre: _nombreCtrl.text.trim(),
      );
      if (!mounted) return;

      if (response.session == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Te enviamos un mail para validar tu cuenta. Revisá tu inbox o spam y después iniciá sesión.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/login');
        return;
      }

      await context.read<AppProvider>().refrescarUsuario();
      if (mounted) context.go('/creditos-onboarding');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyRegisterError(e)),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isValidEmail(String email) {
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return regex.hasMatch(email);
  }

  String _friendlyRegisterError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('over_email_send_rate_limit') ||
        text.contains('email rate limit exceeded')) {
      return 'Ya te enviamos un mail hace instantes. Esperá un minuto antes de volver a intentarlo y revisá tu casilla o spam.';
    }
    if (text.contains('user already registered')) {
      return 'Ese email ya está registrado. Probá iniciar sesión.';
    }
    if (text.contains('row-level security') && text.contains('usuarios')) {
      return 'Tu cuenta se creó pero todavía no pudimos terminar el alta. Validá tu email e intentá iniciar sesión en unos instantes.';
    }
    return 'Error: $error';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blackDeep,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => context.go('/onboarding'),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFF5F5A56),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(height: 26),
              const Text(
                'Crear cuenta',
                style: TextStyle(
                  color: Color(0xFFF2ECE5),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Empezá a reservar con packs de créditos',
                style: TextStyle(
                  color: Color(0xFF6E6761),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 28),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _AuthLabel('Nombre'),
                    const SizedBox(height: 8),
                    _DarkField(
                      controller: _nombreCtrl,
                      hintText: 'Valentina',
                      validator: (value) {
                        if (value?.trim().isEmpty ?? true) {
                          return 'Ingresá tu nombre';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    const _AuthLabel('Email'),
                    const SizedBox(height: 8),
                    _DarkField(
                      controller: _emailCtrl,
                      hintText: 'valentina@gmail.com',
                      keyboardType: TextInputType.emailAddress,
                      focused: true,
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty) {
                          return 'Ingresá tu email';
                        }
                        if (!_isValidEmail(email)) {
                          return 'Email inválido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    const _AuthLabel('Contraseña'),
                    const SizedBox(height: 8),
                    _DarkField(
                      controller: _passwordCtrl,
                      hintText: '********',
                      obscureText: _obscure,
                      suffix: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: const Color(0xFF6B655F),
                          size: 18,
                        ),
                      ),
                      validator: (value) {
                        if (value?.isEmpty ?? true) {
                          return 'Ingresá una contraseña';
                        }
                        if ((value?.length ?? 0) < 6) {
                          return 'Mínimo 6 caracteres';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: const [
                        Expanded(child: Divider(color: Color(0xFF242424))),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'o registrate con',
                            style: TextStyle(
                              color: Color(0xFF5F5953),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: Color(0xFF242424))),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _SocialButton(
                      label: 'Continuar con Google',
                      icon: Icons.circle,
                    ),
                    const SizedBox(height: 10),
                    const _SocialButton(
                      label: 'Continuar con Apple',
                      icon: Icons.change_history_rounded,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.blackDeep,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.blackDeep,
                                ),
                              )
                            : const Text('Crear cuenta'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: () => context.go('/login'),
                  child: RichText(
                    text: const TextSpan(
                      children: [
                        TextSpan(
                          text: '¿Ya tenés cuenta? ',
                          style: TextStyle(
                            color: Color(0xFF938A82),
                            fontSize: 13,
                          ),
                        ),
                        TextSpan(
                          text: 'Ingresar',
                          style: TextStyle(
                            color: Color(0xFFF2ECE5),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'Términos y privacidad',
                  style: TextStyle(
                    color: Color(0xFF938A82),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthLabel extends StatelessWidget {
  final String text;

  const _AuthLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF5F5953),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _DarkField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final bool focused;

  const _DarkField({
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.validator,
    this.focused = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      style: const TextStyle(
        color: Color(0xFFF3EEE8),
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Color(0xFF8D857D),
          fontSize: 15,
        ),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFF171717),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: focused ? AppColors.primary : const Color(0xFF2A2A2A),
            width: focused ? 1.2 : 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: 1.2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SocialButton({
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF989089),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
