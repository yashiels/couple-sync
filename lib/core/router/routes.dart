import 'package:go_router/go_router.dart';

/// Route path constants for type-safe navigation.
/// Use these instead of string literals throughout the app.
abstract class AppRoutes {
  // Authentication & Onboarding
  static const auth = '/auth';
  static const timezoneSetup = '/timezone-setup';
  static const pairing = '/pairing';

  // Universal Link / App Link deep-link entry point
  // Matches https://coupleschedule.app/invite/:code
  static const inviteBase = '/invite';
  static String invite(String code) => '/invite/$code';

  // Main App
  static const home = '/home';
  static const calendar = '/calendar';
  static const blocks = '/blocks';
  static const blockForm = '/block-form';
  static const overlap = '/overlap';
  static const settings = '/settings';
}

/// Route names for GoRouter state access.
abstract class RouteNames {
  static const auth = 'auth';
  static const timezoneSetup = 'timezone-setup';
  static const pairing = 'pairing';
  static const invite = 'invite';
  static const home = 'home';
  static const calendar = 'calendar';
  static const blocks = 'blocks';
  static const blockForm = 'block-form';
  static const overlap = 'overlap';
  static const settings = 'settings';
}

/// Type-safe route arguments for screens that need parameters.
class BlockFormArgs {
  final String? blockId;
  final DateTime? initialDate;

  const BlockFormArgs({this.blockId, this.initialDate});

  Map<String, dynamic> toMap() => {
    'blockId': blockId,
    'initialDate': initialDate?.toIso8601String(),
  };

  factory BlockFormArgs.fromMap(Map<String, dynamic> map) {
    return BlockFormArgs(
      blockId: map['blockId'] as String?,
      initialDate: map['initialDate'] != null
          ? DateTime.tryParse(map['initialDate'] as String)
          : null,
    );
  }
}

/// Extension methods for easier navigation.
extension GoRouterNavigation on GoRouter {
  void goToAuth() => go(AppRoutes.auth);
  void goToTimezoneSetup() => go(AppRoutes.timezoneSetup);
  void goToPairing() => go(AppRoutes.pairing);
  void goToHome() => go(AppRoutes.home);
  void goToCalendar() => go(AppRoutes.calendar);
  void goToBlocks() => go(AppRoutes.blocks);
  void goToBlockForm({String? blockId, DateTime? initialDate}) {
    go(
      AppRoutes.blockForm,
      extra: BlockFormArgs(blockId: blockId, initialDate: initialDate),
    );
  }

  void goToOverlap() => go(AppRoutes.overlap);
  void goToSettings() => go(AppRoutes.settings);
}
