import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/models/overlap_result.dart';
import '../../../core/router/routes.dart';
import '../../../services/providers/auth_state_provider.dart';
import '../../../services/providers/couple_providers.dart';
import '../partner_clock_widget.dart';
import '../next_window_card_widget.dart';

/// Home screen displaying partner clocks, next free window, and upcoming windows.
/// Pull-to-refresh triggers calendar sync and overlap refresh.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isRefreshing = false;

  Future<void> _handleRefresh() async {
    setState(() => _isRefreshing = true);

    // Invalidate providers to trigger re-fetch
    ref.invalidate(partnerProfileProvider);
    ref.invalidate(overlapWindowsProvider);

    // Allow time for providers to refresh
    await Future.delayed(const Duration(seconds: 1));

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

    // Read current user profile (synchronous — Provider<UserModel?>)
    final userProfile = ref.watch(currentUserProfileProvider);
    // Read partner profile (async — FutureProvider<UserModel?>)
    final partnerAsync = ref.watch(partnerProfileProvider);
    // Read overlap windows (async — StreamProvider<OverlapResult?>)
    final overlapAsync = ref.watch(overlapWindowsProvider);

    // Determine user timezone (fallback to UTC if profile not loaded)
    final userTimezone = userProfile?.timezone ?? 'UTC';

    // If user has no couple, show a "no couple" message
    if (userProfile != null && userProfile.coupleId == null) {
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
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.favorite_border,
                  size: 64,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  'No partner yet',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Pair with your partner to start finding mutual free time.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Build the main content based on async states
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
            : partnerAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => _buildErrorState(
                  theme,
                  'Failed to load partner data',
                  () => ref.invalidate(partnerProfileProvider),
                ),
                data: (partner) {
                  final partnerTimezone = partner?.timezone ?? 'UTC';
                  final partnerName = partner?.displayName ?? 'Partner';

                  return overlapAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stack) => _buildErrorState(
                      theme,
                      'Failed to load overlap data',
                      () => ref.invalidate(overlapWindowsProvider),
                    ),
                    data: (overlapResult) {
                      final nextWindow = overlapResult?.nextWindow;
                      final upcomingWindows = overlapResult?.windowsByTime
                              .where((w) => w != nextWindow)
                              .take(5)
                              .toList() ??
                          [];

                      return SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Partner clocks
                            PartnerClockWidget(
                              userTimezone: userTimezone,
                              partnerTimezone: partnerTimezone,
                              partnerName: partnerName,
                            ),

                            const SizedBox(height: 24),

                            // Next window card
                            NextWindowCard(
                              window: nextWindow,
                              userTimezone: userTimezone,
                              partnerTimezone: partnerTimezone,
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
                                  userTimezone: userTimezone,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showQuickActions(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildErrorState(
      ThemeData theme, String message, VoidCallback onRetry) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
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
            '${window.score.toStringAsFixed(0)}',
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
