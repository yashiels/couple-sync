import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Couple settings model ─────────────────────────────────────────────────────

/// Privacy and scheduling settings persisted to Firestore under
/// `couples/{coupleId}/settings`.
class CoupleSettings {
  const CoupleSettings({
    this.showTitles = true,
    this.minSlotDurationMinutes = 30,
  });

  /// If false, only show busy/free without event titles.
  final bool showTitles;

  /// Minimum free-slot duration shown to the partner (15/30/45/60 min).
  final int minSlotDurationMinutes;

  factory CoupleSettings.fromFirestore(Map<String, dynamic> data) {
    return CoupleSettings(
      showTitles: data['showTitles'] as bool? ?? true,
      minSlotDurationMinutes: data['minSlotDurationMinutes'] as int? ?? 30,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'showTitles': showTitles,
        'minSlotDurationMinutes': minSlotDurationMinutes,
      };

  CoupleSettings copyWith({
    bool? showTitles,
    int? minSlotDurationMinutes,
  }) {
    return CoupleSettings(
      showTitles: showTitles ?? this.showTitles,
      minSlotDurationMinutes:
          minSlotDurationMinutes ?? this.minSlotDurationMinutes,
    );
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// The couple ID for the current user — must be overridden at login.
final coupleIdProvider = StateProvider<String?>((ref) => null);

/// Streams couple settings from Firestore.
final coupleSettingsProvider =
    StreamProvider.autoDispose<CoupleSettings>((ref) {
  final coupleId = ref.watch(coupleIdProvider);
  if (coupleId == null) {
    return Stream.value(const CoupleSettings());
  }

  return FirebaseFirestore.instance
      .collection('couples')
      .doc(coupleId)
      .collection('settings')
      .doc('prefs')
      .snapshots()
      .map((snap) {
    if (!snap.exists || snap.data() == null) return const CoupleSettings();
    return CoupleSettings.fromFirestore(snap.data()!);
  });
});

/// Notifier that exposes write operations on top of [coupleSettingsProvider].
final coupleSettingsNotifierProvider =
    AsyncNotifierProvider.autoDispose<CoupleSettingsNotifier, CoupleSettings>(
  CoupleSettingsNotifier.new,
);

class CoupleSettingsNotifier
    extends AutoDisposeAsyncNotifier<CoupleSettings> {
  @override
  Future<CoupleSettings> build() async {
    return ref.watch(coupleSettingsProvider.future);
  }

  Future<void> setShowTitles(bool value) => _update((s) => s.copyWith(showTitles: value));

  Future<void> setMinSlotDuration(int minutes) =>
      _update((s) => s.copyWith(minSlotDurationMinutes: minutes));

  Future<void> _update(CoupleSettings Function(CoupleSettings) updater) async {
    final coupleId = ref.read(coupleIdProvider);
    if (coupleId == null) return;

    final current = await future;
    final updated = updater(current);

    await FirebaseFirestore.instance
        .collection('couples')
        .doc(coupleId)
        .collection('settings')
        .doc('prefs')
        .set(updated.toFirestore(), SetOptions(merge: true));
  }
}

// ── Calendar source model ─────────────────────────────────────────────────────

enum CalendarSourceType { googleCalendar, appleCalendar, outlook }

class CalendarSource {
  const CalendarSource({
    required this.id,
    required this.type,
    required this.email,
    this.displayName,
  });

  final String id;
  final CalendarSourceType type;
  final String email;
  final String? displayName;

  factory CalendarSource.fromFirestore(
      String id, Map<String, dynamic> data) {
    return CalendarSource(
      id: id,
      type: CalendarSourceType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => CalendarSourceType.googleCalendar,
      ),
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String?,
    );
  }
}

/// Streams the list of connected calendar sources for the current user.
final calendarSourcesProvider =
    StreamProvider.autoDispose<List<CalendarSource>>((ref) {
  final coupleId = ref.watch(coupleIdProvider);
  if (coupleId == null) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection('couples')
      .doc(coupleId)
      .collection('calendarSources')
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => CalendarSource.fromFirestore(d.id, d.data()))
          .toList());
});
