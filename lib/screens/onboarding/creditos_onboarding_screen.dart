import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';

const _kPrefsKey = 'creditos_onboarding_done';

class CreditosOnboardingScreen extends StatefulWidget {
  const CreditosOnboardingScreen({super.key});

  @override
  State<CreditosOnboardingScreen> createState() =>
      _CreditosOnboardingScreenState();
}

class _CreditosOnboardingScreenState extends State<CreditosOnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _slides = [
    _Slide(
      icon: Icons.toll_rounded,
      title: '¿Qué son los créditos?',
      body:
          'Los créditos son la moneda de Aura. Cada clase tiene un valor en créditos y vos reservás con un solo toque, sin complicaciones.',
    ),
    _Slide(
      icon: Icons.card_giftcard_rounded,
      title: '¿Cómo conseguirlos?',
      body:
          'Comprá un pack de créditos cuando lo necesites, o suscribite a un plan mensual y recibís créditos automáticamente cada mes.',
    ),
    _Slide(
      icon: Icons.calendar_today_rounded,
      title: '¡A reservar!',
      body:
          'Explorá cientos de clases, elegí tu horario favorito y reservá al instante. Tu próxima clase te está esperando.',
    ),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefsKey, true);
    if (!mounted) return;
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
  return prefs.getBool(_kPrefsKey) ?? false;
}
