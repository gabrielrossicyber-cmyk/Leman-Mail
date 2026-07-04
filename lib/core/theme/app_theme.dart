import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'brand.dart';

/// Thèmes Material 3 de Leman Mail, dérivés de la charte [Brand] :
/// fond crème, encre brun-noir, bordeaux/carmin, titres serif
/// (Playfair Display, cousin du serif éditorial du site), boutons pilule
/// sombres et bordures taupe.
abstract final class AppTheme {
  static const riskLow = Brand.riskLow;
  static const riskMedium = Brand.riskMedium;
  static const riskHigh = Brand.riskHigh;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: Brand.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: Brand.bordeaux,
      onPrimary: Brand.cream,
      secondary: Brand.carmine,
      surface: Brand.cream,
      onSurface: Brand.ink,
      surfaceContainerLow: Brand.cardLight,
      surfaceContainerHighest: Brand.taupe.withValues(alpha: 0.35),
      outline: Brand.taupe,
      primaryContainer: Brand.carmine.withValues(alpha: 0.12),
      onPrimaryContainer: Brand.bordeaux,
    );
    return _base(scheme, buttonBackground: Brand.ink, buttonForeground: Brand.cream);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: Brand.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFFD9908F), // bordeaux éclairci, lisible sur sombre
      secondary: const Color(0xFFE0A9A8),
      surface: Brand.darkSurface,
      onSurface: Brand.cream,
      surfaceContainerLow: Brand.cardDark,
      surfaceContainerHighest: const Color(0xFF3A2F27),
      outline: Brand.taupe.withValues(alpha: 0.5),
      primaryContainer: Brand.bordeaux,
      onPrimaryContainer: Brand.cream,
    );
    return _base(scheme, buttonBackground: Brand.cream, buttonForeground: Brand.ink);
  }

  static ThemeData _base(
    ColorScheme scheme, {
    required Color buttonBackground,
    required Color buttonForeground,
  }) {
    final baseText = ThemeData(
      brightness: scheme.brightness,
      useMaterial3: true,
    ).textTheme.apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        );

    // Titres serif éditoriaux, corps en sans-serif système.
    TextStyle serif(TextStyle? style, {FontWeight weight = FontWeight.w700}) =>
        GoogleFonts.playfairDisplay(
          textStyle: style,
          fontWeight: weight,
          color: scheme.onSurface,
        );

    final textTheme = baseText.copyWith(
      displaySmall: serif(baseText.displaySmall),
      headlineMedium: serif(baseText.headlineMedium),
      headlineSmall: serif(baseText.headlineSmall),
      titleLarge: serif(baseText.titleLarge),
      labelSmall: baseText.labelSmall?.copyWith(letterSpacing: 1.2),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 20),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.4)),
        ),
        color: scheme.surfaceContainerLow,
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
        selectedColor: scheme.primaryContainer,
        labelStyle: TextStyle(color: scheme.onSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
      ),
      drawerTheme: DrawerThemeData(backgroundColor: scheme.surface),
      dividerTheme: DividerThemeData(
        color: scheme.outline.withValues(alpha: 0.35),
      ),
      // Boutons pilule sombres, signature du site.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: buttonBackground,
          foregroundColor: buttonForeground,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.secondary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: buttonBackground,
        foregroundColor: buttonForeground,
      ),
      snackBarTheme:
          const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }

  /// Maps a 0-100 score to a semantic color (higher is better).
  static Color scoreColor(int score) {
    if (score >= 70) return riskLow;
    if (score >= 50) return riskMedium;
    return riskHigh;
  }
}
