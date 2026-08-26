import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _authService = AuthService();
  bool _loading = false;
  bool _loadingGoogle = false;
  bool _loadingApple = false;
  bool _obscure = true;
  bool _emailConfirmedBanner = false;

  @override
  void initState() {
    super.initState();
    _detectEmailConfirmation();
  }

  void _detectEmailConfirmation() {
    final uri = Uri.base;
    final query = uri.queryParameters['confirmed'];
    final fragment = uri.fragment;
    final cameFromConfirmation = query == '1' ||
        query == 'true' ||
        fragment.contains('type=signup') ||
        fragment.contains('type=email_change');
    if (cameFromConfirmation) {
      setState(() => _emailConfirmedBanner = true);
    }
  }

  String _friendlyLoginError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('invalid login credentials') ||
        text.contains('invalid_credentials')) {
      return 'Email o contraseña incorrectos. Revisá los datos e intentá de nuevo.';
    }
    if (text.contains('email not confirmed')) {
      return 'Todavía no validaste tu email. Revisá tu casilla (o spam).';
    }
    if (text.contains('rate limit')) {
      return 'Demasiados intentos. Esperá un momento y volvé a probar.';
    }
    return 'No pudimos iniciar sesión. Revisá tu conexión e intentá de nuevo.';
  }

  Future<void> _recuperarContrasena() async {
    final ctrl = TextEditingController(text: _emailCtrl.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Recuperar contraseña'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Te mandamos un mail con un enlace para crear una nueva '
              'contraseña.',
              style: TextStyle(color: AppColors.grey, fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'tu@email.com',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Enviar',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (email == null || email.isEmpty) return;
    if (!email.contains('@') || !email.contains('.')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresá un email válido.')),
      );
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        // En mobile el mail abre la APP vía deep link y main.dart escucha el
        // evento passwordRecovery. En web usa el Site URL por defecto.
        //
        // ⚠️ NO cambiar `aura://reset-password` por una URL https:// "para que
        // abra en cualquier lado" (2026-08-26: se propuso y se descartó al
        // medirlo). El SDK usa PKCE por defecto (gotrue 2.19: flowType =
        // AuthFlowType.pkce) y `resetPasswordForEmail` guarda el code verifier
        // en el almacenamiento del cliente QUE PIDIÓ el reset. El canje del
        // `?code=` solo funciona en ESE cliente.
        // Con https:// el link abriría el NAVEGADOR y no la app —iOS no tiene
        // associated-domains y el App Link de Android solo cubre
        // /payment-result—, así que el verifier quedaría en la app y el canje
        // fallaría: rompería el único caso que hoy SÍ anda (pedirlo en la app
        // y abrir el mail en el mismo teléfono).
        // El arreglo device-independent es TokenHash + verifyOTP, que no
        // necesita verifier. Anotado en RETOMAR, no es este build.
        redirectTo: kIsWeb ? null : 'aura://reset-password',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Te enviamos un mail a $email. Abrí el link desde ESTE mismo '
              '${kIsWeb ? 'navegador' : 'teléfono'}: si lo abrís en otro lado, '
              'el enlace no va a funcionar. Revisá spam.'),
          duration: const Duration(seconds: 8),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // No revelamos si el email existe o no (seguridad): mensaje neutro.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Si ese email tiene una cuenta, te va a llegar el enlace de '
              'recuperación.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _loadingGoogle = true);
    try {
      final launched = await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb
            ? AppConstants.auraWebUrl
            : 'aura://login-callback',
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        queryParams: const {
          'prompt': 'select_account',
          'access_type': 'offline',
        },
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir Google. Revisá tu conexión.'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() => _loadingGoogle = false);
      }
      // Si launched == true en web: la página redirige, el widget se destruye.
      // En mobile: la app queda en loading hasta que vuelva el deep link.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _loadingGoogle = false);
    }
  }

  Future<void> _loginWithApple() async {
    setState(() => _loadingApple = true);
    try {
      // iOS: flujo NATIVO (hoja de Apple, sin navegador ni redirect).
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        await _authService.signInWithAppleNative();
        if (!mounted) return;
        final destino = await _authService.destinoInicial();
        if (!mounted) return;
        context.go(destino);
        return;
      }

      // Web / Android: OAuth web (main.dart maneja el callback).
      final launched = await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: kIsWeb
            ? AppConstants.auraWebUrl
            : 'aura://login-callback',
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir Apple. Revisá tu conexión.'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() => _loadingApple = false);
      }
      // launched == true: el navegador abrió Apple; main.dart maneja el
      // callback aura://login-callback y resuelve rol + redirect.
    } on SignInWithAppleAuthorizationException catch (e) {
      // El usuario canceló la hoja de Apple: no es un error.
      if (!mounted) return;
      if (e.code != AuthorizationErrorCode.canceled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo iniciar sesión con Apple.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      setState(() => _loadingApple = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _loadingApple = false);
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final response = await _authService.signIn(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (!mounted) return;

      final uid = response.user?.id;
      String destino = '/home';
      if (uid != null) {
        await context.read<AppProvider>().refrescarUsuario();
        try {
          // Resuelve la ruta según los accesos (usuario / estudio / profe /
          // selector si tiene roles en más de un estudio).
          destino = await _authService.destinoInicial();
        } catch (_) {
          // Si RLS o un fallo transitorio bloquean resolver el destino, no
          // rompemos el login: caemos a /home.
        }
      }
      if (mounted) context.go(destino);
    } catch (e) {
      if (!mounted) return;
      // Caso especial: cuenta sin confirmar. Va un diálogo con explicación
      // clara (el remitente puede figurar como "Supabase") + reenviar.
      if (e.toString().toLowerCase().contains('email not confirmed')) {
        await _mostrarDialogoSinConfirmar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyLoginError(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Diálogo cuando el login falla porque la cuenta no está validada. Explica
  /// que el mail puede venir a nombre de "Supabase" y ofrece reenviarlo.
  Future<void> _mostrarDialogoSinConfirmar() async {
    var reenviando = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Validá tu cuenta'),
          content: const Text(
            'Todavía no validaste tu cuenta. Te mandamos un mail para '
            'confirmarla — puede figurar como remitente "Supabase" y estar en '
            'spam. Buscalo, abrilo y hacé clic en el link.\n\n'
            'Si no lo encontrás, reenvialo acá abajo.',
            style: TextStyle(color: AppColors.black, fontSize: 14, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: reenviando ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cerrar',
                  style: TextStyle(color: AppColors.grey)),
            ),
            TextButton(
              onPressed: reenviando
                  ? null
                  : () async {
                      final email = _emailCtrl.text.trim();
                      if (email.isEmpty) return;
                      setD(() => reenviando = true);
                      try {
                        await _authService.reenviarConfirmacion(email);
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Te reenviamos el mail a $email. Revisá tu casilla y spam.'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      } catch (err) {
                        setD(() => reenviando = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(err.toString().contains('rate')
                                  ? 'Esperá un momento antes de reenviar de nuevo.'
                                  : 'No pudimos reenviar el mail. Probá en un momento.'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      }
                    },
              child: Text(reenviando ? 'Reenviando…' : 'Reenviar mail',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blackDeep,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.opaque,
          child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => context.go(kIsWeb ? '/landing' : '/onboarding'),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFF5F5A56),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.blackDeep,
                                width: 2,
                              ),
                            ),
                          ),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.blackDeep,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'AURA.',
                    style: TextStyle(
                      color: Color(0xFFF5F0E8),
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const Text(
                'Bienvenida de nuevo',
                style: TextStyle(
                  color: Color(0xFFF2ECE5),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Ingresá a tu cuenta para seguir reservando',
                style: TextStyle(
                  color: Color(0xFF6E6761),
                  fontSize: 14,
                ),
              ),
              if (_emailConfirmedBanner) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF153D2A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF2EAA63), width: 1),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.check_circle_rounded,
                          color: Color(0xFF6BD498), size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Email confirmado. Ya podés ingresar.',
                          style: TextStyle(
                            color: Color(0xFFD2F3DE),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AuthLabel('Email'),
                    const SizedBox(height: 8),
                    _DarkField(
                      controller: _emailCtrl,
                      hintText: 'valentina@gmail.com',
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value?.trim().isEmpty ?? true) {
                          return 'Ingresá tu email';
                        }
                        return null;
                      },
                      focused: true,
                    ),
                    const SizedBox(height: 16),
                    _AuthLabel('Contraseña'),
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
                          return 'Ingresá tu contraseña';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: _recuperarContrasena,
                        child: const Text(
                          '¿Olvidaste tu contraseña?',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
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
                            : const Text('Ingresar'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: const [
                  Expanded(child: Divider(color: Color(0xFF242424))),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'o ingresá con',
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
              _SocialButton(
                label: _loadingGoogle ? 'Conectando...' : 'Continuar con Google',
                onTap: _loadingGoogle ? null : _loginWithGoogle,
                loading: _loadingGoogle,
              ),
              const SizedBox(height: 10),
              _AppleSignInButton(
                onPressed: _loadingApple ? null : _loginWithApple,
                loading: _loadingApple,
                text: 'Continuar con Apple',
              ),
              const SizedBox(height: 22),
              Center(
                child: GestureDetector(
                  onTap: () => context.go('/register'),
                  child: RichText(
                    text: const TextSpan(
                      children: [
                        TextSpan(
                          text: '¿No tenés cuenta? ',
                          style: TextStyle(
                            color: Color(0xFF8A8179),
                            fontSize: 14,
                          ),
                        ),
                        TextSpan(
                          text: 'Registrate',
                          style: TextStyle(
                            color: Color(0xFFF5F0E8),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
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

class _AppleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final String text;

  const _AppleSignInButton({
    required this.onPressed,
    required this.text,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        height: 42,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
    return SignInWithAppleButton(
      onPressed: onPressed ?? () {},
      text: text,
      style: SignInWithAppleButtonStyle.black,
      borderRadius: BorderRadius.circular(12),
      height: 42,
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  const _SocialButton({
    required this.label,
    this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF171717),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/google_logo.png',
                      width: 18,
                      height: 18,
                    ),
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
      ),
    );
  }
}
