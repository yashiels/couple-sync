import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Gradient primaries
  static const Color roseLight = Color(0xFFF9C5D1);
  static const Color rose = Color(0xFFF4A0B5);
  static const Color roseDark = Color(0xFFE07898);

  static const Color lavenderLight = Color(0xFFE8D5F5);
  static const Color lavender = Color(0xFFCBA8EA);
  static const Color lavenderDark = Color(0xFFAA7DD0);

  // Partner color coding
  static const Color partnerA = Color(0xFFF4A0B5); // rose
  static const Color partnerB = Color(0xFF9BC4F5); // sky blue

  // Overlap / free window accent
  static const Color overlapStart = Color(0xFFC8A4E8);
  static const Color overlapEnd = Color(0xFFF4A0B5);

  // Neutrals
  static const Color surface = Color(0xFFFDF8FF);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF2D1F3A);
  static const Color onSurfaceMuted = Color(0xFF8A7A9A);
  static const Color divider = Color(0xFFEDE0F5);

  // Aliases used across screens
  static const Color roseDeep = roseDark;
  static const Color lavenderDeep = lavenderDark;
  static const Color skyBlue = partnerB;
  static const Color inputFill = Color(0xFFF5F0FA);
  static const Color textPrimary = onSurface;
  static const Color textSecondary = onSurfaceMuted;
  static const Color textHint = Color(0xFFB0A3BF);
  static const Color error = Color(0xFFE53935);
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFCBA8EA), Color(0xFFF4A0B5)],
  );

  static const LinearGradient overlapGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0x60CBA8EA), Color(0x60F4A0B5)],
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF9F0FF), Color(0xFFFDF8FF)],
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'SF Pro Display',
      scaffoldBackgroundColor: AppColors.surface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.lavender,
        brightness: Brightness.light,
        surface: AppColors.surface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.onSurface,
        titleTextStyle: TextStyle(
          color: AppColors.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        shadowColor: const Color(0x14CBA8EA),
      ),
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: AppColors.onSurface,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
          letterSpacing: -0.3,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
          letterSpacing: -0.2,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.onSurface,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.onSurface,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.onSurfaceMuted,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.onSurfaceMuted,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
