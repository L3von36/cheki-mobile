import 'package:flutter/material.dart';

/// Dark premium theme tokens — mirrors the web console's zinc + emerald.
abstract final class AdminColors {
  static const background = Color(0xFF09090B);
  static const card = Color(0xFF111113);
  static const border = Color(0xFF232328);
  static const emerald = Color(0xFF34D399);
  static const emeraldDim = Color(0xFF065F46);
  static const text = Color(0xFFF4F4F5);
  static const muted = Color(0xFFA1A1AA);
  static const faint = Color(0xFF71717A);
  static const amber = Color(0xFFF59E0B);
  static const rose = Color(0xFFF43F5E);
}

/// Light theme tokens — clean zinc + emerald for day use.
abstract final class AdminLightColors {
  static const background = Color(0xFFFAFAFA);
  static const card = Color(0xFFFFFFFF);
  static const border = Color(0xFFE4E4E7);
  static const emerald = Color(0xFF059669);
  static const emeraldDim = Color(0xFF064E3B);
  static const text = Color(0xFF18181B);
  static const muted = Color(0xFF71717A);
  static const faint = Color(0xFFA1A1AA);
  static const amber = Color(0xFFB45309);
  static const rose = Color(0xFFE11D48);
}

ThemeData adminTheme() {
  final scheme = ColorScheme.dark(
    primary: AdminColors.emerald,
    onPrimary: const Color(0xFF052E22),
    secondary: AdminColors.emerald,
    surface: AdminColors.card,
    onSurface: AdminColors.text,
    error: AdminColors.rose,
    outline: AdminColors.border,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AdminColors.background,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AdminColors.text, displayColor: AdminColors.text),
    cardTheme: CardThemeData(
      color: AdminColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AdminColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF0C0C0E),
      hintStyle: const TextStyle(color: AdminColors.faint),
      labelStyle: const TextStyle(color: AdminColors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AdminColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AdminColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AdminColors.emerald, width: 1.4),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Color(0xFF052E22)
            : AdminColors.faint,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AdminColors.emerald
            : AdminColors.border,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AdminColors.emerald,
        foregroundColor: const Color(0xFF052E22),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minimumSize: const Size.fromHeight(52),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AdminColors.border, thickness: 1),
  );
}

ThemeData adminLightTheme() {
  final scheme = ColorScheme.light(
    primary: AdminLightColors.emerald,
    onPrimary: Colors.white,
    secondary: AdminLightColors.emerald,
    surface: AdminLightColors.card,
    onSurface: AdminLightColors.text,
    error: AdminLightColors.rose,
    outline: AdminLightColors.border,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: AdminLightColors.background,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AdminLightColors.text, displayColor: AdminLightColors.text),
    cardTheme: CardThemeData(
      color: AdminLightColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AdminLightColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF4F4F5),
      hintStyle: const TextStyle(color: AdminLightColors.faint),
      labelStyle: const TextStyle(color: AdminLightColors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AdminLightColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AdminLightColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AdminLightColors.emerald, width: 1.4),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : AdminLightColors.faint,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AdminLightColors.emerald
            : AdminLightColors.border,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AdminLightColors.emerald,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minimumSize: const Size.fromHeight(52),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AdminLightColors.border, thickness: 1),
  );
}
