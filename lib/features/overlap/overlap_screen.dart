import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/overlap_window.dart';
import '../../shared/providers/overlap_providers.dart';

const _demoCoupleId = 'demo_couple';

/// Displays the Firestore-computed free windows for the current couple,
/// sorted by overlap score with the best match shown as a hero card.
class OverlapScreen extends ConsumerWidget {
  const OverlapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlapAsync = ref.watch(overlapResultProvider(_demoCoupleId));
    final computedAt = ref.watch(overlapComputedAtProvider(_demoCoupleId));

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
      body: overlapAsync.when(
        data: (result) {
          if (result == null || result.windows.isEmpty) {
            return _EmptyState();
          }
          return _WindowList(windows: result.windows);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
              child: const Icon(Icons.favorite_rounded, size: 48, color: Colors.white),
            ),
            const SizedBox(height: 24),
            Text('No free windows yet', style: Theme.of(context).textTheme.headlineMedium),
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
}

class _WindowList extends StatelessWidget {
  final List<OverlapWindow> windows;
  const _WindowList({required this.windows});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: windows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _WindowCard(window: windows[i], isTop: i == 0),
    );
  }
}

class _WindowCard extends StatelessWidget {
  final OverlapWindow window;
  final bool isTop;
  const _WindowCard({required this.window, required this.isTop});

  static final _dateFmt = DateFormat('EEEE, d MMMM');
  static final _timeFmt = DateFormat('HH:mm');

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final start = window.startUtc.toLocal();
    final end = window.endUtc.toLocal();

    if (isTop) {
      // Hero card with gradient
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
                const Icon(Icons.favorite_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text('Best Match', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _dateFmt.format(start),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${_timeFmt.format(start)} – ${_timeFmt.format(end)}',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _Chip(label: _formatDuration(window.durationMinutes)),
                const SizedBox(width: 8),
                if (window.reasonableBoth) _Chip(label: 'Good hours for both'),
              ],
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.lavender.withAlpha(60),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.access_time_rounded, color: AppColors.lavenderDeep),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_dateFmt.format(start), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    '${_timeFmt.format(start)} – ${_timeFmt.format(end)}  ·  ${_formatDuration(window.durationMinutes)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (window.reasonableBoth)
              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(60),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }
}
