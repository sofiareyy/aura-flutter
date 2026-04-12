import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AuraGestionDesign {
  static const Color background = Color(0xFFF7F5F2);
  static const Color card = Color(0xFFFFFFFF);
  static const Color premiumCard = Color(0xFF1A1A1A);
  static const Color accent = Color(0xFFE8763A);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF888888);
  static const Color border = Color(0xFFE8E5E0);
  static const Color softBadge = Color(0xFFFDF0E8);
  static const Color creamText = Color(0xFFF7F5F2);
  static const Color shimmerBase = Color(0xFFF0EDE8);
  static const Color shimmerHighlight = Color(0xFFE8E5E0);
  static const Color successBg = Color(0xFF1A1A1A);
  static const Color errorBg = Color(0xFFFF4444);

  static const double horizontalPadding = 20;
  static const double sectionSpacing = 24;
  static const double cardRadius = 16;
  static const double buttonRadius = 12;

  static const BoxShadow softShadow = BoxShadow(
    color: Color(0x141A1A1A),
    blurRadius: 12,
    offset: Offset(0, 2),
  );

  static TextStyle titleStyle({
    Color color = textPrimary,
    double size = 22,
  }) {
    return GoogleFonts.dmSans(
      fontSize: size,
      fontWeight: FontWeight.w600,
      color: color,
    );
  }

  static TextStyle sectionLabelStyle() {
    return GoogleFonts.dmSans(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.5,
      color: textSecondary,
    );
  }

  static TextStyle bodyStyle({
    Color color = textPrimary,
    double size = 15,
    FontWeight weight = FontWeight.w400,
  }) {
    return GoogleFonts.dmSans(
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }

  static ButtonStyle primaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: accent,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 52),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(buttonRadius),
      ),
      textStyle: bodyStyle(
        color: Colors.white,
        weight: FontWeight.w600,
      ),
    );
  }

  static ButtonStyle secondaryButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: accent,
      minimumSize: const Size(double.infinity, 52),
      side: const BorderSide(color: accent),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(buttonRadius),
      ),
      textStyle: bodyStyle(
        color: accent,
        weight: FontWeight.w600,
      ),
    );
  }

  static InputDecoration inputDecoration({
    required String label,
    String? hint,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      labelStyle: bodyStyle(color: textSecondary, size: 14),
      hintStyle: bodyStyle(color: textSecondary, size: 14),
      filled: true,
      fillColor: card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(buttonRadius),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(buttonRadius),
        borderSide: const BorderSide(color: accent, width: 1.4),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(buttonRadius),
        borderSide: const BorderSide(color: border),
      ),
    );
  }

  static void showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: successBg,
        content: Text(
          message,
          style: bodyStyle(color: creamText, size: 14),
        ),
      ),
    );
  }

  static void showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: errorBg,
        content: Text(
          message,
          style: bodyStyle(color: Colors.white, size: 14),
        ),
      ),
    );
  }
}

class AuraShimmerBox extends StatefulWidget {
  final double height;
  final double width;
  final BorderRadius borderRadius;

  const AuraShimmerBox({
    super.key,
    required this.height,
    required this.width,
    required this.borderRadius,
  });

  @override
  State<AuraShimmerBox> createState() => _AuraShimmerBoxState();
}

class _AuraShimmerBoxState extends State<AuraShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1 + (2 * _controller.value), 0),
              end: Alignment(1 + (2 * _controller.value), 0),
              colors: const [
                AuraGestionDesign.shimmerBase,
                AuraGestionDesign.shimmerHighlight,
                AuraGestionDesign.shimmerBase,
              ],
              stops: const [0.1, 0.3, 0.4],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: AuraGestionDesign.shimmerBase,
              borderRadius: widget.borderRadius,
            ),
          ),
        );
      },
    );
  }
}
