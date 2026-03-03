import '../../shared/models/free_window.dart';
import '../../shared/models/time_block_model.dart';

/// Design-time mock data for UI development.
class MockData {
  MockData._();

  static final String myCity = 'New York';
  static final String myTimezone = 'America/New_York';
  static final String partnerCity = 'London';
  static final String partnerTimezone = 'Europe/London';

  /// Returns a set of mock [TimeBlock] entries spanning today in UTC.
  static List<TimeBlock> todayBlocks() {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    return [
      TimeBlock(
        id: '1',
        userId: 'me',
        title: 'Team standup',
        startUtc: today.add(const Duration(hours: 14)), // 9am EST
        endUtc: today.add(const Duration(hours: 14, minutes: 30)),
        type: BlockType.busy,
        timezone: myTimezone,
        source: BlockSource.google,
        visibility: TimeBlockVisibility.bothPartners,
        category: BlockCategory.work,
        createdAt: DateTime.now().toUtc(),
      ),
      TimeBlock(
        id: '2',
        userId: 'me',
        title: 'Commute',
        startUtc: today.add(const Duration(hours: 12)), // 7am EST
        endUtc: today.add(const Duration(hours: 13)),
        type: BlockType.busy,
        timezone: myTimezone,
        source: BlockSource.manual,
        visibility: TimeBlockVisibility.bothPartners,
        category: BlockCategory.commute,
        createdAt: DateTime.now().toUtc(),
      ),
      TimeBlock(
        id: '3',
        userId: 'me',
        title: 'Gym',
        startUtc: today.add(const Duration(hours: 23)), // 6pm EST
        endUtc: today.add(const Duration(hours: 24)),
        type: BlockType.busy,
        timezone: myTimezone,
        source: BlockSource.manual,
        visibility: TimeBlockVisibility.bothPartners,
        category: BlockCategory.exercise,
        createdAt: DateTime.now().toUtc(),
      ),
      TimeBlock(
        id: '4',
        userId: 'partner',
        title: 'Busy',
        startUtc: today.add(const Duration(hours: 9)), // 9am GMT
        endUtc: today.add(const Duration(hours: 10)),
        type: BlockType.busy,
        timezone: partnerTimezone,
        source: BlockSource.google,
        visibility: TimeBlockVisibility.bothPartners,
        category: BlockCategory.other,
        createdAt: DateTime.now().toUtc(),
      ),
      TimeBlock(
        id: '5',
        userId: 'partner',
        title: 'Busy',
        startUtc: today.add(const Duration(hours: 13)), // 1pm GMT
        endUtc: today.add(const Duration(hours: 14)),
        type: BlockType.busy,
        timezone: partnerTimezone,
        source: BlockSource.google,
        visibility: TimeBlockVisibility.bothPartners,
        category: BlockCategory.other,
        createdAt: DateTime.now().toUtc(),
      ),
      TimeBlock(
        id: '6',
        userId: 'partner',
        title: 'Busy',
        startUtc: today.add(const Duration(hours: 18)), // 6pm GMT
        endUtc: today.add(const Duration(hours: 19)),
        type: BlockType.busy,
        timezone: partnerTimezone,
        source: BlockSource.manual,
        visibility: TimeBlockVisibility.bothPartners,
        category: BlockCategory.other,
        createdAt: DateTime.now().toUtc(),
      ),
    ];
  }

  /// Returns a set of mock [FreeWindow] entries for the next four days.
  static List<FreeWindow> upcomingWindows() {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    return [
      FreeWindow(
        id: 'w1',
        startUtc: today.add(const Duration(hours: 24)), // tomorrow morning
        endUtc: today.add(const Duration(hours: 26)),
        timezoneA: myTimezone,
        timezoneB: partnerTimezone,
        cityA: myCity,
        cityB: partnerCity,
        suggestedActivity: 'Morning coffee call',
      ),
      FreeWindow(
        id: 'w2',
        startUtc: today.add(const Duration(hours: 33, minutes: 30)),
        endUtc: today.add(const Duration(hours: 35, minutes: 30)),
        timezoneA: myTimezone,
        timezoneB: partnerTimezone,
        cityA: myCity,
        cityB: partnerCity,
        suggestedActivity: 'Watch a movie together',
      ),
      FreeWindow(
        id: 'w3',
        startUtc: today.add(const Duration(hours: 48)),
        endUtc: today.add(const Duration(hours: 51)),
        timezoneA: myTimezone,
        timezoneB: partnerTimezone,
        cityA: myCity,
        cityB: partnerCity,
        suggestedActivity: 'Cook together on video',
      ),
      FreeWindow(
        id: 'w4',
        startUtc: today.add(const Duration(hours: 72)),
        endUtc: today.add(const Duration(hours: 73, minutes: 30)),
        timezoneA: myTimezone,
        timezoneB: partnerTimezone,
        cityA: myCity,
        cityB: partnerCity,
        suggestedActivity: 'Online game night',
      ),
      FreeWindow(
        id: 'w5',
        startUtc: today.add(const Duration(hours: 96, minutes: 30)),
        endUtc: today.add(const Duration(hours: 99)),
        timezoneA: myTimezone,
        timezoneB: partnerTimezone,
        cityA: myCity,
        cityB: partnerCity,
        suggestedActivity: 'Virtual dinner date',
      ),
    ];
  }
}
