import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _controller.forward();

    Future.delayed(const Duration(milliseconds: 1500), () async {
      if (!mounted) return;
      await _controller.reverse();
      if (!mounted) return;
      _navigate();
    });
  }

  void _navigate() {
    final isLoggedIn = Supabase.instance.client.auth.currentUser != null;
    context.go(isLoggedIn ? '/home' : '/onboarding');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: FadeTransition(
        opacity: _controller,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ícono Aura: círculo naranja con punto negro
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8763A),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(
                      color: Color(0xFF0D0D0D),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'AURA.',
                style: GoogleFonts.dmSans(
                  color: const Color(0xFFFFFFFF),
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.15,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'MOVÉ. EXPLORÁ. VIVÍ.',
                style: TextStyle(
                  color: Color(0xFF666666),
                  fontSize: 11,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
