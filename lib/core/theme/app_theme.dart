import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// iOS system colour palette.
///
/// White scaffold, grouped-table gray background, SF-style blue accent.
/// Rose/lavender gradient preserved only for brand hero moments.
class AppColors {
  AppColors._();

  // ── iOS system colours ────────────────────────────────────────────────────
  static const Color primary = Color(0xFF007AFF);
  static const Color destructive = Color(0xFFFF3B30);
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);

  // Surfaces
  static const Color background = Color(0xFFFFFFFF);
  static const Color groupedBackground = Color(0xFFF2F2F7);
  static const Color surfaceElevated = Color(0xFFFFFFFF);

  // Text
  static const Color onSurface = Color(0xFF000000);
  static const Color onSurfaceMuted = Color(0xFF8E8E93);
  static const Color textPrimary = Color(0xFF000000);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textTertiary = Color(0xFFC7C7CC);
  static const Color textHint = Color(0xFFC7C7CC);

  // Borders / dividers
  static const Color separator = Color(0xFFC6C6C8);
  static const Color divider = Color(0xFFC6C6C8);

  // ── Brand colours (hero moments only) ─────────────────────────────────────
  static const Color rose = Color(0xFFE8849A);
  static const Color roseLight = Color(0xFFFCEEF1);
  static const Color roseDark = Color(0xFFD4627A);

  static const Color partnerBlue = Color(0xFF7AB4E8);
  static const Color partnerBlueLight = Color(0xFFEBF3FC);

  static const Color lavenderLight = Color(0xFFE8D5F5);
  static const Color lavender = Color(0xFFCBA8EA);
  static const Color lavenderDark = Color(0xFFAA7DD0);

  // Partner colour coding
  static const Color partnerA = Color(0xFFE8849A);
  static const Color partnerB = Color(0xFF7AB4E8);

  // Overlap
  static const Color overlapStart = Color(0xFFB794D6);
  static const Color overlapEnd = Color(0xFFE8849A);

  // Semantic
  static const Color error = Color(0xFFFF3B30);

  // Legacy aliases (keep for backward compat across screens)
  static const Color roseDeep = roseDark;
  static const Color lavenderDeep = lavenderDark;
  static const Color skyBlue = partnerB;
  static const Color inputFill = Color(0xFFF2F2F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color roseLightBg = Color(0xFFFCEEF1);

  // Gradients — brand hero moments only
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
    colors: [Color(0xFFF2F2F7), Color(0xFFFFFFFF)],
  );
}

/// iOS-style typography using Inter (closest to SF Pro on Android/web).
class AppTypography {
  AppTypography._();

  static TextStyle largeTitle = GoogleFonts.inter(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: 0.37,
  );

  static TextStyle title1 = GoogleFonts.inter(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static TextStyle title2 = GoogleFonts.inter(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static TextStyle title3 = GoogleFonts.inter(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle headline = GoogleFonts.inter(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle body = GoogleFonts.inter(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static TextStyle subhead = GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static TextStyle footnote = GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static TextStyle caption = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static TextStyle captionBold = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );
}

/// Material 3 theme configured with iOS-native look-and-feel.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      platform: TargetPlatform.iOS,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        surface: AppColors.surfaceElevated,
        primary: AppColors.primary,
        error: AppColors.error,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.onSurface,
        centerTitle: true,
        titleTextStyle: AppTypography.headline,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.separator,
        thickness: 0.33,
        space: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.groupedBackground,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1),
        ),
        hintStyle: AppTypography.body.copyWith(color: AppColors.textTertiary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: AppTypography.headline,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: const BorderSide(color: AppColors.separator),
          textStyle: AppTypography.headline,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: AppTypography.headline,
        ),
      ),
      textTheme: TextTheme(
        displaySmall: AppTypography.largeTitle,
        headlineMedium: AppTypography.title1,
        headlineSmall: AppTypography.title2,
        titleLarge: AppTypography.title3,
        titleMedium: AppTypography.headline,
        bodyLarge: AppTypography.body,
        bodyMedium: AppTypography.subhead,
        bodySmall: AppTypography.footnote,
        labelSmall: AppTypography.caption,
      ),
    );
    return base;
  }
}
