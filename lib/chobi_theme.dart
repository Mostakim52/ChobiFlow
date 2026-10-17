import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ChobiFlow signature theme — "Marigold Flow on Ink"
/// Ink #131022, Plum #21183D, Marigold #FFB020, Flow Teal #2DD4BF,
/// Cream #FFF9EC, Violet #5B2EEE
class ChobiColors {
  static const ink = Color(0xFF131022);
  static const plum = Color(0xFF21183D);
  static const plumSoft = Color(0xFF2E2154);
  static const marigold = Color(0xFFFFB020);
  static const marigoldDeep = Color(0xFFE68A00);
  static const flowTeal = Color(0xFF2DD4BF);
  static const flowTealDeep = Color(0xFF0E9F8A);
  static const cream = Color(0xFFFFF9EC);
  static const paper = Color(0xFFFFFFFF);
  static const violet = Color(0xFF5B2EEE);
  static const blush = Color(0xFFFF6B6B);
  static const lavenderMist = Color(0xFFE9E4FF);

  static const collectionPalette = [
    Color(0xFF5B2EEE),
    Color(0xFFFFB020),
    Color(0xFF0E9F8A),
    Color(0xFFFF6B6B),
    Color(0xFF3B82F6),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF14B8A6),
  ];
}

class ChobiTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: ChobiColors.violet,
        secondary: ChobiColors.flowTealDeep,
        tertiary: ChobiColors.marigoldDeep,
        surface: Colors.white,
        error: ChobiColors.blush,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: ChobiColors.cream,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(base.textTheme, Brightness.light),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: ChobiColors.ink,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: Color(0xFFEEE6D6), width: 1),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: ChobiColors.violet,
        unselectedItemColor: Color(0xFF9A93B2),
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: ChobiColors.ink,
        foregroundColor: Colors.white,
        elevation: 6,
        shape: StadiumBorder(),
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: ChobiColors.marigold,
        secondary: ChobiColors.flowTeal,
        tertiary: ChobiColors.lavenderMist,
        surface: ChobiColors.plum,
        error: ChobiColors.blush,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: ChobiColors.ink,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(base.textTheme, Brightness.dark),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: ChobiColors.plum,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: Color(0xFF3A2E63), width: 1),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: ChobiColors.plum,
        selectedItemColor: ChobiColors.marigold,
        unselectedItemColor: Color(0xFF8E86AD),
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: ChobiColors.marigold,
        foregroundColor: ChobiColors.ink,
        elevation: 6,
        shape: StadiumBorder(),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme t, Brightness b) {
    final display = GoogleFonts.soraTextTheme(t);
    final body = GoogleFonts.interTextTheme(display);
    return body.copyWith(
      displayLarge: body.displayLarge?.copyWith(
          fontWeight: FontWeight.w800, letterSpacing: -1.5, height: 1.0),
      displayMedium: body.displayMedium?.copyWith(
          fontWeight: FontWeight.w800, letterSpacing: -1.0),
      displaySmall: body.displaySmall?.copyWith(fontWeight: FontWeight.w800),
      headlineLarge:
          body.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
      headlineMedium:
          body.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineSmall: body.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: body.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: body.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

/// Animated gradient ribbon — the signature "Flow" element.
class FlowRibbon extends StatelessWidget {
  final double height;
  final double opacity;
  const FlowRibbon({super.key, this.height = 56, this.opacity = 1});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: CustomPaint(
        painter: _RibbonPainter(),
        size: Size(double.infinity, height),
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final marigoldPath = Path()
      ..moveTo(-20, h * 0.72)
      ..cubicTo(w * 0.25, h * 0.15, w * 0.45, h * 1.05, w * 0.72, h * 0.38)
      ..cubicTo(w * 0.85, h * 0.12, w * 0.95, h * 0.45, w + 20, h * 0.32);
    canvas.drawPath(
      marigoldPath,
      Paint()
        ..color = const Color(0xFFFFB020)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round,
    );
    final tealPath = Path()
      ..moveTo(-20, h * 0.86)
      ..cubicTo(w * 0.3, h * 0.45, w * 0.55, h * 1.1, w * 0.78, h * 0.58)
      ..cubicTo(w * 0.9, h * 0.38, w * 0.96, h * 0.6, w + 20, h * 0.52);
    canvas.drawPath(
      tealPath,
      Paint()
        ..color = const Color(0xFF2DD4BF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
