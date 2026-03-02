import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps [SharedPreferences] for all notification-related user preferences.
class NotificationPreferences {
  NotificationPreferences._(this._prefs);

  /// Loads persisted preferences and returns an initialised instance.
  static Future<NotificationPreferences> create() async {
    final prefs = await SharedPreferences.getInstance();
    return NotificationPreferences._(prefs);
  }

  final SharedPreferences _prefs;

  // Keys
  static const _kNewWindowAlerts = 'notif_new_window_alerts';
  static const _kDailyDigest = 'notif_daily_digest';
  static const _kQuietHoursStartHour = 'notif_quiet_start_hour';
  static const _kQuietHoursStartMinute = 'notif_quiet_start_minute';
  static const _kQuietHoursEndHour = 'notif_quiet_end_hour';
  static const _kQuietHoursEndMinute = 'notif_quiet_end_minute';

  // ── Getters ──────────────────────────────────────────────────────────────

  /// Whether new free-window push alerts are enabled (default `true`).
  bool get newWindowAlerts => _prefs.getBool(_kNewWindowAlerts) ?? true;

  /// Whether the daily morning digest notification is enabled (default `false`).
  bool get dailyDigest => _prefs.getBool(_kDailyDigest) ?? false;

  /// The start of the quiet-hours window (default 22:00).
  TimeOfDay get quietHoursStart => TimeOfDay(
        hour: _prefs.getInt(_kQuietHoursStartHour) ?? 22,
        minute: _prefs.getInt(_kQuietHoursStartMinute) ?? 0,
      );

  /// The end of the quiet-hours window (default 08:00).
  TimeOfDay get quietHoursEnd => TimeOfDay(
        hour: _prefs.getInt(_kQuietHoursEndHour) ?? 8,
        minute: _prefs.getInt(_kQuietHoursEndMinute) ?? 0,
      );

  // ── Setters ──────────────────────────────────────────────────────────────

  /// Persists the [value] for new-window alerts.
  Future<void> setNewWindowAlerts(bool value) =>
      _prefs.setBool(_kNewWindowAlerts, value);

  /// Persists the [value] for the daily digest toggle.
  Future<void> setDailyDigest(bool value) =>
      _prefs.setBool(_kDailyDigest, value);

  /// Persists the quiet-hours [time] start.
  Future<void> setQuietHoursStart(TimeOfDay time) async {
    await _prefs.setInt(_kQuietHoursStartHour, time.hour);
    await _prefs.setInt(_kQuietHoursStartMinute, time.minute);
  }

  /// Persists the quiet-hours [time] end.
  Future<void> setQuietHoursEnd(TimeOfDay time) async {
    await _prefs.setInt(_kQuietHoursEndHour, time.hour);
    await _prefs.setInt(_kQuietHoursEndMinute, time.minute);
  }
}
