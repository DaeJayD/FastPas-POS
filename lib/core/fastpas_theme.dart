import 'package:flutter/material.dart';

/// Semantic roles shared by the release screens and their dialogs.
@immutable
class PosColors extends ThemeExtension<PosColors> {
  const PosColors({
    required this.background,
    required this.surface,
    required this.subtle,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accentText,
    required this.accentSoft,
    required this.warning,
    required this.warningSurface,
    required this.success,
    required this.error,
  });
  final Color background,
      surface,
      subtle,
      border,
      text,
      muted,
      accent,
      accentText,
      accentSoft,
      warning,
      warningSurface,
      success,
      error;
  static const porcelain = PosColors(
    background: Color(0xFFF5F6F2),
    surface: Colors.white,
    subtle: Color(0xFFF0F2EB),
    border: Color(0xFFDCE1D7),
    text: Color(0xFF20291E),
    muted: Color(0xFF626E5F),
    accent: Color(0xFFCEF54A),
    accentText: Color(0xFF1C260E),
    accentSoft: Color(0xFFEDF4DC),
    warning: Color(0xFF934618),
    warningSurface: Color(0xFFFFF0DF),
    success: Color(0xFF466634),
    error: Color(0xFF9B3726),
  );
  static const forest = PosColors(
    background: Color(0xFF101312),
    surface: Color(0xFF191E1B),
    subtle: Color(0xFF242D25),
    border: Color(0xFF303932),
    text: Color(0xFFF0F3ED),
    muted: Color(0xFFA2AEA4),
    accent: Color(0xFFCEF54A),
    accentText: Color(0xFF1C260E),
    accentSoft: Color(0xFF28331F),
    warning: Color(0xFFFFC49F),
    warningSurface: Color(0xFF493326),
    success: Color(0xFFB5D79C),
    error: Color(0xFFFFB6A3),
  );
  @override
  PosColors copyWith() => this;
  @override
  PosColors lerp(covariant PosColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return PosColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      subtle: mix(subtle, other.subtle),
      border: mix(border, other.border),
      text: mix(text, other.text),
      muted: mix(muted, other.muted),
      accent: mix(accent, other.accent),
      accentText: mix(accentText, other.accentText),
      accentSoft: mix(accentSoft, other.accentSoft),
      warning: mix(warning, other.warning),
      warningSurface: mix(warningSurface, other.warningSurface),
      success: mix(success, other.success),
      error: mix(error, other.error),
    );
  }
}

extension PosThemeContext on BuildContext {
  PosColors get pos =>
      Theme.of(this).extension<PosColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? PosColors.forest
          : PosColors.porcelain);
}

abstract final class Volt {
  // Compatibility aliases for the separate legacy preview. Release widgets use context.pos.
  static const ink = Color(0xFF20291E), lime = Color(0xFFCEF54A);
  static const background = Color(0xFFF5F6F2),
      line = Color(0xFFDCE1D7),
      muted = Color(0xFF626E5F),
      soft = Color(0xFFF0F2EB),
      surface = Colors.white;
  static final ThemeData theme = _build(PosColors.porcelain, Brightness.light);
  static final ThemeData darkTheme = _build(PosColors.forest, Brightness.dark);
  static ThemeData _build(PosColors p, Brightness brightness) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: p.accent,
          brightness: brightness,
        ).copyWith(
          primary: brightness == Brightness.dark
              ? p.accent
              : const Color(0xFF456315),
          onPrimary: brightness == Brightness.dark
              ? p.accentText
              : Colors.white,
          secondary: p.accent,
          onSecondary: p.accentText,
          surface: p.surface,
          onSurface: p.text,
          onSurfaceVariant: p.muted,
          outline: p.muted,
          outlineVariant: p.border,
          error: p.error,
          surfaceContainerHighest: p.subtle,
        );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: p.border),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Roboto',
      colorScheme: scheme,
      extensions: [p],
      scaffoldBackgroundColor: p.background,
      disabledColor: p.muted.withValues(alpha: .55),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.text,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          color: p.text,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: p.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.border),
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          color: p.text,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: TextStyle(color: p.muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.accentText,
          disabledBackgroundColor: p.subtle,
          disabledForegroundColor: p.muted,
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          minimumSize: const Size(48, 48),
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.accentText,
          minimumSize: const Size(48, 48),
          elevation: 0,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.accentSoft,
        labelStyle: TextStyle(fontFamily: 'Roboto', color: p.text),
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.accentSoft,
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.text,
        contentTextStyle: TextStyle(color: p.background),
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
          child: CustomPaint(
            painter: _SpeedMark(Theme.of(context).colorScheme.onSurface),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'FastPas',
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
            color: context.pos.text,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'POS',
          style: TextStyle(
            fontSize: size * .47,
            fontWeight: FontWeight.w700,
            color: context.pos.muted,
          ),
        ),
      ],
    ),
  );
}

class FastPasMark extends StatelessWidget {
  const FastPasMark({super.key});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _SpeedMark(Theme.of(context).colorScheme.onSurface));
}

class _SpeedMark extends CustomPainter {
  _SpeedMark(this.foreground);
  final Color foreground;
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
    canvas.drawPath(large, Paint()..color = foreground);
  }

  @override
  bool shouldRepaint(covariant _SpeedMark oldDelegate) =>
      oldDelegate.foreground != foreground;
}
