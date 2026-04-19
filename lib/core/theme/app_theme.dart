import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Application theme configuration following Material Design 3 guidelines.
/// Provides light and dark themes with custom color schemes and typography.
class AppTheme {
  // Private constructor to prevent instantiation
  AppTheme._();

  // ============== Typography ==============

  /// Custom text theme following Material Design 3 guidelines
  static TextTheme _buildTextTheme({required bool isDark}) {
    final Color textColor = isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;
    
    return TextTheme(
      // Headline styles - Large display text
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.5,
        color: textColor,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: textColor,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: textColor,
      ),
      
      // Title styles - Section headers and app bar titles
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        color: textColor,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.15,
        color: textColor,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        color: textColor,
      ),
      
      // Body styles - Main content text
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
        color: textColor,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
        color: textColor,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
        color: textColor,
      ),
      
      // Label styles - Buttons and form labels
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        color: textColor,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: textColor,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: textColor,
      ),
      
      // Caption - Deprecated in M3, removed
      // Maps to bodySmall in M3
    );
  }

  // ============== Light Theme ==============

  /// Light theme with Material Design 3 color scheme
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primaryLight,
        onPrimary: AppColors.onPrimaryLight,
        primaryContainer: AppColors.primaryContainerLight,
        onPrimaryContainer: AppColors.onPrimaryContainerLight,
        secondary: AppColors.secondaryLight,
        onSecondary: AppColors.onSecondaryLight,
        secondaryContainer: AppColors.secondaryContainerLight,
        onSecondaryContainer: AppColors.onSecondaryContainerLight,
        surface: AppColors.surfaceLight,
        onSurface: AppColors.onSurfaceLight,
        surfaceContainerHighest: AppColors.surfaceVariantLight,
        onSurfaceVariant: AppColors.onSurfaceVariantLight,
        error: AppColors.errorLight,
        onError: AppColors.onErrorLight,
        errorContainer: AppColors.errorContainerLight,
        onErrorContainer: AppColors.onErrorContainerLight,
        outline: AppColors.outlineLight,
        outlineVariant: AppColors.outlineVariantLight,
      ),
      textTheme: _buildTextTheme(isDark: false),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surfaceLight,
        foregroundColor: AppColors.onSurfaceLight,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceLight,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryLight,
          foregroundColor: AppColors.onPrimaryLight,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryContainerLight,
        foregroundColor: AppColors.onPrimaryContainerLight,
        elevation: 3,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceVariantLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.errorLight, width: 1),
        ),
      ),
    );
  }

  // ============== Dark Theme ==============

  /// Dark theme with Material Design 3 color scheme
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primaryDark,
        onPrimary: AppColors.onPrimaryDark,
        primaryContainer: AppColors.primaryContainerDark,
        onPrimaryContainer: AppColors.onPrimaryContainerDark,
        secondary: AppColors.secondaryDark,
        onSecondary: AppColors.onSecondaryDark,
        secondaryContainer: AppColors.secondaryContainerDark,
        onSecondaryContainer: AppColors.onSecondaryContainerDark,
        surface: AppColors.surfaceDark,
        onSurface: AppColors.onSurfaceDark,
        surfaceContainerHighest: AppColors.surfaceVariantDark,
        onSurfaceVariant: AppColors.onSurfaceVariantDark,
        error: AppColors.errorDark,
        onError: AppColors.onErrorDark,
        errorContainer: AppColors.errorContainerDark,
        onErrorContainer: AppColors.onErrorContainerDark,
        outline: AppColors.outlineDark,
        outlineVariant: AppColors.outlineVariantDark,
      ),
      textTheme: _buildTextTheme(isDark: true),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surfaceDark,
        foregroundColor: AppColors.onSurfaceDark,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceDark,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryDark,
          foregroundColor: AppColors.onPrimaryDark,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryContainerDark,
        foregroundColor: AppColors.onPrimaryContainerDark,
        elevation: 3,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceVariantDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primaryDark, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.errorDark, width: 1),
        ),
      ),
    );
  }

  // ============== Helper Methods ==============

  /// Get category color for a specific block category in light mode
  static Color getCategoryColorLight(String category) {
    switch (category.toLowerCase()) {
      case 'work':
        return AppColors.categoryWorkLight;
      case 'study':
        return AppColors.categoryStudyLight;
      case 'commute':
        return AppColors.categoryCommuteLight;
      case 'exercise':
        return AppColors.categoryExerciseLight;
      case 'social':
        return AppColors.categorySocialLight;
      case 'meals':
        return AppColors.categoryMealsLight;
      case 'sleep':
        return AppColors.categorySleepLight;
      case 'personal':
        return AppColors.categoryPersonalLight;
      case 'other':
      default:
        return AppColors.categoryOtherLight;
    }
  }

  /// Get category color for a specific block category in dark mode
  static Color getCategoryColorDark(String category) {
    switch (category.toLowerCase()) {
      case 'work':
        return AppColors.categoryWorkDark;
      case 'study':
        return AppColors.categoryStudyDark;
      case 'commute':
        return AppColors.categoryCommuteDark;
      case 'exercise':
        return AppColors.categoryExerciseDark;
      case 'social':
        return AppColors.categorySocialDark;
      case 'meals':
        return AppColors.categoryMealsDark;
      case 'sleep':
        return AppColors.categorySleepDark;
      case 'personal':
        return AppColors.categoryPersonalDark;
      case 'other':
      default:
        return AppColors.categoryOtherDark;
    }
  }

  /// Get category color based on theme brightness
  static Color getCategoryColor(String category, Brightness brightness) {
    return brightness == Brightness.dark
        ? getCategoryColorDark(category)
        : getCategoryColorLight(category);
  }

  /// Get success color based on theme brightness
  static Color getSuccessColor(Brightness brightness) {
    return brightness == Brightness.dark
        ? AppColors.successDark
        : AppColors.successLight;
  }
}
