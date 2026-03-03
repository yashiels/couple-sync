import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/overlap_window.dart';
import '../../shared/models/scheduling_request.dart';
import '../../shared/providers/auth_providers.dart';
import '../../shared/providers/overlap_providers.dart';
import '../../shared/providers/pairing_providers.dart';

/// Duration filter options for the free-windows list.
enum _DurationFilter {
  any('Any'),
  thirtyMin('30 min'),
  oneHour('1 hr'),
  twoHours('2 hr');

  const _DurationFilter(this.label);
  final String label;

  /// Minimum duration in minutes that this filter requires.
  int get minMinutes {
    switch (this) {
      case _DurationFilter.any:
        return 0;
      case _DurationFilter.thirtyMin:
        return 30;
      case _DurationFilter.oneHour:
        return 60;
      case _DurationFilter.twoHours:
        return 120;
    }
  }
}

/// Displays the Firestore-computed free windows for the current couple,
/// sorted by overlap score with duration filtering, Gemini suggestions,
/// and Schedule Call functionality.
class OverlapScreen extends ConsumerStatefulWidget {
  const OverlapScreen({super.key});

  @override
  ConsumerState<OverlapScreen> createState() => _OverlapScreenState();
}

class _OverlapScreenState extends ConsumerState<OverlapScreen> {
  _DurationFilter _selectedFilter = _DurationFilter.any;

  static final _dateFmt = DateFormat('EEEE, d MMMM');
  static final _timeFmt = DateFormat('HH:mm');

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final couple = ref.watch(currentCoupleProvider);

