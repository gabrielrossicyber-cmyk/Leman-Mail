import 'package:flutter/material.dart';

import 'brand.dart';

/// Leman Mail Material 3 themes, derived entirely from [Brand].
abstract final class AppTheme {
  static const riskLow = Brand.riskLow;
  static const riskMedium = Brand.riskMedium;
  static const riskHigh = Brand.riskHigh;

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Brand.primary,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: Brand.displayFontFamily,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: scheme.surfaceContainerLow,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: scheme.primaryContainer,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }

  /// Maps a 0-100 score to a semantic color (higher is better).
  static Color scoreColor(int score) {
    if (score >= 70) return riskLow;
    if (score >= 50) return riskMedium;
    return riskHigh;
  }
}
