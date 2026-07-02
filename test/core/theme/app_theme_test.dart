import 'package:couple_sync/core/models/time_block.dart';
import 'package:couple_sync/core/theme/app_colors.dart';
import 'package:couple_sync/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTheme.lightTheme', () {
    late ThemeData theme;
    setUpAll(() => theme = AppTheme.lightTheme);

    test('uses Material 3', () {
      expect(theme.useMaterial3, isTrue);
    });

    test('brightness is light', () {
      expect(theme.brightness, equals(Brightness.light));
    });

    test('primary color matches AppColors.primaryLight', () {
      expect(theme.colorScheme.primary, equals(AppColors.primaryLight));
    });

    test('error color matches AppColors.errorLight', () {
      expect(theme.colorScheme.error, equals(AppColors.errorLight));
    });

    test('app bar is elevation-0 and centered title', () {
      expect(theme.appBarTheme.elevation, equals(0));
      expect(theme.appBarTheme.centerTitle, isTrue);
    });

    test('app bar background is the surface color', () {
      expect(theme.appBarTheme.backgroundColor, equals(AppColors.surfaceLight));
    });

    test('headline large font size is 32', () {
      expect(theme.textTheme.headlineLarge?.fontSize, equals(32));
    });

    test('body medium font size is 14', () {
      expect(theme.textTheme.bodyMedium?.fontSize, equals(14));
    });

    test('card elevation is 1', () {
      expect(theme.cardTheme.elevation, equals(1));
    });
  });

  group('AppTheme.darkTheme', () {
    late ThemeData theme;
    setUpAll(() => theme = AppTheme.darkTheme);

    test('uses Material 3', () {
      expect(theme.useMaterial3, isTrue);
    });

    test('brightness is dark', () {
      expect(theme.brightness, equals(Brightness.dark));
    });

    test('primary color matches AppColors.primaryDark', () {
      expect(theme.colorScheme.primary, equals(AppColors.primaryDark));
    });

    test('error color matches AppColors.errorDark', () {
      expect(theme.colorScheme.error, equals(AppColors.errorDark));
    });

    test('app bar background is the dark surface color', () {
      expect(theme.appBarTheme.backgroundColor, equals(AppColors.surfaceDark));
    });

    test('headline large font size is 32', () {
      expect(theme.textTheme.headlineLarge?.fontSize, equals(32));
    });

    test('text colors differ between light and dark themes', () {
      final light = AppTheme.lightTheme.textTheme.bodyLarge?.color;
      final dark = AppTheme.darkTheme.textTheme.bodyLarge?.color;
      expect(light, isNotNull);
      expect(dark, isNotNull);
      expect(light, isNot(equals(dark)));
    });
  });

  group('AppTheme – light vs dark', () {
    test('light and dark themes have different primary colors', () {
      expect(
        AppTheme.lightTheme.colorScheme.primary,
        isNot(equals(AppTheme.darkTheme.colorScheme.primary)),
      );
    });

    test('light and dark themes have different surface colors', () {
      expect(
        AppTheme.lightTheme.colorScheme.surface,
        isNot(equals(AppTheme.darkTheme.colorScheme.surface)),
      );
    });
  });

  group('AppTheme.getCategoryColorLight', () {
    test('returns correct color for known categories', () {
      expect(AppTheme.getCategoryColorLight(TimeBlockCategory.work), equals(AppColors.categoryWorkLight));
      expect(AppTheme.getCategoryColorLight(TimeBlockCategory.study), equals(AppColors.categoryStudyLight));
      expect(AppTheme.getCategoryColorLight(TimeBlockCategory.sleep), equals(AppColors.categorySleepLight));
    });

    test('returns Other color for the other category', () {
      expect(
        AppTheme.getCategoryColorLight(TimeBlockCategory.other),
        equals(AppColors.categoryOtherLight),
      );
    });
  });

  group('AppTheme.getCategoryColorDark', () {
    test('returns correct color for known categories', () {
      expect(AppTheme.getCategoryColorDark(TimeBlockCategory.work), equals(AppColors.categoryWorkDark));
      expect(AppTheme.getCategoryColorDark(TimeBlockCategory.exercise), equals(AppColors.categoryExerciseDark));
    });

    test('returns Other color for the other category', () {
      expect(
        AppTheme.getCategoryColorDark(TimeBlockCategory.other),
        equals(AppColors.categoryOtherDark),
      );
    });
  });

  group('AppTheme.getCategoryColor (brightness-aware)', () {
    test('returns dark variant when brightness is dark', () {
      expect(
        AppTheme.getCategoryColor(TimeBlockCategory.work, Brightness.dark),
        equals(AppColors.categoryWorkDark),
      );
    });

    test('returns light variant when brightness is light', () {
      expect(
        AppTheme.getCategoryColor(TimeBlockCategory.work, Brightness.light),
        equals(AppColors.categoryWorkLight),
      );
    });
  });

  group('AppTheme.getSuccessColor', () {
    test('returns light success color for light brightness', () {
      expect(
        AppTheme.getSuccessColor(Brightness.light),
        equals(AppColors.successLight),
      );
    });

    test('returns dark success color for dark brightness', () {
      expect(
        AppTheme.getSuccessColor(Brightness.dark),
        equals(AppColors.successDark),
      );
    });

    test('light and dark success colors are different', () {
      expect(AppColors.successLight, isNot(equals(AppColors.successDark)));
    });
  });
}
