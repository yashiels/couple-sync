import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/couple_model.dart';
import '../../shared/models/overlap_window.dart';
import '../../shared/models/recurring_window.dart';
import '../../shared/providers/auth_providers.dart';
import '../../shared/providers/overlap_providers.dart';
import '../../shared/providers/pairing_providers.dart';
import '../../shared/providers/pattern_providers.dart';
import '../calendar/providers/google_calendar_provider.dart';
import 'widgets/timezone_clock.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final couple = ref.watch(currentCoupleProvider);

    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    final coupleId = couple?.coupleId;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Large title app bar
          SliverAppBar(
            pinned: true,
            expandedHeight: 96,
            backgroundColor: AppColors.background,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 14),
              title: Text('Home', style: AppTypography.largeTitle.copyWith(fontSize: 28)),
              expandedTitleScale: 1.0,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_rounded),
                onPressed: () => context.push('/settings'),
              ),
            ],
          ),

          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 8),

                // Timezone section
                _TimezoneSection(userTimezone: user.timezone),
                const SizedBox(height: 20),

                // Hero card
                if (coupleId != null)
                  _HeroWindowCard(coupleId: coupleId)
                else
                  _NoCoupleCard(),
                const SizedBox(height: 20),

                // Patterns
                if (coupleId != null) _PatternsSection(coupleId: coupleId),
                const SizedBox(height: 20),

                // Quick actions
                _QuickActionsRow(coupleId: coupleId),

                // Bottom padding for tab bar
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Timezone section ──────────────────────────────────────────────────────────

class _TimezoneSection extends ConsumerWidget {
  const _TimezoneSection({required this.userTimezone});
  final String userTimezone;

  String _cityFromTimezone(String tz) {
    final parts = tz.split('/');
    return parts.length > 1 ? parts.last.replaceAll('_', ' ') : tz;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userCity = _cityFromTimezone(userTimezone);
    final userOffset = DateTime.now().timeZoneOffset;
    final couple = ref.watch(currentCoupleProvider);
    final user = ref.watch(currentUserProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Time Zones', style: AppTypography.title3),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: TimezoneClock(
                  city: userCity,
                  utcOffset: userOffset,
                  isMe: true,
                  label: 'You',
                ),
              ),
              Container(
                width: 0.33,
                height: 48,
                color: AppColors.separator,
              ),
              Expanded(
                child: couple != null && user != null
                    ? _PartnerClock(couple: couple, currentUserUid: user.uid)
                    : _EmptyPartnerClock(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PartnerClock extends ConsumerWidget {
  const _PartnerClock({required this.couple, required this.currentUserUid});
  final CoupleModel couple;
  final String currentUserUid;

  String _cityFromTimezone(String tz) {
    final parts = tz.split('/');
    return parts.length > 1 ? parts.last.replaceAll('_', ' ') : tz;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnerUid = couple.partnerUid(currentUserUid);

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(partnerUid).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _EmptyPartnerClock();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final partnerTz = data['timezone'] as String? ?? 'UTC';
        final partnerCity = _cityFromTimezone(partnerTz);

        return TimezoneClock(
          city: partnerCity,
          utcOffset: DateTime.now().timeZoneOffset,
          isMe: false,
          label: data['displayName'] as String? ?? 'Partner',
        );
      },
    );
  }
}

class _EmptyPartnerClock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Partner',
            style: AppTypography.caption.copyWith(color: AppColors.partnerB),
          ),
          const SizedBox(height: 4),
          Text('Not paired yet', style: AppTypography.subhead),
          Text(
            'Pair to see their time',
            style: AppTypography.caption,
          ),
        ],
      ),
    );
  }
}

// ── Hero window card ──────────────────────────────────────────────────────────

class _HeroWindowCard extends ConsumerWidget {
  const _HeroWindowCard({required this.coupleId});
  final String coupleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topWindow = ref.watch(topOverlapWindowProvider(coupleId));

    if (topWindow == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(Icons.access_time_rounded,
                size: 40, color: AppColors.onSurfaceMuted),
            const SizedBox(height: 12),
            Text('No free windows found', style: AppTypography.headline),
            const SizedBox(height: 4),
            Text(
              'Connect a calendar and add blocks to find overlap.',
              style: AppTypography.footnote,
            ),
          ],
        ),
      );
    }

    return _OverlapHeroCard(window: topWindow);
  }
}

class _OverlapHeroCard extends StatelessWidget {
  const _OverlapHeroCard({required this.window});
  final OverlapWindow window;

