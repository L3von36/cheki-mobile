import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Mahtem design tokens — "Payment Verifier" fintech look:
/// navy ink, blue gradient hero, green actions, soft icon circles.
abstract final class MahtemPalette {
  // Brand accents.
  static const Color green = Color(0xFF22A45D);
  static const Color greenDeep = Color(0xFF168A4C);
  static const Color greenSoft = Color(0xFFE1F5EA);
  static const Color navy = Color(0xFF1C2B5E);
  static const Color blue = Color(0xFF2E6BE6);
  static const Color blueLight = Color(0xFF5B8DEF);
  static const Color blueSoft = Color(0xFFE4EEFC);
  static const Color blueSoftDark = Color(0xFF1D2B4E);
  static const Color red = Color(0xFFEF4444);
  static const Color redSoft = Color(0xFFFDEAEA);
  static const Color amber = Color(0xFFF59E0B);
  static const Color amberSoft = Color(0xFFFEF3E2);

  // Light scheme.
  static const Color lBg = Color(0xFFF3F6FC);
  static const Color lCard = Color(0xFFFFFFFF);
  static const Color lBorder = Color(0xFFE4EAF3);
  static const Color lInk = Color(0xFF16224D);
  static const Color lInkDim = Color(0xFF64748B);
  static const Color lInkFaint = Color(0xFF94A3B8);

  // Dark scheme.
  static const Color dBg = Color(0xFF0B1220);
  static const Color dCard = Color(0xFF141C30);
  static const Color dCardAlt = Color(0xFF1A2440);
  static const Color dBorder = Color(0xFF243049);
  static const Color dInk = Color(0xFFE6EBF5);
  static const Color dInkDim = Color(0xFF94A3B8);
  static const Color dInkFaint = Color(0xFF64748B);

  /// Splash / hero gradient (deep navy like the design's splash screen).
  static const List<Color> splashGradient = [
    Color(0xFF1B2C63),
    Color(0xFF24418F),
  ];

  /// Blue gradient used by the home hero card.
  static const List<Color> heroGradient = [
    Color(0xFF2E6BE6),
    Color(0xFF5590F2),
  ];

  /// Green gradient for primary buttons.
  static const List<Color> buttonGradient = [
    Color(0xFF2CB168),
    Color(0xFF1E9455),
  ];
}

/// Builds the light and dark [ThemeData] for the app.
abstract final class MahtemTheme {
  /// Font family used in Amharic mode. Noto Sans Ethiopic ships bundled
  /// with the app (pubspec fonts) — no runtime download, works offline.
  /// Inter has no Ge'ez (ግዕዝ) glyphs, so Amharic mode needs the Ethiopic
  /// face for everything, not just body text.
  static const String ethiopicFamily = 'Noto Sans Ethiopic';

  /// Ethiopic glyphs carry tall diacritics and stacked marks — the tight
  /// Latin line heights (1.15) clip them. One notch of extra air in
  /// Amharic mode keeps every headline fully visible.
  static double _headingHeight(bool ethiopic) => ethiopic ? 1.3 : 1.15;

  static ThemeData dark({bool ethiopicFont = false}) =>
      _build(Brightness.dark, ethiopicFont: ethiopicFont);

  static ThemeData light({bool ethiopicFont = false}) =>
      _build(Brightness.light, ethiopicFont: ethiopicFont);

  static ThemeData _build(Brightness brightness, {bool ethiopicFont = false}) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = isDark
        ? ColorScheme.dark(
            surface: MahtemPalette.dBg,
            primary: MahtemPalette.green,
            onPrimary: Colors.white,
            secondary: MahtemPalette.blueLight,
            error: MahtemPalette.red,
            outline: MahtemPalette.dBorder,
            surfaceContainerHighest: MahtemPalette.dCardAlt,
          )
        : ColorScheme.light(
            surface: MahtemPalette.lBg,
            primary: MahtemPalette.green,
            onPrimary: Colors.white,
            secondary: MahtemPalette.blue,
            error: MahtemPalette.red,
            outline: MahtemPalette.lBorder,
            surfaceContainerHighest: MahtemPalette.blueSoft,
          );

