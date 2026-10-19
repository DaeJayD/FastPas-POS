import 'package:flutter/material.dart';

abstract final class Volt {
  static const ink = Color(0xFF202528);
  static const lime = Color(0xFFCEF54A);
  static const background = Color(0xFFFAFAFA);
  static const line = Color(0xFFE7E9EB);
  static const muted = Color(0xFF697178);
  static const soft = Color(0xFFF0F2F3);

  static ThemeData get theme {
    final scheme = ColorScheme.fromSeed(seedColor: ink).copyWith(
      primary: ink,
      onPrimary: Colors.white,
      secondary: lime,
      onSecondary: ink,
      surface: Colors.white,
      onSurface: ink,
      outline: muted,
      outlineVariant: line,
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: line),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        titleTextStyle:
            TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: ink, width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        hintStyle: const TextStyle(color: muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: lime,
          foregroundColor: ink,
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: lime.withValues(alpha: .24),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              color: states.contains(WidgetState.selected) ? ink : muted,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              fontSize: 12,
            )),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class FastPasBrand extends StatelessWidget {
  const FastPasBrand({super.key, this.size = 27});
  final double size;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size * 1.15,
            height: size,
            child: CustomPaint(painter: _SpeedMark()),
          ),
          const SizedBox(width: 10),
          Text('FastPas',
              style: TextStyle(
                  fontSize: size,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                  color: Volt.ink)),
          const SizedBox(width: 6),
          Text('POS',
              style: TextStyle(
                  fontSize: size * .47,
                  fontWeight: FontWeight.w700,
                  color: Volt.muted)),
        ],
      );
}

class _SpeedMark extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final small = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width * .27, size.height * .46)
      ..lineTo(size.width * .54, size.height * .46)
      ..lineTo(size.width * .27, size.height)
      ..close();
    final large = Path()
      ..moveTo(size.width * .33, size.height)
      ..lineTo(size.width * .73, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width * .60, size.height)
      ..close();
    canvas.drawPath(small, Paint()..color = Volt.lime);
    canvas.drawPath(large, Paint()..color = Volt.ink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
