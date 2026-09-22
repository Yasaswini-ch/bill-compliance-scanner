import 'package:flutter/material.dart';

/// Colours and text styles for the app. Sizes lean large on purpose: the
/// result screen is meant to be legible from a few feet away, on a phone held
/// up to a jury or projected on a screen.
abstract final class AppColors {
  static const Color primary = Color(0xFF1B3A5C);
  static const Color primaryDark = Color(0xFF12293F);
  static const Color accent = Color(0xFF2FB8AC);
  static const Color alert = Color(0xFFE63946);
  static const Color success = Color(0xFF2A9D8F);
  static const Color warning = Color(0xFFE9A23B);

  static const Color surface = Color(0xFFF7F9FB);
  static const Color card = Colors.white;
  static const Color textPrimary = Color(0xFF14212E);
  static const Color textSecondary = Color(0xFF5B6B7B);
  static const Color divider = Color(0xFFDDE4EA);

  /// Tinted backgrounds for flag cards, kept light so text stays readable.
  static const Color alertSurface = Color(0xFFFDECEE);
  static const Color warningSurface = Color(0xFFFDF4E6);
  static const Color successSurface = Color(0xFFE6F5F2);
  static const Color infoSurface = Color(0xFFEDF2F7);
}

abstract final class AppTheme {
  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.accent,
        error: AppColors.alert,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.surface,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      textTheme: base.textTheme
          .copyWith(
            displaySmall: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.15,
            ),
            headlineSmall: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.25,
            ),
            titleMedium: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            bodyLarge: const TextStyle(
              fontSize: 16.5,
              height: 1.45,
              color: AppColors.textPrimary,
            ),
            bodyMedium: const TextStyle(
              fontSize: 15,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
            labelLarge: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          )
          .apply(fontFamily: 'Roboto'),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.divider),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: AppColors.primary, width: 1.6),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.primaryDark,
        contentTextStyle: TextStyle(color: Colors.white, fontSize: 15),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        space: 1,
        thickness: 1,
      ),
    );
  }
}
