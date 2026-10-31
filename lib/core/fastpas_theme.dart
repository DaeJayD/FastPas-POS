import 'package:flutter/material.dart';

abstract final class Volt {
  static const ink = Color(0xFF202528);
  static const lime = Color(0xFFCEF54A);
  static const background = Color(0xFFEDF0F2);
  static const line = Color(0xFFD6DEE2);
  static const muted = Color(0xFF5D6870);
  static const soft = Color(0xFFE5EBEE);
  static const surface = Color(0xFFF9FAFB);

  static final ThemeData theme = _buildTheme();

  static ThemeData _buildTheme() {
    final scheme = ColorScheme.fromSeed(seedColor: ink).copyWith(
      primary: ink,
      onPrimary: Colors.white,
      secondary: lime,
      onSecondary: ink,
      surface: surface,
      onSurface: ink,
      outline: muted,
      outlineVariant: line,
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: line),
    );
    return ThemeData(
      fontFamily: 'Roboto',
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
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: line),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: 'Roboto',
          color: ink,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: ink, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        hintStyle: const TextStyle(color: muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: lime,
          foregroundColor: ink,
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: lime.withValues(alpha: .24),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected) ? ink : muted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            fontSize: 12,
          ),
        ),
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
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size * 1.15,
          height: size,
          child: CustomPaint(painter: _SpeedMark()),
        ),
        const SizedBox(width: 10),
        Text(
          'FastPas',
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
            color: Volt.ink,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'POS',
          style: TextStyle(
            fontSize: size * .47,
            fontWeight: FontWeight.w700,
            color: Volt.muted,
          ),
        ),
      ],
    ),
  );
}

class FastPasMark extends StatelessWidget {
  const FastPasMark({super.key});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _SpeedMark());
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