  String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  String _formatTime(DateTime utc) {
    return DateFormat('h:mm a').format(utc.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final isHappening = window.startUtc.isBefore(DateTime.now().toUtc());
    final startStr = _formatTime(window.startUtc);
    final endStr = _formatTime(window.endUtc);
    final diff = window.startUtc.difference(DateTime.now().toUtc());
    final countdownStr = _formatCountdown(diff.isNegative ? Duration.zero : diff);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isHappening ? 'You\'re free now!' : 'Next free window',
                      style: AppTypography.caption.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isHappening ? 'Now' : 'in $countdownStr',
                      style: AppTypography.title2.copyWith(color: Colors.white),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _formatDuration(window.durationMinutes),
                    style: AppTypography.subhead.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 16, color: Colors.white70),
                  const SizedBox(width: 8),
                  Text(
                    '$startStr - $endStr',
                    style: AppTypography.subhead.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (window.reasonableBoth) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Good for both',
                        style: AppTypography.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (window.suggestedActivity != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 13, color: Colors.white70),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      window.suggestedActivity!,
                      style: AppTypography.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatCountdown(Duration d) {
    if (d.inDays > 0) {
      final h = d.inHours.remainder(24);
      return '${d.inDays}d ${h}h';
    }
    if (d.inHours > 0) {
      final m = d.inMinutes.remainder(60);
      return '${d.inHours}h ${m.toString().padLeft(2, '0')}m';
    }
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}

// ── No couple card ────────────────────────────────────────────────────────────

class _NoCoupleCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(Icons.favorite_border_rounded,
              size: 40, color: AppColors.rose.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text('Pair with your partner', style: AppTypography.headline),
          const SizedBox(height: 4),
          Text(
            'Use an invite code to pair and find free time together',
            textAlign: TextAlign.center,
            style: AppTypography.footnote,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/pairing'),
              icon: const Icon(Icons.link_rounded, size: 18),
              label: const Text('Pair Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Patterns section ──────────────────────────────────────────────────────────

class _PatternsSection extends ConsumerWidget {
  const _PatternsSection({required this.coupleId});
  final String coupleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patterns = ref.watch(suggestedPatternsProvider(coupleId));
    if (patterns.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Patterns', style: AppTypography.title3),
        const SizedBox(height: 12),
        ...patterns.map((p) => _PatternCard(pattern: p)),
      ],
    );
  }
}

class _PatternCard extends StatelessWidget {
  const _PatternCard({required this.pattern});
  final RecurringWindow pattern;

  Color _consistencyColor(String consistency) {
    switch (consistency.toLowerCase()) {
      case 'high':
        return AppColors.success;
      case 'moderate':
        return AppColors.warning;
      default:
        return AppColors.onSurfaceMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.groupedBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  pattern.dayOfWeek.substring(0, 3),
                  style: AppTypography.captionBold.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${pattern.dayOfWeek}  ${pattern.startTime} - ${pattern.endTime}',
                    style: AppTypography.subhead.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _consistencyColor(pattern.consistency)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          pattern.consistency,
                          style: AppTypography.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _consistencyColor(pattern.consistency),
                          ),
                        ),
                      ),
                      if (pattern.suggestedActivity != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            pattern.suggestedActivity!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quick actions row ─────────────────────────────────────────────────────────

class _QuickActionsRow extends ConsumerStatefulWidget {
  const _QuickActionsRow({required this.coupleId});
  final String? coupleId;

  @override
  ConsumerState<_QuickActionsRow> createState() => _QuickActionsRowState();
}

class _QuickActionsRowState extends ConsumerState<_QuickActionsRow> {
  bool _syncing = false;

  Future<void> _syncCalendars() async {
    if (_syncing) return;
    final user = ref.read(currentUserProvider);
    if (user == null || widget.coupleId == null) return;

    setState(() => _syncing = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Syncing calendars...')),
    );
    try {
      final service = ref.read(googleCalendarServiceProvider);
      await service.syncToFirestore(
        userId: user.uid,
        coupleId: widget.coupleId!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Calendars synced!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: AppTypography.title3),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _ActionButton(
                icon: Icons.add_rounded,
                label: 'Add Block',
                onTap: () => context.push('/blocks/add'),
              ),
              const SizedBox(width: 10),
              _ActionButton(
                icon: _syncing ? Icons.hourglass_top_rounded : Icons.sync_rounded,
                label: 'Sync',
                onTap: _syncing ? () {} : _syncCalendars,
              ),
              const SizedBox(width: 10),
              _ActionButton(
                icon: Icons.view_timeline_rounded,
                label: 'All Windows',
                onTap: () => context.go('/overlap'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.groupedBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
