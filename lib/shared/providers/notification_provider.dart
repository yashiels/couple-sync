import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/notification_preferences.dart';
import '../services/notification_service.dart';

// ── Notification service ──────────────────────────────────────────────────────

final notificationServiceProvider = Provider<NotificationService>(
  (_) => NotificationService.instance,
);

// ── Preferences (async initialisation) ───────────────────────────────────────

final notificationPreferencesProvider =
    FutureProvider<NotificationPreferences>(
  (_) => NotificationPreferences.create(),
);

// ── Derived state providers ───────────────────────────────────────────────────

/// Whether new window-of-opportunity alerts are enabled.
final newWindowAlertsProvider = StateNotifierProvider<_BoolPrefNotifier, bool>(
  (ref) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);
    final initial = prefsAsync.valueOrNull?.newWindowAlerts ?? true;
    return _BoolPrefNotifier(
      initial: initial,
      onChanged: (v) =>
          prefsAsync.valueOrNull?.setNewWindowAlerts(v),
    );
  },
);

/// Whether the daily digest notification is enabled.
final dailyDigestProvider = StateNotifierProvider<_BoolPrefNotifier, bool>(
  (ref) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);
    final initial = prefsAsync.valueOrNull?.dailyDigest ?? false;
    return _BoolPrefNotifier(
      initial: initial,
      onChanged: (v) =>
          prefsAsync.valueOrNull?.setDailyDigest(v),
    );
  },
);

/// Quiet hours start time.
final quietHoursStartProvider =
    StateNotifierProvider<_TimeOfDayNotifier, TimeOfDay>(
  (ref) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);
    final initial =
        prefsAsync.valueOrNull?.quietHoursStart ?? const TimeOfDay(hour: 22, minute: 0);
    return _TimeOfDayNotifier(
      initial: initial,
      onChanged: (t) =>
          prefsAsync.valueOrNull?.setQuietHoursStart(t),
    );
  },
);

/// Quiet hours end time.
final quietHoursEndProvider =
    StateNotifierProvider<_TimeOfDayNotifier, TimeOfDay>(
  (ref) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);
    final initial =
        prefsAsync.valueOrNull?.quietHoursEnd ?? const TimeOfDay(hour: 8, minute: 0);
    return _TimeOfDayNotifier(
      initial: initial,
      onChanged: (t) =>
          prefsAsync.valueOrNull?.setQuietHoursEnd(t),
    );
  },
);

// ── Helpers ───────────────────────────────────────────────────────────────────

class _BoolPrefNotifier extends StateNotifier<bool> {
  _BoolPrefNotifier({required bool initial, required this.onChanged})
      : super(initial);

  final void Function(bool) onChanged;

  void toggle() {
    state = !state;
    onChanged(state);
  }

  void set(bool value) {
    state = value;
    onChanged(state);
  }
}

class _TimeOfDayNotifier extends StateNotifier<TimeOfDay> {
  _TimeOfDayNotifier({required TimeOfDay initial, required this.onChanged})
      : super(initial);

  final void Function(TimeOfDay) onChanged;

  void set(TimeOfDay time) {
    state = time;
    onChanged(state);
  }
}
