import 'package:couple_sync/core/router/routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppRoutes path constants', () {
    test('auth/onboarding paths start with slash', () {
      expect(AppRoutes.auth, startsWith('/'));
      expect(AppRoutes.timezoneSetup, startsWith('/'));
      expect(AppRoutes.pairing, startsWith('/'));
    });

    test('main app paths start with slash', () {
      expect(AppRoutes.home, startsWith('/'));
      expect(AppRoutes.calendar, startsWith('/'));
      expect(AppRoutes.blocks, startsWith('/'));
      expect(AppRoutes.blockForm, startsWith('/'));
      expect(AppRoutes.overlap, startsWith('/'));
      expect(AppRoutes.settings, startsWith('/'));
    });

    test('auth/onboarding path values are correct', () {
      expect(AppRoutes.auth, '/auth');
      expect(AppRoutes.timezoneSetup, '/timezone-setup');
      expect(AppRoutes.pairing, '/pairing');
    });

    test('main app path values are correct', () {
      expect(AppRoutes.home, '/home');
      expect(AppRoutes.calendar, '/calendar');
      expect(AppRoutes.blocks, '/blocks');
      expect(AppRoutes.blockForm, '/block-form');
      expect(AppRoutes.overlap, '/overlap');
      expect(AppRoutes.settings, '/settings');
    });

    test('all paths are unique', () {
      final paths = [
        AppRoutes.auth,
        AppRoutes.timezoneSetup,
        AppRoutes.pairing,
        AppRoutes.home,
        AppRoutes.calendar,
        AppRoutes.blocks,
        AppRoutes.blockForm,
        AppRoutes.overlap,
        AppRoutes.settings,
      ];
      expect(paths.toSet().length, paths.length);
    });
  });

  group('RouteNames constants', () {
    test('route name values are correct', () {
      expect(RouteNames.auth, 'auth');
      expect(RouteNames.timezoneSetup, 'timezone-setup');
      expect(RouteNames.pairing, 'pairing');
      expect(RouteNames.home, 'home');
      expect(RouteNames.calendar, 'calendar');
      expect(RouteNames.blocks, 'blocks');
      expect(RouteNames.blockForm, 'block-form');
      expect(RouteNames.overlap, 'overlap');
      expect(RouteNames.settings, 'settings');
    });

    test('all route names are unique', () {
      final names = [
        RouteNames.auth,
        RouteNames.timezoneSetup,
        RouteNames.pairing,
        RouteNames.home,
        RouteNames.calendar,
        RouteNames.blocks,
        RouteNames.blockForm,
        RouteNames.overlap,
        RouteNames.settings,
      ];
      expect(names.toSet().length, names.length);
    });

    test('route names do not contain leading slashes', () {
      expect(RouteNames.auth, isNot(startsWith('/')));
      expect(RouteNames.home, isNot(startsWith('/')));
      expect(RouteNames.timezoneSetup, isNot(startsWith('/')));
    });
  });

  group('BlockFormArgs', () {
    test('serializes to map with blockId and initialDate', () {
      final date = DateTime(2026, 4, 7, 12, 0, 0);
      final args = BlockFormArgs(blockId: 'block-123', initialDate: date);

      final map = args.toMap();

      expect(map['blockId'], 'block-123');
      expect(map['initialDate'], date.toIso8601String());
    });

    test('serializes to map with null values', () {
      const args = BlockFormArgs();

      final map = args.toMap();

      expect(map['blockId'], isNull);
      expect(map['initialDate'], isNull);
    });

    test('deserializes from map with all fields', () {
      final date = DateTime(2026, 4, 7, 12, 0, 0);
      final map = {
        'blockId': 'block-456',
        'initialDate': date.toIso8601String(),
      };

      final args = BlockFormArgs.fromMap(map);

      expect(args.blockId, 'block-456');
      expect(args.initialDate, date);
    });

    test('deserializes from map with null values', () {
      final map = <String, dynamic>{'blockId': null, 'initialDate': null};

      final args = BlockFormArgs.fromMap(map);

      expect(args.blockId, isNull);
      expect(args.initialDate, isNull);
    });

    test('roundtrip serialization preserves all fields', () {
      final date = DateTime(2026, 6, 15, 9, 30, 0);
      final original = BlockFormArgs(blockId: 'blk-abc', initialDate: date);

      final restored = BlockFormArgs.fromMap(original.toMap());

      expect(restored.blockId, original.blockId);
      expect(restored.initialDate, original.initialDate);
    });

    test('roundtrip serialization preserves null fields', () {
      const original = BlockFormArgs();

      final restored = BlockFormArgs.fromMap(original.toMap());

      expect(restored.blockId, isNull);
      expect(restored.initialDate, isNull);
    });
  });
}
