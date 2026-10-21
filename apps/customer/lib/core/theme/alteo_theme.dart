import 'package:flutter/material.dart';

abstract final class AlteoColors {
  static const forest = Color(0xFF145C45);
  static const forestDeep = Color(0xFF0C3E30);
  static const mint = Color(0xFFE5F3EA);
  static const coral = Color(0xFFFF8066);
  static const canvas = Color(0xFFF7F8F5);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF17231D);
  static const muted = Color(0xFF65736B);
  static const line = Color(0xFFE3E9E4);
  static const darkCanvas = Color(0xFF101714);
  static const darkCard = Color(0xFF1A2420);
}

abstract final class AlteoTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AlteoColors.forest,
      brightness: Brightness.light,
      primary: AlteoColors.forest,
      secondary: AlteoColors.coral,
      surface: AlteoColors.card,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AlteoColors.canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: AlteoColors.canvas,
        foregroundColor: AlteoColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AlteoColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AlteoColors.line),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AlteoColors.line,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AlteoColors.card,
        hintStyle: const TextStyle(color: AlteoColors.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AlteoColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AlteoColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AlteoColors.forest, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AlteoColors.forest,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AlteoColors.line,
          disabledForegroundColor: AlteoColors.muted,
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AlteoColors.forest,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          side: const BorderSide(color: AlteoColors.line),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: AlteoColors.ink, fontSize: 30, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -0.8),
        headlineMedium: TextStyle(color: AlteoColors.ink, fontSize: 24, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.5),
        titleLarge: TextStyle(color: AlteoColors.ink, fontSize: 18, fontWeight: FontWeight.w800),
        titleMedium: TextStyle(color: AlteoColors.ink, fontSize: 15, fontWeight: FontWeight.w700),
        bodyMedium: TextStyle(color: AlteoColors.ink, fontSize: 14, height: 1.45),
        bodySmall: TextStyle(color: AlteoColors.muted, fontSize: 12, height: 1.4),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AlteoColors.forest,
      brightness: Brightness.dark,
      primary: const Color(0xFF80D1A7),
      secondary: AlteoColors.coral,
      surface: AlteoColors.darkCard,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AlteoColors.darkCanvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: AlteoColors.darkCanvas,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AlteoColors.darkCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF2B3932)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AlteoColors.darkCard,
        hintStyle: const TextStyle(color: Color(0xFF9EADA5)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2B3932)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2B3932)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF80D1A7), width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF80D1A7),
          foregroundColor: const Color(0xFF09291E),
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: Colors.white, fontSize: 30, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -0.8),
        headlineMedium: TextStyle(color: Colors.white, fontSize: 24, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.5),
        titleLarge: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
        titleMedium: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
        bodyMedium: TextStyle(color: Color(0xFFE6EDE8), fontSize: 14, height: 1.45),
        bodySmall: TextStyle(color: Color(0xFF9EADA5), fontSize: 12, height: 1.4),
      ),
    );
  }
}
