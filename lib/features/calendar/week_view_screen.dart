import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/time_block.dart';
import '../../core/models/overlap_result.dart';
import '../../core/router/routes.dart';
import 'week_view_widget.dart';

/// Calendar week view screen displaying a 7-day view with blocks and overlap windows.
/// 
/// This screen uses mock data since STORY-026 (Cloud Functions) was skipped.
/// TODO: Replace mock data with Firestore queries when Cloud Functions are implemented.
/// TODO: Query userBlocks from Firestore: timeblocks/{coupleId}/blocks where userId == currentUserId
/// TODO: Query partnerBlocks from Firestore: timeblocks/{coupleId}/blocks where userId == partnerId
/// TODO: Query overlapWindows from Firestore: overlaps/{coupleId}/windows/latest
class WeekViewScreen extends StatefulWidget {
  const WeekViewScreen({super.key});

  @override
  State<WeekViewScreen> createState() => _WeekViewScreenState();
}

class _WeekViewScreenState extends State<WeekViewScreen> {
  // Current week being displayed
  late DateTime _currentWeekStart;
  
  // Mock data - will be replaced with Firestore queries
  late List<TimeBlock> _userBlocks;
  late List<TimeBlock> _partnerBlocks;
  late List<OverlapWindow> _overlapWindows;
  
  // TODO: Get current user ID from auth provider
  static const String _currentUserId = 'user_123';
  
  @override
  void initState() {
    super.initState();
    _currentWeekStart = _getWeekStart(DateTime.now());
    _loadMockData();
  }
  
  /// Get the start of the week (Monday) for a given date
  DateTime _getWeekStart(DateTime date) {
    final weekday = date.weekday;
    return DateTime(date.year, date.month, date.day).subtract(Duration(days: weekday - 1));
  }
  
  /// Load mock data for the current week
  /// TODO: Replace with Firestore queries
  void _loadMockData() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // Mock user blocks
    _userBlocks = [
      // Today's blocks
      TimeBlock(
        userId: _currentUserId,
        title: 'Work',
        type: TimeBlockType.busy,
        category: TimeBlockCategory.work,
        startUtc: today.add(const Duration(hours: 9)).millisecondsSinceEpoch,
        endUtc: today.add(const Duration(hours: 17)).millisecondsSinceEpoch,
        timezone: 'Africa/Johannesburg',
        source: TimeBlockSource.manual,
        visibility: TimeBlockVisibility.bothPartners,
        createdAt: now,
      ),
      TimeBlock(
        userId: _currentUserId,
        title: 'Gym',
        type: TimeBlockType.busy,
        category: TimeBlockCategory.exercise,
        startUtc: today.add(const Duration(hours: 18)).millisecondsSinceEpoch,
        endUtc: today.add(const Duration(hours: 19)).millisecondsSinceEpoch,
        timezone: 'Africa/Johannesburg',
        source: TimeBlockSource.manual,
        visibility: TimeBlockVisibility.bothPartners,
        createdAt: now,
      ),
      // Tomorrow's blocks
      TimeBlock(
        userId: _currentUserId,
        title: 'Team Meeting',
        type: TimeBlockType.busy,
        category: TimeBlockCategory.work,
        startUtc: today.add(const Duration(days: 1, hours: 10)).millisecondsSinceEpoch,
        endUtc: today.add(const Duration(days: 1, hours: 11)).millisecondsSinceEpoch,
        timezone: 'Africa/Johannesburg',
        source: TimeBlockSource.google,
        visibility: TimeBlockVisibility.bothPartners,
        createdAt: now,
      ),
      // Day after tomorrow
      TimeBlock(
        userId: _currentUserId,
        title: 'Study Session',
        type: TimeBlockType.busy,
        category: TimeBlockCategory.study,
        startUtc: today.add(const Duration(days: 2, hours: 14)).millisecondsSinceEpoch,
        endUtc: today.add(const Duration(days: 2, hours: 16)).millisecondsSinceEpoch,
        timezone: 'Africa/Johannesburg',
        source: TimeBlockSource.manual,
        visibility: TimeBlockVisibility.bothPartners,
        createdAt: now,
      ),
    ];
    
