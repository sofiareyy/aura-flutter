import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageCtrl = PageController();
  int _currentPage = 0;

  static const _slides = [
    _Slide(
      titleBefore: 'Tu mundo de\n',
      titleHighlight: 'experiencias',
      titleAfter: '',
      subtitle:
          'Fitness, arte, bienestar y más\ntodo en un solo lugar para\nreservar con tus créditos.',
    ),
    _Slide(
      titleBefore: 'Usá tus ',
      titleHighlight: 'créditos',
      titleAfter: '\ncomo quieras',
      subtitle:
          'Comprá packs cuando quieras\ny usalos para reservar lo que\nmás te guste.',
    ),
    _Slide(
      titleBefore: 'Descubrí lugares\n',
      titleHighlight: 'nuevos',
      titleAfter: '',
      subtitle:
          'Más de 10 espacios en\nBuenos Aires esperándote.\nNuevos estudios cada semana.',
    ),
  ];

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _slides.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      context.go('/register');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageCtrl,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: _slides.length,
            itemBuilder: (context, index) {
              return AnimatedBuilder(
                animation: _pageCtrl,
                builder: (context, child) {
                  final page = _pageCtrl.hasClients
                      ? (_pageCtrl.page ?? index.toDouble())
                      : index.toDouble();
                  final opacity =
                      (1.0 - (page - index).abs()).clamp(0.0, 1.0);
                  return Opacity(opacity: opacity, child: child!);
                },
                child: _SlideContent(slide: _slides[index]),
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Text(
                '0${_currentPage + 1} / 0${_slides.length}',
                style: const TextStyle(
                  color: Color(0xFF555555),
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _slides.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _currentPage == i
                                ? const Color(0xFFE8763A)
                                : const Color(0xFF333333),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE8763A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          _currentPage == _slides.length - 1
                              ? 'Empezar ahora'
                              : 'Siguiente',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (_currentPage == _slides.length - 1) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton(
                          onPressed: () => context.go('/login'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Ya tengo cuenta',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideContent extends StatelessWidget {
  final _Slide slide;

  const _SlideContent({required this.slide});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 56),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Transform.translate(
                      offset: const Offset(0, -16),
                      child: Container(
                        width: 240,
                        height: 240,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1A1A1A),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            size: 72,
                            color: Color(0xFFE8763A),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                      children: [
                        TextSpan(text: slide.titleBefore),
                        TextSpan(
                          text: slide.titleHighlight,
                          style: const TextStyle(color: Color(0xFFE8763A)),
                        ),
                        TextSpan(text: slide.titleAfter),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    slide.subtitle,
                    style: const TextStyle(
                      color: Color(0xFFA7A19A),
                      fontSize: 16,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide {
  final String titleBefore;
  final String titleHighlight;
  final String titleAfter;
  final String subtitle;

  const _Slide({
    required this.titleBefore,
    required this.titleHighlight,
    required this.titleAfter,
    required this.subtitle,
  });
}
