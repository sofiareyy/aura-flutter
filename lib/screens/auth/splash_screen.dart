import 'package:flutter/material.dart';

import 'onboarding_screen.dart';

class AuthSplashScreen extends StatefulWidget {
  const AuthSplashScreen({super.key});

  @override
  State<AuthSplashScreen> createState() => _AuthSplashScreenState();
}

class _AuthSplashScreenState extends State<AuthSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..forward();
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _runTransition();
  }

  Future<void> _runTransition() async {
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (!mounted || _navigating) return;
    _navigating = true;
    await _controller.reverse();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, __, ___) => const AuthOnboardingScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(scaffoldBackgroundColor: const Color(0xFF0D0D0D)),
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D0D),
        body: SizedBox.expand(
          child: FadeTransition(
            opacity: _fade,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 176,
                    height: 176,
                    decoration: const BoxDecoration(
                      color: Color(0xFF24150F),
                      shape: BoxShape.circle,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8763A),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF0D0D0D),
                                      width: 2.5,
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF0D0D0D),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'AURA.',
                          style: TextStyle(
                            color: Color(0xFFF5F0E8),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'MOVÉ. EXPLORÁ. VIVÍ.',
                          style: TextStyle(
                            color: Color(0xFF5A534D),
                            fontSize: 11,
                            letterSpacing: 1.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 34),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      _SplashDot(active: true),
                      SizedBox(width: 8),
                      _SplashDot(),
                      SizedBox(width: 8),
                      _SplashDot(),
                    ],
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

class _SplashDot extends StatelessWidget {
  final bool active;

  const _SplashDot({this.active = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: active ? 6 : 5,
      height: active ? 6 : 5,
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE8763A) : const Color(0xFF45413D),
        shape: BoxShape.circle,
      ),
    );
  }
}
