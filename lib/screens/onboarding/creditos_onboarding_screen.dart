import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';

/// La marca de "ya lo vio". La lee `main.dart` para decidir si interponerlo
/// tras el login social (ver `utils/onboarding_creditos.dart`).
const kPrefsOnboardingCreditos = 'creditos_onboarding_done';

class CreditosOnboardingScreen extends StatefulWidget {
  const CreditosOnboardingScreen({super.key});

  @override
  State<CreditosOnboardingScreen> createState() =>
      _CreditosOnboardingScreenState();
}

class _CreditosOnboardingScreenState extends State<CreditosOnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  // Copy reescrito el 9/9/2026 para conversión: de 79 registradas sólo 4
  // compraron. El texto viejo explicaba el mecanismo ("los créditos son la
  // moneda") sin decir nunca por qué conviene. Ahora cada pantalla es UNA
  // frase: qué es, cómo se usa, y el beneficio. Nadie lee onboardings largos.
  static const _slides = [
    _Slide(
      icon: Icons.storefront_rounded,
      title: 'Una app, muchos estudios',
      body:
          'Comprás créditos y reservás en yoga, pilates, funcional o barre. '
          'Sin atarte a un solo lugar.',
    ),
    _Slide(
      icon: Icons.auto_awesome_rounded,
      title: 'Elegís vos',
      body:
          'Cada clase tiene su valor en créditos. Mirás, elegís y reservás de '
          'un toque.',
    ),
    _Slide(
      icon: Icons.favorite_rounded,
      title: 'Sin cuota mensual',
      body: 'Pagás lo que usás. Comprás cuando querés, usás cuando podés.',
    ),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefsOnboardingCreditos, true);
    if (!mounted) return;
    // Pieza C: volver a la clase que la invitada estaba mirando cuando se
    // topó con el muro. Sólo se acepta una ruta interna que empiece con "/":
    // sin ese filtro, un `?volver=https://…` armado a mano mandaría a la
    // usuaria fuera de la app apenas termina de registrarse.
    final volver = GoRouterState.of(context).uri.queryParameters['volver'];
    if (volver != null && volver.startsWith('/') && !volver.startsWith('//')) {
      context.go(volver);
      return;
    }
    context.go('/home');
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _slides.length - 1;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 16),
                child: TextButton(
                  onPressed: _finish,
                  child: const Text(
                    'Saltar',
                    style: TextStyle(
                      color: Color(0xFF5A534D),
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),

            // PageView
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _SlidePage(slide: _slides[i]),
              ),
            ),

            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _page ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? AppColors.primary
                        : const Color(0xFF3A3530),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // CTA button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _next,
                  child: Text(isLast ? 'Empezar' : 'Siguiente'),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  final IconData icon;
  final String title;
  final String body;

  const _Slide({
    required this.icon,
    required this.title,
    required this.body,
  });
}

class _SlidePage extends StatelessWidget {
  final _Slide slide;

  const _SlidePage({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF24150F),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Icon(
              slide.icon,
              size: 52,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 36),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFF5F0E8),
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF8F877F),
              fontSize: 16,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Returns true if the user has already seen the credits onboarding.
Future<bool> creditosOnboardingDone() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(kPrefsOnboardingCreditos) ?? false;
}
