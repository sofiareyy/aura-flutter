import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

class AuthOnboardingScreen extends StatefulWidget {
  const AuthOnboardingScreen({super.key});

  @override
  State<AuthOnboardingScreen> createState() => _AuthOnboardingScreenState();
}

class _AuthOnboardingScreenState extends State<AuthOnboardingScreen> {
  final _pageCtrl = PageController();
  int _currentPage = 0;

  static const _slides = [
    _Slide(
      titleStart: 'Tu mundo de\n',
      highlight: 'experiencias',
      titleEnd: '',
      subtitle:
          'Fitness, arte, bienestar y más\ntodo en un solo lugar para\nreservar con tus créditos.',
      graphic: _SlideGraphic.ring,
    ),
    _Slide(
      titleStart: 'Usá tus ',
      highlight: 'créditos',
      titleEnd: '\ncomo quieras',
      subtitle:
          'Comprá packs cuando quieras\ny usalos para reservar lo que\nmás te guste.',
      graphic: _SlideGraphic.credits,
    ),
    _Slide(
      titleStart: 'Descubrí lugares\n',
      highlight: 'nuevos',
      titleEnd: '',
      subtitle:
          'Más de 10 espacios en\nBuenos Aires esperándote.\nNuevos estudios cada semana.',
      graphic: _SlideGraphic.places,
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
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      context.go('/register');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blackDeep,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: _slides.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) => _SlidePage(
                  slide: _slides[index],
                  currentPage: _currentPage,
                  pageIndex: index,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _next,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.blackDeep,
                      ),
                      child: Text(
                        _currentPage == _slides.length - 1
                            ? 'Empezar ahora'
                            : 'Siguiente',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => context.go('/login'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6E6761),
                        side: const BorderSide(color: Color(0xFF2A2A2A)),
                        backgroundColor: const Color(0xFF131313),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text(
                        'Ya tengo cuenta',
                        style: TextStyle(
                          color: Color(0xFF67615B),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlidePage extends StatelessWidget {
  final _Slide slide;
  final int currentPage;
  final int pageIndex;

  const _SlidePage({
    required this.slide,
    required this.currentPage,
    required this.pageIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '0${pageIndex + 1} / 03',
            style: const TextStyle(
              color: Color(0xFF47433F),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(
              3,
              (index) => Container(
                margin: const EdgeInsets.only(right: 7),
                width: index == currentPage ? 22 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: index == currentPage
                      ? AppColors.primary
                      : const Color(0xFF3A3937),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                SizedBox(
                  height: 250,
                  child: _Artwork(graphic: slide.graphic),
                ),
                const SizedBox(height: 6),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      color: Color(0xFFF6F1EB),
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                    children: [
                      TextSpan(text: slide.titleStart),
                      TextSpan(
                        text: slide.highlight,
                        style: const TextStyle(color: AppColors.primary),
                      ),
                      TextSpan(text: slide.titleEnd),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  slide.subtitle,
                  style: const TextStyle(
                    color: Color(0xFF6E6761),
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  final _SlideGraphic graphic;

  const _Artwork({required this.graphic});

  @override
  Widget build(BuildContext context) {
    switch (graphic) {
      case _SlideGraphic.ring:
        return Stack(
          children: [
            Positioned(
              left: 6,
              top: 16,
              child: Container(
                width: 198,
                height: 198,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF2D1A12),
                    width: 10,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 100,
              top: 82,
              child: Container(
                width: 66,
                height: 66,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF3A2318),
                ),
              ),
            ),
            Positioned(
              right: 6,
              top: 34,
              child: Container(
                width: 78,
                height: 78,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x221E120D),
                ),
              ),
            ),
          ],
        );
      case _SlideGraphic.credits:
        return Stack(
          children: [
            Positioned(
              left: 28,
              top: 50,
              child: Container(
                width: 192,
                height: 132,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: const Color(0xFF2D1A12),
                    width: 9,
                  ),
                ),
              ),
            ),
            const Positioned(
              left: 58,
              top: 100,
              child: _Bubble(size: 36),
            ),
            const Positioned(
              left: 96,
              top: 80,
              child: _Bubble(size: 40),
            ),
            const Positioned(
              left: 136,
              top: 102,
              child: _Bubble(size: 34),
            ),
          ],
        );
      case _SlideGraphic.places:
        return Stack(
          children: [
            Positioned(
              left: 88,
              top: 22,
              child: Container(
                width: 142,
                height: 142,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF2D1A12),
                    width: 10,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 14,
              top: 18,
              child: Icon(
                Icons.close_rounded,
                size: 44,
                color: const Color(0xFF4A2B1D),
              ),
            ),
          ],
        );
    }
  }
}

class _Bubble extends StatelessWidget {
  final double size;

  const _Bubble({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFF3A2318),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _Slide {
  final String titleStart;
  final String highlight;
  final String titleEnd;
  final String subtitle;
  final _SlideGraphic graphic;

  const _Slide({
    required this.titleStart,
    required this.highlight,
    required this.titleEnd,
    required this.subtitle,
    required this.graphic,
  });
}

enum _SlideGraphic { ring, credits, places }
