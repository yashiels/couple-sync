import 'package:flutter/material.dart';

/// App color definitions following Material Design 3 guidelines.
/// Provides both light and dark theme colors, plus semantic colors for
/// time block categories.
class AppColors {
  // Private constructor to prevent instantiation
  AppColors._();

  // ============== Light Theme Colors ==============

  /// Primary color - Deep purple for brand identity
  static const Color primaryLight = Color(0xFF6750A4);

  /// Primary container - Lighter variant for surfaces
  static const Color primaryContainerLight = Color(0xFFEADDFF);

  /// On primary - Text/icon color on primary
  static const Color onPrimaryLight = Color(0xFFFFFFFF);

  /// On primary container - Text/icon color on primary container
  static const Color onPrimaryContainerLight = Color(0xFF21005D);

  /// Secondary color - Teal for accents
  static const Color secondaryLight = Color(0xFF006A6A);

  /// Secondary container
  static const Color secondaryContainerLight = Color(0xFF6FF7F7);

  /// On secondary
  static const Color onSecondaryLight = Color(0xFFFFFFFF);

  /// On secondary container
  static const Color onSecondaryContainerLight = Color(0xFF002020);

  /// Surface color - Background for components
  static const Color surfaceLight = Color(0xFFFFFBFE);

  /// Surface variant
  static const Color surfaceVariantLight = Color(0xFFE7E0EC);

  /// On surface
  static const Color onSurfaceLight = Color(0xFF1C1B1F);

  /// On surface variant
  static const Color onSurfaceVariantLight = Color(0xFF49454F);

  /// Background color
  static const Color backgroundLight = Color(0xFFFFFBFE);

  /// On background
  static const Color onBackgroundLight = Color(0xFF1C1B1F);

  /// Error color
  static const Color errorLight = Color(0xFFB3261E);

  /// Error container
  static const Color errorContainerLight = Color(0xFFF9DEDC);

  /// On error
  static const Color onErrorLight = Color(0xFFFFFFFF);

  /// On error container
  static const Color onErrorContainerLight = Color(0xFF410E0B);

  /// Success color - Green for positive states
  static const Color successLight = Color(0xFF2E7D32);

  /// Success container
  static const Color successContainerLight = Color(0xFFC8E6C9);

  /// On success
  static const Color onSuccessLight = Color(0xFFFFFFFF);

  /// On success container
  static const Color onSuccessContainerLight = Color(0xFF1B5E20);

  /// Outline color
  static const Color outlineLight = Color(0xFF79747E);

  /// Outline variant
  static const Color outlineVariantLight = Color(0xFFCAC4D0);

  // ============== Dark Theme Colors ==============

  /// Primary color - Deep purple for brand identity
  static const Color primaryDark = Color(0xFFD0BCFF);

  /// Primary container
  static const Color primaryContainerDark = Color(0xFF4F378B);

  /// On primary
  static const Color onPrimaryDark = Color(0xFF381E72);

  /// On primary container
  static const Color onPrimaryContainerDark = Color(0xFFEADDFF);

  /// Secondary color - Teal for accents
  static const Color secondaryDark = Color(0xFF4CDADA);

  /// Secondary container
  static const Color secondaryContainerDark = Color(0xFF004F4F);

  /// On secondary
  static const Color onSecondaryDark = Color(0xFF003737);

  /// On secondary container
  static const Color onSecondaryContainerDark = Color(0xFF6FF7F7);

  /// Surface color
  static const Color surfaceDark = Color(0xFF1C1B1F);

  /// Surface variant
  static const Color surfaceVariantDark = Color(0xFF49454F);

  /// On surface
  static const Color onSurfaceDark = Color(0xFFE6E1E5);

  /// On surface variant
  static const Color onSurfaceVariantDark = Color(0xFFCAC4D0);

  /// Background color
  static const Color backgroundDark = Color(0xFF1C1B1F);

  /// On background
  static const Color onBackgroundDark = Color(0xFFE6E1E5);

  /// Error color
  static const Color errorDark = Color(0xFFF2B8B5);

  /// Error container
  static const Color errorContainerDark = Color(0xFF8C1D18);

  /// On error
  static const Color onErrorDark = Color(0xFF601410);

  /// On error container
  static const Color onErrorContainerDark = Color(0xFFF9DEDC);

  /// Success color - Green for positive states
  static const Color successDark = Color(0xFF81C784);

  /// Success container
  static const Color successContainerDark = Color(0xFF1B5E20);

  /// On success
  static const Color onSuccessDark = Color(0xFF003A00);

  /// On success container
  static const Color onSuccessContainerDark = Color(0xFFC8E6C9);

  /// Outline color
  static const Color outlineDark = Color(0xFF938F99);

  /// Outline variant
  static const Color outlineVariantDark = Color(0xFF49454F);

  // ============== Semantic Colors for Block Categories ==============

  /// Work category - Professional blue
  static const Color categoryWorkLight = Color(0xFF1976D2);
  static const Color categoryWorkDark = Color(0xFF64B5F6);

  /// Study category - Academic purple
  static const Color categoryStudyLight = Color(0xFF7B1FA2);
  static const Color categoryStudyDark = Color(0xFFBA68C8);

  /// Commute category - Travel orange
  static const Color categoryCommuteLight = Color(0xFFE64A19);
  static const Color categoryCommuteDark = Color(0xFFFF8A65);

  /// Exercise category - Fitness green
  static const Color categoryExerciseLight = Color(0xFF388E3C);
  static const Color categoryExerciseDark = Color(0xFF81C784);

  /// Social category - People pink
  static const Color categorySocialLight = Color(0xFFC2185B);
  static const Color categorySocialDark = Color(0xFFF06292);

  /// Meals category - Food amber
  static const Color categoryMealsLight = Color(0xFFF57C00);
  static const Color categoryMealsDark = Color(0xFFFFB74D);

  /// Sleep category - Rest indigo
  static const Color categorySleepLight = Color(0xFF303F9F);
  static const Color categorySleepDark = Color(0xFF7986CB);

  /// Personal category - Self-care teal
  static const Color categoryPersonalLight = Color(0xFF00796B);
  static const Color categoryPersonalDark = Color(0xFF4DB6AC);

  /// Other category - Neutral grey
  static const Color categoryOtherLight = Color(0xFF546E7A);
  static const Color categoryOtherDark = Color(0xFF90A4AE);
}
