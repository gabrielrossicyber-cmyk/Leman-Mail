import 'package:flutter/material.dart';

/// Leman Mail Material 3 themes.
///
/// Brand: deep "Léman lake" blue with a security-green accent, high
/// contrast in both modes, shared component shapes.
abstract final class AppTheme {
  static const _seed = Color(0xFF0B5394); // Léman blue
  static const riskLow = Color(0xFF2E7D32);
  static const riskMedium = Color(0xFFF9A825);
  static const riskHigh = Color(0xFFC62828);

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
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
