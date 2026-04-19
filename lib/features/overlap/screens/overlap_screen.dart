import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../core/models/overlap_result.dart';
import '../../../services/providers/couple_providers.dart';
import '../../../services/providers/auth_state_provider.dart';
import '../widgets/window_card_widget.dart';

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
      result =
          result.where((w) => w.durationMinutes >= _minDurationMinutes!).toList();
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
    final overlapAsync = ref.watch(overlapWindowsProvider);

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
                  onPressed: () => ref.invalidate(overlapWindowsProvider),
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
                                      windows[index], userTimezone, partnerTimezone),
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
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
          ),
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
                  _buildFilterChip(
                    'Min ${_formatDuration(_minDurationMinutes!)}',
                    () => setState(() => _minDurationMinutes = null),
                  ),
                if (_minScore != null)
                  _buildFilterChip(
                    'Min score ${_minScore!.round()}',
                    () => setState(() => _minScore = null),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            child: Icon(
              Icons.close,
              size: 14,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
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
                Text(
                  'Sort By',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
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
      int? minutes, String label, StateSetter setDialogState) {
    final isSelected = _minDurationMinutes == minutes;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setDialogState(() => _minDurationMinutes = selected ? minutes : null);
        setState(() => _minDurationMinutes = selected ? minutes : null);
      },
    );
  }

  Widget _buildScoreChoice(
      double? score, String label, StateSetter setDialogState) {
    final isSelected = _minScore == score;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setDialogState(() => _minScore = selected ? score : null);
        setState(() => _minScore = selected ? score : null);
      },
    );
  }

  Widget _buildSortChoice(
      String sortBy, String label, StateSetter setDialogState) {
    final isSelected = _sortBy == sortBy;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      // Only update when a new chip is selected; ignore tap on the already-
      // selected chip so the sort order never enters an unselected state.
      onSelected: (selected) {
        if (!selected) return;
        setDialogState(() => _sortBy = sortBy);
        setState(() => _sortBy = sortBy);
      },
    );
  }

  void _showWindowDetails(OverlapWindow window, String userTimezone,
      String partnerTimezone) {
    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final dateFormat = DateFormat('EEEE, MMMM d, yyyy');
        final timeFormat = DateFormat('h:mm a');

        // Convert UTC start/end to user's timezone
        final userLocation = tz.getLocation(userTimezone);
        final userStart = tz.TZDateTime.from(window.startDateTime, userLocation);
        final userEnd = tz.TZDateTime.from(window.endDateTime, userLocation);

        // Convert UTC start/end to partner's timezone
        final partnerLocation = tz.getLocation(partnerTimezone);
        final partnerStart =
            tz.TZDateTime.from(window.startDateTime, partnerLocation);
        final partnerEnd =
            tz.TZDateTime.from(window.endDateTime, partnerLocation);

        return AlertDialog(
          title: const Text('Window Details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date
              Text(
                dateFormat.format(userStart),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Time ranges
              _buildDetailRow(
                'Your Time',
                '${timeFormat.format(userStart)} - ${timeFormat.format(userEnd)}',
                theme,
              ),
              const SizedBox(height: 8),
              _buildDetailRow(
                'Partner\'s Time',
                '${timeFormat.format(partnerStart)} - ${timeFormat.format(partnerEnd)}',
                theme,
              ),

              const Divider(height: 32),

              // Duration
              _buildDetailRow(
                'Duration',
                _formatDuration(window.durationMinutes),
                theme,
              ),
              const SizedBox(height: 8),

              // Score
              Text(
                'Score',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              _buildScoreRow('Match Score', window.score, theme),

              const SizedBox(height: 16),

              // Reasonable hours
              Row(
                children: [
                  Icon(
                    window.reasonableBoth ? Icons.check_circle : Icons.cancel,
                    size: 20,
                    color: window.reasonableBoth ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    window.reasonableBoth
                        ? 'Reasonable hours for both'
                        : 'Outside typical hours',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScoreRow(String label, double score, ThemeData theme) {
    final scoreDisplay = score.round();
    final color = _getScoreColor(score);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: (score / 60).clamp(0.0, 1.0),
                backgroundColor: color.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$scoreDisplay',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  void _clearFilters() {
    setState(() {
      _minDurationMinutes = null;
      _minScore = null;
    });
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

  Color _getScoreColor(double score) {
    if (score >= 40) return Colors.green;
    if (score >= 25) return Colors.lightGreen;
    if (score >= 15) return Colors.orange;
    return Colors.red;
  }
}
