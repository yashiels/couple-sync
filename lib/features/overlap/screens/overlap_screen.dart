import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/models/overlap_result.dart';
import '../widgets/window_card_widget.dart';

/// Overlap screen displaying mutual free time windows with filtering and sorting.
/// 
/// TODO: Replace mock data with Firestore queries when Cloud Functions are implemented:
/// - Query: Firestore.instance.collection('overlaps').doc(coupleId).collection('windows').doc('latest')
/// - Listen to real-time updates with snapshots()
/// - Filter/sort on client side after fetching
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
  
  // TODO: Get from user provider when implemented
  final String _userTimezone = 'Africa/Johannesburg';
  final String _partnerTimezone = 'America/New_York';
  
  // TODO: Replace with Firestore provider when Cloud Functions implemented
  List<OverlapWindow> get _mockWindows => _generateMockWindows();
  
  List<OverlapWindow> _generateMockWindows() {
    // Generate mock overlap windows for testing
    final now = DateTime.now();
    final windows = <OverlapWindow>[];
    
    for (int i = 0; i < 15; i++) {
      final startHour = 9 + (i * 24); // Daily windows at 9 AM
      final start = now.add(Duration(hours: startHour, minutes: 0));
      final duration = [30, 60, 90, 120, 180][i % 5]; // Varying durations
      
      windows.add(OverlapWindow(
        startUtc: start.toUtc().millisecondsSinceEpoch,
        endUtc: start.add(Duration(minutes: duration)).toUtc().millisecondsSinceEpoch,
        durationMinutes: duration,
        score: [0.3, 0.5, 0.7, 0.8, 0.9, 1.0][i % 6],
        reasonableBoth: i % 2 == 0,
      ));
    }
    
    return windows;
  }
  
  List<OverlapWindow> get _filteredAndSortedWindows {
    var windows = _mockWindows;
    
    // Apply filters
    if (_minDurationMinutes != null) {
      windows = windows.where((w) => w.durationMinutes >= _minDurationMinutes!).toList();
    }
    
    if (_minScore != null) {
      windows = windows.where((w) => w.score >= _minScore!).toList();
    }
    
    // Apply sorting
    switch (_sortBy) {
      case 'date':
        windows.sort((a, b) => a.startUtc.compareTo(b.startUtc));
        break;
      case 'duration':
        windows.sort((a, b) => b.durationMinutes.compareTo(a.durationMinutes));
        break;
      case 'score':
        windows.sort((a, b) => b.score.compareTo(a.score));
        break;
    }
    
    // Limit to 10 windows (acceptance criteria says "up to 20" but story says "up to 10")
    // Using 10 as specified in the task instructions
    return windows.take(10).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final windows = _filteredAndSortedWindows;
    
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
      body: windows.isEmpty
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
                          userTimezone: _userTimezone,
                          partnerTimezone: _partnerTimezone,
                          onTap: () => _showWindowDetails(windows[index]),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
  
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
              'Try adjusting your blocks.',
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
                    'Min ${(_minScore! * 100).round()}% score',
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
                    _buildScoreChoice(0.4, '40%', setDialogState),
                    _buildScoreChoice(0.6, '60%', setDialogState),
                    _buildScoreChoice(0.8, '80%', setDialogState),
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
  
  Widget _buildDurationChoice(int? minutes, String label, StateSetter setDialogState) {
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
  
  Widget _buildScoreChoice(double? score, String label, StateSetter setDialogState) {
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
  
  Widget _buildSortChoice(String sortBy, String label, StateSetter setDialogState) {
    final isSelected = _sortBy == sortBy;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setDialogState(() => _sortBy = selected ? sortBy : _sortBy);
        setState(() => _sortBy = selected ? sortBy : _sortBy);
      },
    );
  }
  
  void _showWindowDetails(OverlapWindow window) {
    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final dateFormat = DateFormat('EEEE, MMMM d, yyyy');
        final timeFormat = DateFormat('h:mm a');
        
        final userStart = window.startDateTime.toLocal();
        final userEnd = window.endDateTime.toLocal();
        
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
                // TODO: Calculate actual partner time using TZDateTime
                '${timeFormat.format(userStart)} - ${timeFormat.format(userEnd)}',
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
              
              // Score breakdown
              Text(
                'Score Breakdown',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              
              _buildScoreRow('Overall Score', window.score, theme),
              const SizedBox(height: 8),
              _buildScoreRow('Duration Score', window.score * 0.8, theme),
              const SizedBox(height: 8),
              _buildScoreRow('Timing Score', window.score * 0.9, theme),
              
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
    final scorePercent = (score * 100).round();
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
                value: score,
                backgroundColor: color.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$scorePercent%',
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
    if (score >= 0.8) return Colors.green;
    if (score >= 0.6) return Colors.lightGreen;
    if (score >= 0.4) return Colors.orange;
    return Colors.red;
  }
}