    if (couple == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Free Windows')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Pair with your partner first to see shared free windows.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final coupleId = couple.coupleId;
    final overlapAsync = ref.watch(overlapResultProvider(coupleId));
    final computedAt = ref.watch(overlapComputedAtProvider(coupleId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Free Windows'),
        actions: [
          if (computedAt != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  'Updated ${_relativeTime(computedAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Duration filter chip row
          _buildFilterRow(context),
          const Divider(height: 1),
          // Window list
          Expanded(
            child: overlapAsync.when(
              data: (result) {
                if (result == null || result.windows.isEmpty) {
                  return _buildEmptyState(context);
                }
                final filtered = result.windows
                    .where((w) =>
                        w.durationMinutes >= _selectedFilter.minMinutes)
                    .toList();
                if (filtered.isEmpty) {
                  return _buildNoMatchState(context);
                }
                return _buildWindowList(context, filtered, coupleId);
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the duration filter chip row at the top of the screen.
  Widget _buildFilterRow(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: _DurationFilter.values.map((filter) {
          final selected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(filter.label),
              selected: selected,
              onSelected: (_) => setState(() => _selectedFilter = filter),
              selectedColor: AppColors.lavender,
              labelStyle: TextStyle(
                color: selected ? Colors.white : AppColors.onSurface,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              backgroundColor: AppColors.surfaceElevated,
              side: BorderSide(
                color: selected
                    ? AppColors.lavender
                    : AppColors.divider,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Empty state shown when there are no overlap windows at all.
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                gradient: AppColors.heroGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite_rounded,
                  size: 48, color: Colors.white),
            ),
            const SizedBox(height: 24),
            Text('No free windows yet',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 10),
            Text(
              'Add your schedules and we\'ll find moments when you\'re both free.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  /// State shown when the filter excludes all available windows.
  Widget _buildNoMatchState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.filter_list_off_rounded,
                size: 48, color: AppColors.onSurfaceMuted),
            const SizedBox(height: 16),
            Text('No windows match this filter',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 10),
            Text(
              'Try a shorter minimum duration to see more results.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the scrollable list of window cards.
  Widget _buildWindowList(
    BuildContext context,
    List<OverlapWindow> windows,
    String coupleId,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: windows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        return _buildWindowCard(context, windows[i], coupleId, isTop: i == 0);
      },
    );
  }

  /// Builds a single window card with time range, duration badge,
  /// Gemini suggestion chip, and Schedule Call button.
  Widget _buildWindowCard(
    BuildContext context,
    OverlapWindow window,
    String coupleId, {
    required bool isTop,
  }) {
    final start = window.startUtc.toLocal();
    final end = window.endUtc.toLocal();

    if (isTop) {
      return _buildHeroCard(context, window, coupleId, start, end);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.lavender.withAlpha(60),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.access_time_rounded,
                      color: AppColors.lavenderDeep),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_dateFmt.format(start),
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        '${_timeFmt.format(start)} – ${_timeFmt.format(end)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                // Duration badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.lavenderLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _formatDuration(window.durationMinutes),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.lavenderDark,
                    ),
                  ),
                ),
              ],
            ),
            // Suggested activity chip
            if (window.suggestedActivity != null) ...[
              const SizedBox(height: 12),
              _buildSuggestionChip(context, window.suggestedActivity!),
            ],
            // Schedule Call button
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    _showScheduleSheet(context, window, coupleId),
                icon: const Icon(Icons.videocam_rounded, size: 18),
                label: const Text('Schedule Call'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.lavenderDark,
                  side: const BorderSide(color: AppColors.lavender),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hero card for the top-ranked window with gradient background.
  Widget _buildHeroCard(
    BuildContext context,
    OverlapWindow window,
    String coupleId,
    DateTime start,
    DateTime end,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text('Best Match',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _dateFmt.format(start),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${_timeFmt.format(start)} – ${_timeFmt.format(end)}',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildHeroChip(_formatDuration(window.durationMinutes)),
              const SizedBox(width: 8),
              if (window.reasonableBoth)
                _buildHeroChip('Good hours for both'),
            ],
          ),
          // Gemini suggestion chip on hero card
          if (window.suggestedActivity != null) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(40),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      window.suggestedActivity!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Schedule Call button on hero card
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () =>
                  _showScheduleSheet(context, window, coupleId),
              icon: const Icon(Icons.videocam_rounded, size: 18),
              label: const Text('Schedule Call'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.lavenderDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Small chip used on the hero card with semi-transparent white background.
  Widget _buildHeroChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(60),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// Gemini-suggested activity chip with sparkle icon.
  Widget _buildSuggestionChip(BuildContext context, String activity) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.lavenderLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_rounded,
              size: 14, color: AppColors.lavenderDark),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              activity,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.lavenderDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows the Schedule Call confirmation bottom sheet.
  void _showScheduleSheet(
    BuildContext context,
    OverlapWindow window,
    String coupleId,
  ) {
    final start = window.startUtc.toLocal();
    final end = window.endUtc.toLocal();
    final titleController = TextEditingController(
      text: window.suggestedActivity ?? 'Couple Call',
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Schedule Call',
                style: Theme.of(sheetContext).textTheme.headlineMedium,
              ),
              const SizedBox(height: 20),
              // Window time info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.lavenderLight.withAlpha(100),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        color: AppColors.lavenderDark, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _dateFmt.format(start),
                            style: Theme.of(sheetContext)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_timeFmt.format(start)} – ${_timeFmt.format(end)}  (${_formatDuration(window.durationMinutes)})',
                            style:
                                Theme.of(sheetContext).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Editable title field
              Text('Event title',
                  style: Theme.of(sheetContext).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  hintText: 'Enter event title',
                  filled: true,
                  fillColor: AppColors.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 24),
              // Create Google Meet Event button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(sheetContext).pop();
                    await _createSchedulingRequest(
                      coupleId: coupleId,
                      window: window,
                      title: titleController.text.trim().isEmpty
                          ? 'Couple Call'
                          : titleController.text.trim(),
                    );
                  },
                  icon: const Icon(Icons.videocam_rounded, size: 20),
                  label: const Text('Create Google Meet Event'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.lavenderDark,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Writes a [SchedulingRequest] document to Firestore and shows a
  /// success snackbar. Full Meet event creation requires OAuth, so for
  /// now we only persist the request.
  Future<void> _createSchedulingRequest({
    required String coupleId,
    required OverlapWindow window,
    required String title,
  }) async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be signed in to schedule.')),
        );
      }
      return;
    }

    try {
      final docRef = FirebaseFirestore.instance
          .collection('scheduling_requests')
          .doc();

      final request = SchedulingRequest(
        id: docRef.id,
        coupleId: coupleId,
        requestedByUid: user.uid,
        windowStartUtc: window.startUtc,
        windowEndUtc: window.endUtc,
        title: title,
        status: 'pending',
        createdAt: DateTime.now().toUtc(),
      );

      await docRef.set(request.toFirestore());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Call scheduled! Your partner will be notified.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to schedule: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
