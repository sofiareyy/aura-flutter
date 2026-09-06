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
import '../../services/referidos_service.dart';
import '../../utils/destino_post_login.dart';
import '../../services/auth_service.dart';
import '../../widgets/ancho_maximo.dart';

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
  final _codigoRegaloCtrl = TextEditingController();
  final _codigoReferidoCtrl = TextEditingController();
  final _authService = AuthService();

  bool _loading = false;
  bool _loadingGoogle = false;
  bool _loadingApple = false;
  bool _obscure = true;
  bool _showCodigoRegalo = false;
  bool _showCodigoReferido = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _codigoRegaloCtrl.dispose();
    _codigoReferidoCtrl.dispose();
    super.dispose();
  }

  /// La clase (u otra ruta) desde la que la invitada llegó al registro, puesta
  /// por el muro del modo visita como `?volver=`. Sólo se usa si el rol no
  /// manda a otro lado — ver [DestinoPostLogin.resolver].
  String? get _volver =>
      GoRouterState.of(context).uri.queryParameters['volver'];

  Future<void> _loginWithGoogle() async {
    setState(() => _loadingGoogle = true);
    try {
      // OAuth destruye esta pantalla (en web recarga la página, en la app sale
      // al navegador), así que el `?volver=` de la ruta no sobrevive: se deja
      // guardado y lo consume el callback en main.dart. Faltaba acá y por eso
      // registrarse con Google desde una clase terminaba en /home (4/9/2026).
      await DestinoPostLogin.recordar(_volver);
      final launched = await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? AppConstants.auraWebUrl : 'aura://login-callback',
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
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
        // Se lee ANTES: después del await el context puede no servir.
        final volver = _volver;
        await _authService.signInWithAppleNative();
        if (!mounted) return;
        final destino = await _authService.destinoInicial();
        if (!mounted) return;
        context.go(DestinoPostLogin.resolver(destino, volver));
        return;
      }

      // Web / Android: OAuth web (main.dart maneja el callback). Igual que en
      // Google, la pantalla se destruye: el destino se deja guardado.
      await DestinoPostLogin.recordar(_volver);
      final launched = await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: kIsWeb ? AppConstants.auraWebUrl : 'aura://login-callback',
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
          content: Text(
            'Error: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _loadingApple = false);
    }
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
        // Diálogo (no snackbar) porque navegamos a /login enseguida y el aviso
        // es clave: la persona tiene que encontrar el mail para validar.
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Revisá tu mail 🧡'),
            content: const Text(
              'Te enviamos un mail para validar tu cuenta. Puede figurar como '
              'remitente "Supabase" y estar en spam: buscalo, abrilo y tocá el '
              'link. Después iniciá sesión.',
              style: TextStyle(
                color: AppColors.black,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'Entendido',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
        if (!mounted) return;
        // El `?volver=` viaja al login: si no, la clase que la trajo se perdía
        // justo acá, en el camino más largo (registro + validar mail).
        context.go(DestinoPostLogin.conVolver('/login', _volver));
        return;
      }

      // Canje de gift card por RPC atómico (acredita al ledger, no se puede
      // canjear dos veces). No frena el registro, pero si falla avisamos: antes
      // el error quedaba mudo y el usuario no se enteraba de que su regalo no
      // se acreditó.
      final codigoRaw = _codigoRegaloCtrl.text.trim();
      var giftError = false;
      if (codigoRaw.isNotEmpty) {
        try {
          await ReferidosService().canjearRegalo(codigoRaw);
        } catch (e) {
          giftError = true;
          debugPrint('[register] canjearRegalo falló: $e');
        }
      }

      // Código de referido: solo VINCULA. Los créditos (15 al referido, 20 al
      // referrer) se acreditan con la primera compra real. Falla en silencio.
      final refRaw = _codigoReferidoCtrl.text.trim();
      final uidNuevo = response.user?.id ?? '';
      if (refRaw.isNotEmpty && uidNuevo.isNotEmpty) {
        try {
          await ReferidosService().aplicarCodigo(
            usuarioId: uidNuevo,
            codigo: refRaw,
          );
        } catch (e) {
          // No frena el registro si el código es inválido/ya usado.
          debugPrint('[register] aplicarCodigo referido: $e');
        }
      }

      await context.read<AppProvider>().refrescarUsuario();
      if (!mounted) return;
      if (giftError) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos canjear tu regalo. Probá desde Mis Créditos.',
            ),
          ),
        );
      }
      // Pieza C: si venía de una clase (el muro de invitada puso `?volver=`),
      // se lo pasamos al onboarding para que la devuelva ahí en vez de /home.
      context.go(DestinoPostLogin.conVolver('/creditos-onboarding', _volver));
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

  /// Abre una URL externa en Safari View Controller / in-app web view.
  Future<void> _abrirUrl(String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.inAppWebView);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el enlace.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el enlace.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
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
      body: AnchoMaximo.formulario(
        child: SafeArea(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.opaque,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () =>
                        context.go(kIsWeb ? '/landing' : '/onboarding'),
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
                    style: TextStyle(color: Color(0xFF6E6761), fontSize: 14),
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
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
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
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () => setState(
                            () => _showCodigoRegalo = !_showCodigoRegalo,
                          ),
                          child: const Text(
                            '¿Tenés un código de regalo?',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (_showCodigoRegalo) ...[
                          const SizedBox(height: 8),
                          _DarkField(
                            controller: _codigoRegaloCtrl,
                            hintText: 'GIFT-XXXXXXXX',
                          ),
                        ],
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () => setState(
                            () => _showCodigoReferido = !_showCodigoReferido,
                          ),
                          child: const Text(
                            '¿Te invitó una amiga? Código de referido',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (_showCodigoReferido) ...[
                          const SizedBox(height: 8),
                          _DarkField(
                            controller: _codigoReferidoCtrl,
                            hintText: 'Código de tu amiga',
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Sumás 15 créditos con tu primera compra.',
                            style: TextStyle(
                              color: Color(0xFF5F5953),
                              fontSize: 12,
                            ),
                          ),
                        ],
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
                        _SocialButton(
                          label: _loadingGoogle
                              ? 'Conectando...'
                              : 'Continuar con Google',
                          onTap: _loadingGoogle ? null : _loginWithGoogle,
                          loading: _loadingGoogle,
                        ),
                        const SizedBox(height: 10),
                        _AppleSignInButton(
                          onPressed: _loadingApple ? null : _loginWithApple,
                          loading: _loadingApple,
                          text: 'Registrarse con Apple',
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
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () =>
                              _abrirUrl('${AppConstants.auraWebUrl}terms.html'),
                          child: const Text(
                            'Términos y condiciones',
                            style: TextStyle(
                              color: Color(0xFFE8763A),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const Text(
                          '   ·   ',
                          style: TextStyle(
                            color: Color(0xFF938A82),
                            fontSize: 13,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _abrirUrl(
                            '${AppConstants.auraWebUrl}privacy.html',
                          ),
                          child: const Text(
                            'Política de privacidad',
                            style: TextStyle(
                              color: Color(0xFFE8763A),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
        hintStyle: const TextStyle(color: Color(0xFF8D857D), fontSize: 15),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFF171717),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: focused ? AppColors.primary : const Color(0xFF2A2A2A),
            width: focused ? 1.2 : 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
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

  const _SocialButton({required this.label, this.onTap, this.loading = false});

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
