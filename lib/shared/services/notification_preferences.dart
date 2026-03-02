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

  bool get newWindowAlerts => _prefs.getBool(_kNewWindowAlerts) ?? true;

  bool get dailyDigest => _prefs.getBool(_kDailyDigest) ?? false;

  TimeOfDay get quietHoursStart => TimeOfDay(
        hour: _prefs.getInt(_kQuietHoursStartHour) ?? 22,
        minute: _prefs.getInt(_kQuietHoursStartMinute) ?? 0,
      );

  TimeOfDay get quietHoursEnd => TimeOfDay(
        hour: _prefs.getInt(_kQuietHoursEndHour) ?? 8,
        minute: _prefs.getInt(_kQuietHoursEndMinute) ?? 0,
      );

  // ── Setters ──────────────────────────────────────────────────────────────

  Future<void> setNewWindowAlerts(bool value) =>
      _prefs.setBool(_kNewWindowAlerts, value);

  Future<void> setDailyDigest(bool value) =>
      _prefs.setBool(_kDailyDigest, value);

  Future<void> setQuietHoursStart(TimeOfDay time) async {
    await _prefs.setInt(_kQuietHoursStartHour, time.hour);
    await _prefs.setInt(_kQuietHoursStartMinute, time.minute);
  }

  Future<void> setQuietHoursEnd(TimeOfDay time) async {
    await _prefs.setInt(_kQuietHoursEndHour, time.hour);
    await _prefs.setInt(_kQuietHoursEndMinute, time.minute);
  }
}
