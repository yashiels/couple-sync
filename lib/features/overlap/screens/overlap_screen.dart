import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/overlap_result.dart';
import '../../../core/overlap/overlap_controller.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/format_utils.dart';
import '../../../services/providers/couple_providers.dart';
import '../../../services/providers/auth_state_provider.dart';
import '../widgets/window_card_widget.dart';
import '../widgets/window_detail_dialog.dart';

/// Overlap screen displaying mutual free time windows with filtering and sorting.
///
/// Reads real data from Firestore via providers:
/// - currentUserProfileProvider for user timezone
/// - partnerProfileProvider for partner timezone
/// - overlapWindowsProvider for real overlap windows
class OverlapScreen extends ConsumerStatefulWidget {
  const OverlapScreen({super.key});

  @override
  ConsumerState<OverlapScreen> createState() => _OverlapScreenState();
}

class _OverlapScreenState extends ConsumerState<OverlapScreen> {
  // Filter state
  int? _minDurationMinutes;
  double? _minScore;
  String _sortBy = 'date'; // 'date', 'duration', 'score'

  List<OverlapWindow> _filterAndSort(List<OverlapWindow> windows) {
    var result = List<OverlapWindow>.from(windows);

    // Apply filters
    if (_minDurationMinutes != null) {
      result = result
          .where((w) => w.durationMinutes >= _minDurationMinutes!)
          .toList();
    }

    if (_minScore != null) {
      result = result.where((w) => w.score >= _minScore!).toList();
    }

    // Apply sorting
    switch (_sortBy) {
      case 'date':
        result.sort((a, b) => a.startUtc.compareTo(b.startUtc));
        break;
      case 'duration':
        result.sort((a, b) => b.durationMinutes.compareTo(a.durationMinutes));
        break;
      case 'score':
        result.sort((a, b) => b.score.compareTo(a.score));
        break;
    }

    // Limit to 10 windows
    return result.take(10).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final userProfile = ref.watch(currentUserProfileProvider);
    final partnerAsync = ref.watch(partnerProfileProvider);
    // Read overlap windows from the device-side controller (async —
    // AsyncNotifierProvider<OverlapResult>). When there is no couple yet,
    // emit a null result so the existing empty-state UI is preserved.
    final coupleId = userProfile?.coupleId;
    final overlapAsync = coupleId == null
        ? const AsyncValue<OverlapResult?>.data(null)
        : ref.watch(overlapControllerProvider(coupleId));

    // If the user has no couple yet, show a friendly message
    if (userProfile?.coupleId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mutual Free Time')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.people_outline,
                  size: 64,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 24),
                Text(
                  'No couple paired yet.',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Pair with your partner to see mutual free time.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.go(AppRoutes.pairing),
                  icon: const Icon(Icons.link),
                  label: const Text('Pair with partner'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final userTimezone = userProfile?.timezone ?? 'UTC';
    final partnerTimezone = partnerAsync.valueOrNull?.timezone ?? 'UTC';

    return overlapAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(
          title: const Text('Mutual Free Time'),
          actions: [
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: () => _showFilterDialog(),
              tooltip: 'Filter & Sort',
            ),
          ],
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(title: const Text('Mutual Free Time')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 24),
                Text(
                  'Something went wrong.',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  error.toString(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    final id = ref.read(currentUserProfileProvider)?.coupleId;
                    if (id != null) {
                      ref.invalidate(overlapControllerProvider(id));
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (overlapResult) {
        final allWindows = overlapResult?.windows ?? [];
        final windows = _filterAndSort(allWindows);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Mutual Free Time'),
            actions: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                onPressed: () => _showFilterDialog(),
                tooltip: 'Filter & Sort',
              ),
            ],
          ),
          body: allWindows.isEmpty
              ? _buildNoOverlapsState(theme)
              : windows.isEmpty
              ? _buildEmptyState(theme)
              : Column(
                  children: [
                    // Filter summary bar
                    _buildFilterSummary(theme),

                    // Hint when the 10-window cap is active
                    if (windows.length == 10) _buildCapHint(theme),

                    // Windows list
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: windows.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: WindowCardWidget(
                              window: windows[index],
                              userTimezone: userTimezone,
                              partnerTimezone: partnerTimezone,
                              onTap: () => _showWindowDetails(
                                windows[index],
                                userTimezone,
                                partnerTimezone,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  /// Hint shown when the visible list is capped at 10 windows.
  Widget _buildCapHint(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing top 10 — refine filters for more',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shown when the provider returns data but there are zero overlap windows.
  Widget _buildNoOverlapsState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_busy,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              'No overlap windows found.',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Try adding more availability blocks.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when filters exclude all windows.
  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_busy,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              'No free time found.',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Try adjusting your filters.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_minDurationMinutes != null || _minScore != null)
              TextButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.clear),
                label: const Text('Clear Filters'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSummary(ThemeData theme) {
    final hasFilters = _minDurationMinutes != null || _minScore != null;

    if (!hasFilters) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.filter_list,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (_minDurationMinutes != null)
                  FilterChip(
                    label: Text('Min ${formatDurationMinutes(_minDurationMinutes!)}'),
                    selected: true,
                    onSelected: (_) =>
                        setState(() => _minDurationMinutes = null),
                  ),
                if (_minScore != null)
                  FilterChip(
                    label: Text('Min score ${_minScore!.round()}'),
                    selected: true,
                    onSelected: (_) => setState(() => _minScore = null),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Filter & Sort'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Minimum Duration
                Text(
                  'Minimum Duration',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildDurationChoice(null, 'Any', setDialogState),
                    _buildDurationChoice(30, '30m', setDialogState),
                    _buildDurationChoice(60, '1h', setDialogState),
                    _buildDurationChoice(120, '2h', setDialogState),
                  ],
                ),

                const SizedBox(height: 24),

                // Minimum Score
                Text(
                  'Minimum Score',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildScoreChoice(null, 'Any', setDialogState),
                    _buildScoreChoice(15, '15+', setDialogState),
                    _buildScoreChoice(25, '25+', setDialogState),
                    _buildScoreChoice(40, '40+', setDialogState),
                  ],
                ),

                const SizedBox(height: 24),

                // Sort By
                Text('Sort By', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildSortChoice('date', 'Date', setDialogState),
                    _buildSortChoice('duration', 'Duration', setDialogState),
                    _buildSortChoice('score', 'Score', setDialogState),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _clearFilters();
                },
                child: const Text('Clear All'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(
                    () {},
                  ); // refresh filter summary + list with new filters
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDurationChoice(
    int? minutes,
    String label,
    StateSetter setDialogState,
  ) {
    final isSelected = _minDurationMinutes == minutes;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setDialogState(() => _minDurationMinutes = selected ? minutes : null);
      },
    );
  }

  Widget _buildScoreChoice(
    double? score,
    String label,
    StateSetter setDialogState,
  ) {
    final isSelected = _minScore == score;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setDialogState(() => _minScore = selected ? score : null);
      },
    );
  }

  Widget _buildSortChoice(
    String sortBy,
    String label,
    StateSetter setDialogState,
  ) {
    final isSelected = _sortBy == sortBy;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      // Only update when a new chip is selected; ignore tap on the already-
      // selected chip so the sort order never enters an unselected state.
      onSelected: (selected) {
        if (!selected) return;
        setDialogState(() => _sortBy = sortBy);
      },
    );
  }

  void _showWindowDetails(
    OverlapWindow window,
    String userTimezone,
    String partnerTimezone,
  ) {
    showDialog(
      context: context,
      builder: (context) => WindowDetailDialog(
        window: window,
        userTimezone: userTimezone,
        partnerTimezone: partnerTimezone,
      ),
    );
  }

  void _clearFilters() {
    setState(() {
      _minDurationMinutes = null;
      _minScore = null;
    });
  }
}
