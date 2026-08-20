import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  // Logo
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8763A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF1A1A1A),
                                width: 3,
                              ),
                            ),
                          ),
                          Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              color: Color(0xFF1A1A1A),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'AURA.',
                    style: TextStyle(
                      color: Color(0xFFE8763A),
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'MOVÉ. EXPLORÁ. VIVÍ.',
                    style: TextStyle(
                      color: Color(0xFF5A534D),
                      fontSize: 13,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'El primer marketplace de fitness\ny experiencias de Buenos Aires.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFF5F0E8),
                      fontSize: 16,
                      height: 1.55,
                    ),
                  ),
                  const Spacer(),
                  // Botones
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => context.go('/login?rol=estudio'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE8763A),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: const Text('Soy un estudio'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => context.go('/login?rol=usuario'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF5F0E8),
                        side: const BorderSide(color: Color(0xFF3A3A3A), width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Quiero reservar'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () => context.go('/explorar'),
                    child: const Text(
                      'Explorar sin cuenta',
                      style: TextStyle(
                        color: Color(0xFFF5F0E8),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => context.go('/login'),
                    child: const Text(
                      '¿Ya tenés cuenta? Iniciá sesión',
                      style: TextStyle(
                        color: Color(0xFF5A534D),
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xFF5A534D),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
