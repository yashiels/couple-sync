import 'package:flutter/material.dart';

/// Central colour palette for the app.
///
/// Follows the design spec: rose (#E8849A) for the user's own blocks, sky-blue
/// (#7AB4E8) for the partner's blocks, and lavender-to-rose gradients for
/// overlap/free windows. Warm cream (#FFF8F5) scaffold background.
class AppColors {
  AppColors._();

  // Identity
  static const Color rose = Color(0xFFE8849A);
  static const Color roseLight = Color(0xFFFCEEF1);
  static const Color roseDark = Color(0xFFD4627A);

  static const Color partnerBlue = Color(0xFF7AB4E8);
  static const Color partnerBlueLight = Color(0xFFEBF3FC);

  // Keep lavender family
  static const Color lavenderLight = Color(0xFFE8D5F5);
  static const Color lavender = Color(0xFFCBA8EA);
  static const Color lavenderDark = Color(0xFFAA7DD0);

  // Partner color coding
  static const Color partnerA = Color(0xFFE8849A); // rose
  static const Color partnerB = Color(0xFF7AB4E8); // sky blue

  // Overlap
  static const Color overlapStart = Color(0xFFB794D6);
  static const Color overlapEnd = Color(0xFFE8849A);

  // Surfaces — warm cream
  static const Color surface = Color(0xFFFFF8F5);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFFFF8F5);
  static const Color onSurface = Color(0xFF2D2D3A);
  static const Color onSurfaceMuted = Color(0xFF6B6B80);
  static const Color divider = Color(0xFFF0E8F5);

  // Semantic
  static const Color success = Color(0xFF7BC47F);
  static const Color warning = Color(0xFFF5C842);
  static const Color error = Color(0xFFE85D5D);

  // Aliases
  static const Color roseDeep = roseDark;
  static const Color lavenderDeep = lavenderDark;
  static const Color skyBlue = partnerB;
  static const Color inputFill = Color(0xFFF5F0FA);
  static const Color textPrimary = onSurface;
  static const Color textSecondary = onSurfaceMuted;
  static const Color textTertiary = Color(0xFFA0A0B0);
  static const Color textHint = Color(0xFFB0A3BF);
  static const Color roseLightBg = Color(0xFFFCEEF1);

  // Gradients
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFB794D6), Color(0xFFE8849A)],
  );

  static const LinearGradient overlapGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0x60B794D6), Color(0x60E8849A)],
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF0EB), Color(0xFFFFF8F5)],
  );
}

/// Material 3 theme configuration for the app.
class AppTheme {
  AppTheme._();

  /// The default light [ThemeData] used by [MaterialApp].
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
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
          borderRadius: BorderRadius.circular(16),
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
