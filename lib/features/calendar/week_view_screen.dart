import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/time_block.dart';
import '../../core/models/overlap_result.dart';
import '../../core/router/routes.dart';
import '../../services/providers/auth_state_provider.dart';
import '../../services/providers/couple_providers.dart';
import 'week_view_widget.dart';

/// Calendar week view screen displaying a 7-day view with blocks and overlap windows.
///
/// Reads real-time data from Riverpod providers:
/// - [userBlocksProvider] for the current user's time blocks
/// - [partnerBlocksProvider] for the partner's time blocks
/// - [overlapWindowsProvider] for computed overlap windows
class WeekViewScreen extends ConsumerStatefulWidget {
  const WeekViewScreen({super.key});

  @override
  ConsumerState<WeekViewScreen> createState() => _WeekViewScreenState();
}

class _WeekViewScreenState extends ConsumerState<WeekViewScreen> {
  // Current week being displayed
  late DateTime _currentWeekStart;

  @override
  void initState() {
    super.initState();
    _currentWeekStart = _getWeekStart(DateTime.now());
  }

  /// Get the start of the week (Monday) for a given date
  DateTime _getWeekStart(DateTime date) {
    final weekday = date.weekday;
    return DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: weekday - 1));
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);
    final userBlocksAsync = ref.watch(userBlocksProvider);
    final partnerBlocksAsync = ref.watch(partnerBlocksProvider);
    final overlapAsync = ref.watch(overlapWindowsProvider);

    // Guard: userId must be available
    if (currentUserId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Calendar')),
        body: const Center(
          child: Text('Not authenticated. Please sign in.'),
        ),
      );
    }

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
      body: _buildBody(
        currentUserId: currentUserId,
        userBlocksAsync: userBlocksAsync,
        partnerBlocksAsync: partnerBlocksAsync,
        overlapAsync: overlapAsync,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewBlock,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody({
    required String currentUserId,
    required AsyncValue<List<TimeBlock>> userBlocksAsync,
    required AsyncValue<List<TimeBlock>> partnerBlocksAsync,
    required AsyncValue<OverlapResult?> overlapAsync,
  }) {
    // Check for errors first
    if (userBlocksAsync is AsyncError) {
      return _buildErrorState(
        'Failed to load your blocks',
        userBlocksAsync.error,
        () => ref.invalidate(userBlocksProvider),
      );
    }
    if (partnerBlocksAsync is AsyncError) {
      return _buildErrorState(
        'Failed to load partner blocks',
        partnerBlocksAsync.error,
        () => ref.invalidate(partnerBlocksProvider),
      );
    }
    if (overlapAsync is AsyncError) {
      return _buildErrorState(
        'Failed to load overlap windows',
        overlapAsync.error,
        () => ref.invalidate(overlapWindowsProvider),
      );
    }

    // Show loading if any provider is still loading (and has no prior data)
    if (userBlocksAsync is AsyncLoading && !userBlocksAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    if (partnerBlocksAsync is AsyncLoading && !partnerBlocksAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    if (overlapAsync is AsyncLoading && !overlapAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    final userBlocks = userBlocksAsync.valueOrNull ?? [];
    final partnerBlocks = partnerBlocksAsync.valueOrNull ?? [];
    final overlapWindows = overlapAsync.valueOrNull?.windows ?? [];

    // Empty state: no blocks at all
    if (userBlocks.isEmpty && partnerBlocks.isEmpty && overlapWindows.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No blocks yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to create your first time block',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return WeekViewWidget(
      initialWeek: _currentWeekStart,
      userBlocks: userBlocks,
      partnerBlocks: partnerBlocks,
      overlapWindows: overlapWindows,
      currentUserId: currentUserId,
      onWeekChanged: _onWeekChanged,
    );
  }

  Widget _buildErrorState(String message, Object? error, VoidCallback onRetry) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
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
  }

  /// Navigate to block form to add new block
  void _addNewBlock() {
    context.push(AppRoutes.blockForm, extra: BlockFormArgs(
      initialDate: DateTime.now(),
    ));
  }
}
