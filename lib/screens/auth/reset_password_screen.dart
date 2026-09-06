import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/ancho_maximo.dart';

/// Pantalla a la que se llega desde el mail de "olvidé mi contraseña".
///
/// **Dos caminos de entrada, los dos terminan en una sesión de recuperación:**
///
/// 1. **`token_hash` en la URL (el camino nuevo, 2026-08-26).** El mail apunta a
///    `https://somosaurapass.com/#/reset-password?token_hash=…&type=recovery`
///    y esta pantalla lo canjea con `verifyOTP(type: OtpType.recovery)`. Ese
///    canje **NO usa el code verifier de PKCE**, así que funciona desde
///    CUALQUIER dispositivo o navegador, sin importar dónde se pidió el reset.
///    Es lo que arregla el bloqueo que reportaron los estudios.
/// 2. **Sesión ya establecida** (deep link `aura://reset-password` en la app,
///    que el SDK procesa por PKCE y dispara `passwordRecovery`). Se conserva
///    para que las apps ya instaladas sigan andando.
///
/// Con la sesión activa, `updateUser` setea la contraseña sin pedir la anterior
/// (`security_update_password_require_reauthentication = false`).
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _saving = false;

  /// Mientras se canjea el `token_hash` del link.
  bool _verificando = true;

  /// Si el canje falló (link vencido, ya usado o inválido).
  String? _errorLink;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _canjearTokenSiHay());
  }

  /// Canjea el `token_hash` del link por una sesión de recuperación.
  ///
  /// Lee el parámetro de dos lugares porque el link puede llegar de las dos
  /// formas: dentro del hash routing de Flutter web
  /// (`/#/reset-password?token_hash=…`, que es lo que manda el mail) o como
  /// query normal antes del `#`, si algún cliente de mail reescribe la URL.
  Future<void> _canjearTokenSiHay() async {
    final auth = Supabase.instance.client.auth;

    String? tokenHash = GoRouterState.of(
      context,
    ).uri.queryParameters['token_hash'];
    tokenHash ??= Uri.base.queryParameters['token_hash'];

    if (tokenHash == null || tokenHash.isEmpty) {
      // Camino 2: sin token en la URL, esperamos la sesión del deep link.
      if (mounted) {
        setState(() {
          _verificando = false;
          _errorLink = auth.currentUser == null
              ? 'Abrí el link desde el mail para poder cambiar tu contraseña.'
              : null;
        });
      }
      return;
    }

    try {
      await auth.verifyOTP(tokenHash: tokenHash, type: OtpType.recovery);
      if (!mounted) return;
      setState(() {
        _verificando = false;
        _errorLink = null;
      });
    } catch (e) {
      debugPrint('[resetPassword verifyOTP] $e');
      if (!mounted) return;
      setState(() {
        _verificando = false;
        _errorLink =
            'Este link ya no sirve: vence a las 24 horas y se usa una sola vez. '
            'Pedí uno nuevo desde "Olvidé mi contraseña".';
      });
    }
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    // Sin sesión de recuperación no se puede actualizar: el link venció, ya
    // se usó, o nunca se canjeó.
    if (Supabase.instance.client.auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este link ya no sirve: vence a las 24 horas y se usa una sola '
            'vez. Pedí uno nuevo desde "Olvidé mi contraseña".',
          ),
          duration: Duration(seconds: 6),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordCtrl.text.trim()),
      );
      if (!mounted) return;
      // Cerramos la sesión de recuperación para que vuelva a entrar con la
      // contraseña nueva (evita quedar "a medias" logueado por el token temporal).
      await AuthService().signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Listo! Ya podés entrar con tu nueva contraseña.'),
          backgroundColor: AppColors.success,
        ),
      );
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(e)),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _friendlyError(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('same') || msg.contains('should be different')) {
      return 'La contraseña nueva no puede ser igual a la anterior.';
    }
    if (msg.contains('socket') ||
        msg.contains('connection') ||
        msg.contains('network') ||
        msg.contains('timeout')) {
      return 'No pudimos conectar. Revisá tu conexión e intentá de nuevo.';
    }
    return 'No pudimos guardar la contraseña. Intentá de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    if (_verificando) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: AnchoMaximo.formulario(
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      );
    }
    if (_errorLink != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Nueva contraseña')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.link_off_rounded,
                size: 48,
                color: AppColors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                _errorLink!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.grey, height: 1.5),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go('/login'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Volver al inicio'),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Nueva contraseña')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Elegí una contraseña nueva para tu cuenta. Con esta vas a entrar '
              'la próxima vez.',
              style: TextStyle(color: AppColors.grey, height: 1.5),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Nueva contraseña'),
              validator: (value) {
                if (value == null || value.trim().length < 6) {
                  return 'Usá al menos 6 caracteres.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Repetir contraseña',
              ),
              validator: (value) {
                if (value != _passwordCtrl.text) {
                  return 'Las contraseñas no coinciden.';
                }
                return null;
              },
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _guardar,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: AppColors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Guardar contraseña'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
