import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/models/overlap_result.dart';
import '../../../core/router/routes.dart';
import '../partner_clock_widget.dart';
import '../next_window_card_widget.dart';

/// Home screen displaying partner clocks, next free window, and upcoming windows.
/// Pull-to-refresh triggers calendar sync and overlap refresh.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isRefreshing = false;
  
  // TODO: Replace with actual data from Firestore/Auth service (STORY-019, STORY-026)
  // Mock data for development
  final String _userTimezone = 'Africa/Johannesburg';
  final String _partnerTimezone = 'Europe/London';
  final String _partnerName = 'Partner';
  
  // TODO: Replace with actual overlap data from Cloud Functions (STORY-026)
  // Mock overlap windows for development
  late final OverlapResult _mockOverlapResult;

  @override
  void initState() {
    super.initState();
    _mockOverlapResult = _generateMockWindows();
  }

  OverlapResult _generateMockWindows() {
    // Generate mock windows starting from tomorrow
    final now = DateTime.now();
    final windows = <OverlapWindow>[];
    
    for (int i = 0; i < 6; i++) {
      final start = now.add(Duration(days: i + 1, hours: 18));
      final end = start.add(const Duration(hours: 2));
      
      windows.add(OverlapWindow(
        startUtc: start.millisecondsSinceEpoch,
        endUtc: end.millisecondsSinceEpoch,
        durationMinutes: 120,
        score: 0.85 - (i * 0.05),
        reasonableBoth: true,
      ));
    }
    
    return OverlapResult(
      windows: windows,
      computedAt: now,
      blockHashA: 'mock_hash_a',
      blockHashB: 'mock_hash_b',
    );
  }

  Future<void> _handleRefresh() async {
    setState(() => _isRefreshing = true);
    
    // TODO: Trigger calendar sync (STORY-019)
    // await _calendarService.syncCalendars();
    
    // TODO: Trigger overlap recalculation via Cloud Functions (STORY-026)
    // await _overlapService.refreshOverlaps();
    
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 2));
    
    setState(() => _isRefreshing = false);
  }

  void _handleFabAction(String action) {
    switch (action) {
      case 'add_block':
        context.go(AppRoutes.blockForm);
        break;
      case 'sync_calendar':
        _handleRefresh();
        break;
      case 'view_all':
        context.go(AppRoutes.overlap);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nextWindow = _mockOverlapResult.nextWindow;
    final upcomingWindows = _mockOverlapResult.windowsByTime
        .where((w) => w != nextWindow)
        .take(5)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Couple Sync'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go(AppRoutes.settings),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: _isRefreshing
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Partner clocks
                    PartnerClockWidget(
                      userTimezone: _userTimezone,
                      partnerTimezone: _partnerTimezone,
                      partnerName: _partnerName,
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Next window card
                    NextWindowCard(
                      window: nextWindow,
                      userTimezone: _userTimezone,
                      partnerTimezone: _partnerTimezone,
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Upcoming windows header
                    Text(
                      'Upcoming Windows',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Upcoming windows list
                    if (upcomingWindows.isEmpty)
                      _buildEmptyUpcoming(theme)
                    else
                      ...upcomingWindows.map(
                        (window) => _UpcomingWindowCard(
                          window: window,
                          userTimezone: _userTimezone,
                        ),
                      ),
                  ],
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showQuickActions(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyUpcoming(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text(
            'No more upcoming windows',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  void _showQuickActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Add Block'),
              subtitle: const Text('Block out time in your schedule'),
              onTap: () {
                Navigator.pop(context);
                _handleFabAction('add_block');
              },
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Sync Calendar'),
              subtitle: const Text('Refresh from Google Calendar'),
              onTap: () {
                Navigator.pop(context);
                _handleFabAction('sync_calendar');
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_view_day),
              title: const Text('View All Windows'),
              subtitle: const Text('See all upcoming free times'),
              onTap: () {
                Navigator.pop(context);
                _handleFabAction('view_all');
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact card for upcoming window in list.
class _UpcomingWindowCard extends StatelessWidget {
  final OverlapWindow window;
  final String userTimezone;

  const _UpcomingWindowCard({
    required this.window,
    required this.userTimezone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('EEE, MMM d');
    final timeFormat = DateFormat('h:mm a');
    
    final start = window.startDateTime.toLocal();
    final end = window.endDateTime.toLocal();
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            '${(window.score * 100).toStringAsFixed(0)}%',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          dateFormat.format(start),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '${timeFormat.format(start)} - ${timeFormat.format(end)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Text(
          _formatDuration(window.durationMinutes),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    }
    final hours = minutes ~/ 60;
    final mins = minutes.remainder(60);
    if (mins == 0) {
      return '$hours hr';
    }
    return '$hours hr $mins min';
  }
}
