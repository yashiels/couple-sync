import 'package:couple_sync/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppColors – light theme color values', () {
    test('primary light color is the expected deep purple', () {
      expect(AppColors.primaryLight, equals(const Color(0xFF6750A4)));
    });

    test('surface light color matches spec', () {
      expect(AppColors.surfaceLight, equals(const Color(0xFFFFFBFE)));
    });

    test('error light color matches spec', () {
      expect(AppColors.errorLight, equals(const Color(0xFFB3261E)));
    });

    test('outline light color matches spec', () {
      expect(AppColors.outlineLight, equals(const Color(0xFF79747E)));
    });
  });

  group('AppColors – dark theme color values', () {
    test('primary dark color is the expected lavender', () {
      expect(AppColors.primaryDark, equals(const Color(0xFFD0BCFF)));
    });

    test('surface dark color matches spec', () {
      expect(AppColors.surfaceDark, equals(const Color(0xFF1C1B1F)));
    });

    test('error dark color matches spec', () {
      expect(AppColors.errorDark, equals(const Color(0xFFF2B8B5)));
    });

    test('outline dark color matches spec', () {
      expect(AppColors.outlineDark, equals(const Color(0xFF938F99)));
    });
  });

  group('AppColors – light / dark contrast pairs', () {
    test('light primary container is lighter than dark primary container', () {
      // Light container has a very high alpha-blended luminance value.
      // A simple proxy: the red+green+blue sum of the light variant is higher.
      final lightSum = _rgbSum(AppColors.primaryContainerLight);
      final darkSum = _rgbSum(AppColors.primaryContainerDark);
      expect(lightSum, greaterThan(darkSum));
    });

    test('light surface is lighter than dark surface', () {
      expect(
        _rgbSum(AppColors.surfaceLight),
        greaterThan(_rgbSum(AppColors.surfaceDark)),
      );
    });
  });

  group('AppColors – category colors', () {
    test('work light and dark are different colors', () {
      expect(AppColors.categoryWorkLight, isNot(equals(AppColors.categoryWorkDark)));
    });

    test('all 9 light category colors have full opacity', () {
      final lightCategories = [
        AppColors.categoryWorkLight,
        AppColors.categoryStudyLight,
        AppColors.categoryCommuteLight,
        AppColors.categoryExerciseLight,
        AppColors.categorySocialLight,
        AppColors.categoryMealsLight,
        AppColors.categorySleepLight,
        AppColors.categoryPersonalLight,
        AppColors.categoryOtherLight,
      ];
      for (final color in lightCategories) {
        expect((color.a * 255.0).round().clamp(0, 255), equals(255), reason: 'Expected full opacity for $color');
      }
    });

    test('all 9 dark category colors have full opacity', () {
      final darkCategories = [
        AppColors.categoryWorkDark,
        AppColors.categoryStudyDark,
        AppColors.categoryCommuteDark,
        AppColors.categoryExerciseDark,
        AppColors.categorySocialDark,
        AppColors.categoryMealsDark,
        AppColors.categorySleepDark,
        AppColors.categoryPersonalDark,
        AppColors.categoryOtherDark,
      ];
      for (final color in darkCategories) {
        expect((color.a * 255.0).round().clamp(0, 255), equals(255), reason: 'Expected full opacity for $color');
      }
    });

    test('dark category colors are lighter than their light counterparts', () {
      // Dark mode uses lighter tints so they are visible on a dark surface.
      // We check this via the RGB sum heuristic.
      expect(
        _rgbSum(AppColors.categoryWorkDark),
        greaterThan(_rgbSum(AppColors.categoryWorkLight)),
      );
      expect(
        _rgbSum(AppColors.categoryStudyDark),
        greaterThan(_rgbSum(AppColors.categoryStudyLight)),
      );
    });
  });

  group('AppColors – on-surface contrast', () {
    test('onSurface light is dark (high contrast on white surface)', () {
      // onSurfaceLight = 0xFF1C1B1F — near-black
      final color = AppColors.onSurfaceLight;
      expect(_rgbSum(color), lessThan(100));
    });

    test('onSurface dark is light (high contrast on dark surface)', () {
      // onSurfaceDark = 0xFFE6E1E5 — near-white
      final color = AppColors.onSurfaceDark;
      expect(_rgbSum(color), greaterThan(600));
    });
  });
}

/// Returns the sum of the red, green, and blue channel values (0–765).
int _rgbSum(Color color) =>
    (color.r * 255.0).round().clamp(0, 255) +
    (color.g * 255.0).round().clamp(0, 255) +
    (color.b * 255.0).round().clamp(0, 255);