    // Mock partner blocks (different user ID)
    _partnerBlocks = [
      // Today's blocks
      TimeBlock(
        userId: 'partner_456',
        title: 'Work',
        type: TimeBlockType.busy,
        category: TimeBlockCategory.work,
        startUtc: today.add(const Duration(hours: 8)).millisecondsSinceEpoch,
        endUtc: today.add(const Duration(hours: 16)).millisecondsSinceEpoch,
        timezone: 'Europe/London',
        source: TimeBlockSource.manual,
        visibility: TimeBlockVisibility.bothPartners,
        createdAt: now,
      ),
      TimeBlock(
        userId: 'partner_456',
        title: 'Dinner with Friends',
        type: TimeBlockType.busy,
        category: TimeBlockCategory.social,
        startUtc: today.add(const Duration(hours: 19)).millisecondsSinceEpoch,
        endUtc: today.add(const Duration(hours: 22)).millisecondsSinceEpoch,
        timezone: 'Europe/London',
        source: TimeBlockSource.manual,
        visibility: TimeBlockVisibility.bothPartners,
        createdAt: now,
      ),
      // Tomorrow's blocks
      TimeBlock(
        userId: 'partner_456',
        title: 'Client Call',
        type: TimeBlockType.busy,
        category: TimeBlockCategory.work,
        startUtc: today.add(const Duration(days: 1, hours: 14)).millisecondsSinceEpoch,
        endUtc: today.add(const Duration(days: 1, hours: 15)).millisecondsSinceEpoch,
        timezone: 'Europe/London',
        source: TimeBlockSource.google,
        visibility: TimeBlockVisibility.bothPartners,
        createdAt: now,
      ),
      // Day after tomorrow
      TimeBlock(
        userId: 'partner_456',
        title: 'Morning Run',
        type: TimeBlockType.busy,
        category: TimeBlockCategory.exercise,
        startUtc: today.add(const Duration(days: 2, hours: 7)).millisecondsSinceEpoch,
        endUtc: today.add(const Duration(days: 2, hours: 8)).millisecondsSinceEpoch,
        timezone: 'Europe/London',
        source: TimeBlockSource.manual,
        visibility: TimeBlockVisibility.bothPartners,
        createdAt: now,
      ),
    ];
    
    // Mock overlap windows (times when both are free)
    _overlapWindows = [
      OverlapWindow(
        startUtc: today.add(const Duration(hours: 17)).millisecondsSinceEpoch,
        endUtc: today.add(const Duration(hours: 18)).millisecondsSinceEpoch,
        durationMinutes: 60,
        score: 8.5,
        reasonableBoth: true,
      ),
      OverlapWindow(
        startUtc: today.add(const Duration(days: 1, hours: 11)).millisecondsSinceEpoch,
        endUtc: today.add(const Duration(days: 1, hours: 13)).millisecondsSinceEpoch,
        durationMinutes: 120,
        score: 9.2,
        reasonableBoth: true,
      ),
      OverlapWindow(
        startUtc: today.add(const Duration(days: 2, hours: 16)).millisecondsSinceEpoch,
        endUtc: today.add(const Duration(days: 2, hours: 18)).millisecondsSinceEpoch,
        durationMinutes: 120,
        score: 7.8,
        reasonableBoth: true,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: _goToToday,
            tooltip: 'Go to today',
          ),
        ],
      ),
      body: WeekViewWidget(
        initialWeek: _currentWeekStart,
        userBlocks: _userBlocks,
        partnerBlocks: _partnerBlocks,
        overlapWindows: _overlapWindows,
        currentUserId: _currentUserId,
        onWeekChanged: _onWeekChanged,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewBlock,
        child: const Icon(Icons.add),
      ),
    );
  }
  
  /// Navigate to today's week
  void _goToToday() {
    setState(() {
      _currentWeekStart = _getWeekStart(DateTime.now());
    });
  }
  
  /// Handle week change from swipe navigation
  void _onWeekChanged(DateTime weekStart) {
    setState(() {
      _currentWeekStart = weekStart;
    });
    
    // TODO: Load blocks and overlap windows for the new week from Firestore
    // For now, we'll just regenerate mock data centered on the new week
    _loadMockDataForWeek(weekStart);
  }
  
  /// Load mock data for a specific week
  /// TODO: Replace with Firestore query
  void _loadMockDataForWeek(DateTime weekStart) {
    // For now, just keep the existing mock data
    // In production, this would query Firestore for blocks in the date range
    // Query: timeblocks/{coupleId}/blocks
    //   where startUtc >= weekStart.millisecondsSinceEpoch
    //   AND endUtc < weekStart.add(Duration(days: 7)).millisecondsSinceEpoch
  }
  
  /// Navigate to block form to add new block
  void _addNewBlock() {
    context.go(AppRoutes.blockForm, extra: BlockFormArgs(
      initialDate: DateTime.now(),
    ));
  }
}