    final bg = isDark ? MahtemPalette.dBg : MahtemPalette.lBg;
    final ink = isDark ? MahtemPalette.dInk : MahtemPalette.lInk;
    final dim = isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim;
    final border = isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder;
    final card = isDark ? MahtemPalette.dCard : MahtemPalette.lCard;

    final baseText = ethiopicFont
        ? ThemeData(brightness: brightness).textTheme.apply(
            fontFamily: ethiopicFamily,
            bodyColor: ink,
            displayColor: ink,
          )
        : GoogleFonts.interTextTheme(
            ThemeData(brightness: brightness).textTheme,
          ).apply(bodyColor: ink, displayColor: ink);

    // Same face for the one-off text styles below so no Amharic string
    // ever renders in a font missing its glyphs.
    TextStyle uiTextStyle({
      Color? color,
      double? fontSize,
      FontWeight? fontWeight,
      double letterSpacing = 0,
    }) => TextStyle(
      fontFamily: ethiopicFont ? ethiopicFamily : 'Inter',
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
    );

    // Compact type scale — deliberately one notch smaller than Material
    // defaults so the UI feels dense, calm and pro.
    final headingH = _headingHeight(ethiopicFont);
    final textTheme = baseText.copyWith(
      headlineLarge: baseText.headlineLarge?.copyWith(
        fontSize: 23,
        fontWeight: FontWeight.w800,
        height: headingH,
      ),
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        height: headingH,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        height: headingH,
      ),
      titleMedium: baseText.titleMedium?.copyWith(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: baseText.titleSmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: baseText.bodyLarge?.copyWith(fontSize: 13, height: 1.5),
      bodyMedium: baseText.bodyMedium?.copyWith(fontSize: 12, height: 1.5),
      bodySmall: baseText.bodySmall?.copyWith(fontSize: 10.5, height: 1.45),
      labelLarge: baseText.labelLarge?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: baseText.labelMedium?.copyWith(fontSize: 10.5),
      labelSmall: baseText.labelSmall?.copyWith(fontSize: 9.5),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: MahtemPalette.green, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: colorScheme.error, width: 1.3),
        ),
        // InputDecorator does NOT merge these with the ambient text theme
        // — without the explicit family, Amharic hints render in a font
        // with no Ge'ez glyphs (the "ugly UI" bug).
        hintStyle: uiTextStyle(
          color: isDark ? MahtemPalette.dInkFaint : MahtemPalette.lInkFaint,
          fontSize: 13,
        ),
        helperStyle: uiTextStyle(color: dim, fontSize: 10.5),
        errorStyle: uiTextStyle(color: colorScheme.error, fontSize: 10.5),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        modalBackgroundColor: card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? MahtemPalette.dCardAlt : MahtemPalette.navy,
        contentTextStyle: uiTextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
          fontSize: 12.5,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: ink, size: 21),
        titleTextStyle: uiTextStyle(
          color: ink,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: dim,
        // ListTile REPLACES the ambient style with these — keep the
        // resolved family so Amharic titles never lose their glyphs.
        titleTextStyle: uiTextStyle(
          color: ink,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: uiTextStyle(color: dim, fontSize: 10.5),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: MahtemPalette.greenSoft,
        height: 66,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return uiTextStyle(
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? MahtemPalette.green : MahtemPalette.lInkFaint,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? MahtemPalette.green : MahtemPalette.lInkFaint,
          );
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? MahtemPalette.green : null,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: card,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: uiTextStyle(
          color: ink,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      ),
    );
  }
}

/// Mono text style used for references, amounts and meta labels.
TextStyle monoStyle({
  double size = 13,
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

/// Soft card shadow used across the light theme.
List<BoxShadow> cardShadow({Color color = const Color(0xFF1C2B5E)}) => [
  BoxShadow(
    color: color.withValues(alpha: 0.06),
    blurRadius: 18,
    offset: const Offset(0, 6),
  ),
];
