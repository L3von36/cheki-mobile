import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Cheki design tokens — extracted from the web app's globals.css so the
/// mobile app feels like the same product.
abstract final class ChekiPalette {
  // Shared accents.
  static const Color green = Color(0xFF2DDB6A);
  static const Color greenDark = Color(0xFF20B854);
  static const Color greenInk = Color(0xFF16A34A);
  static const Color greenDeep = Color(0xFF0A7B43);
  static const Color red = Color(0xFFF0556A);
  static const Color redInk = Color(0xFFDC2626);
  static const Color amber = Color(0xFFF5B049);

  // Dark scheme (default).
  static const Color dBg = Color(0xFF0C0D10);
  static const Color dSurface = Color(0xFF16181D);
  static const Color dSurfaceAlt = Color(0xFF1C1F26);
  static const Color dReceipt = Color(0xFF131519);
  static const Color dBorder = Color(0xFF262932);
  static const Color dInk = Color(0xFFE8E6E3);
  static const Color dInkDim = Color(0xFF9BA0A8);
  static const Color dInkFaint = Color(0xFF5C6068);
  static const Color dDotted = Color(0xFF2A2E38);
  static const Color dField = Color(0xFF101216);

  // Light scheme.
  static const Color lBg = Color(0xFFFAF9F6);
  static const Color lSurface = Color(0xFFFFFFFF);
  static const Color lSurfaceAlt = Color(0xFFF5F2EC);
  static const Color lReceipt = Color(0xFFF8F6F0);
  static const Color lBorder = Color(0xFFE5E2DC);
  static const Color lInk = Color(0xFF1A1A1A);
  static const Color lInkDim = Color(0xFF5D6167);
  static const Color lInkFaint = Color(0xFF9B9FA6);
  static const Color lDotted = Color(0xFFD4D0C8);
}

/// Builds the light and dark [ThemeData] for the app.
abstract final class ChekiTheme {
  static ThemeData dark() => _build(Brightness.dark);
  static ThemeData light() => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = isDark
        ? ColorScheme.dark(
            surface: ChekiPalette.dSurface,
            primary: ChekiPalette.green,
            onPrimary: const Color(0xFF07130B),
            secondary: ChekiPalette.greenDark,
            error: ChekiPalette.red,
            outline: ChekiPalette.dBorder,
            surfaceContainerHighest: ChekiPalette.dSurfaceAlt,
          )
        : ColorScheme.light(
            surface: ChekiPalette.lSurface,
            primary: ChekiPalette.greenInk,
            onPrimary: Colors.white,
            secondary: ChekiPalette.greenDeep,
            error: ChekiPalette.redInk,
            outline: ChekiPalette.lBorder,
            surfaceContainerHighest: ChekiPalette.lSurfaceAlt,
          );

    final bg = isDark ? ChekiPalette.dBg : ChekiPalette.lBg;
    final ink = isDark ? ChekiPalette.dInk : ChekiPalette.lInk;

    final baseText = GoogleFonts.interTextTheme(
      ThemeData(brightness: brightness).textTheme,
    ).apply(bodyColor: ink, displayColor: ink);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
      textTheme: baseText.copyWith(
        headlineLarge: baseText.headlineLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleLarge: baseText.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        bodyMedium: baseText.bodyMedium?.copyWith(height: 1.45),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? ChekiPalette.dField : ChekiPalette.lSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ChekiPalette.green, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.error, width: 1.4),
        ),
        hintStyle: TextStyle(
          color: isDark ? ChekiPalette.dInkFaint : ChekiPalette.lInkFaint,
          fontWeight: FontWeight.w400,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? ChekiPalette.dSurface : ChekiPalette.lSurface,
        modalBackgroundColor:
            isDark ? ChekiPalette.dSurface : ChekiPalette.lSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? ChekiPalette.dSurfaceAlt : ChekiPalette.lInk,
        contentTextStyle: GoogleFonts.inter(
          color: isDark ? ChekiPalette.dInk : ChekiPalette.lBg,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: ink),
        titleTextStyle: GoogleFonts.inter(
          color: ink,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Mono text style used for references, amounts and meta labels.
TextStyle monoStyle({
  double size = 14,
  FontWeight weight = FontWeight.w500,
  Color? color,
  double letterSpacing = 0,
}) {
  return GoogleFonts.jetBrainsMono(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
  );
}
