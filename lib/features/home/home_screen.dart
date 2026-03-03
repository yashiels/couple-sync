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

/// The main home screen with timezone clocks, hero window card, patterns
/// section, and quick-action chips. All data is Firestore-backed via Riverpod.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final couple = ref.watch(currentCoupleProvider);

    // While user/couple data is loading, show a centered spinner.
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Couple Schedule')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final coupleId = couple?.coupleId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Couple Schedule'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            // ── Timezone clock section ──────────────────────────────────
            _TimezoneSection(userTimezone: user.timezone),

            const SizedBox(height: 20),

            // ── Hero card — next free window ────────────────────────────
            if (coupleId != null)
              _HeroWindowCard(coupleId: coupleId)
            else
              _NoCoupleCard(),

            const SizedBox(height: 20),

            // ── Patterns section ────────────────────────────────────────
            if (coupleId != null) _PatternsSection(coupleId: coupleId),

            const SizedBox(height: 20),

            // ── Quick actions row ───────────────────────────────────────
            _QuickActionsRow(coupleId: coupleId),

            const SizedBox(height: 24),
          ],
        ),
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
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Time zones',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TimezoneClock(
                city: userCity,
                utcOffset: userOffset,
                isMe: true,
                label: 'You',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: couple != null && user != null
                  ? _PartnerClock(
                      couple: couple,
                      currentUserUid: user.uid,
                    )
                  : _EmptyPartnerClock(),
            ),
          ],
        ),
      ],
    );
  }
}

class _PartnerClock extends ConsumerWidget {
  const _PartnerClock({
    required this.couple,
    required this.currentUserUid,
  });

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
          // TODO: resolve partner's actual UTC offset from IANA timezone
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.partnerB,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Partner',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5A9FE0),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Not paired yet',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.onSurfaceMuted,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pair to see their time',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.onSurfaceMuted,
            ),
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
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            Icon(Icons.access_time_rounded,
                size: 40, color: AppColors.onSurfaceMuted),
            const SizedBox(height: 12),
            Text(
              'No free windows found',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.onSurfaceMuted,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add more blocks so we can find overlap',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return _OverlapHeroCard(window: topWindow);
  }
}

/// Gradient hero card showing the next overlap window with time, duration,
/// and optional Gemini suggestion.
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
    final local = utc.toLocal();
    return DateFormat('h:mm a').format(local);
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
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.lavender.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isHappening ? 'You\'re free now!' : 'Next free window',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isHappening ? 'Now' : 'in $countdownStr',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _formatDuration(window.durationMinutes),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Time range
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded,
                      size: 16, color: Colors.white70),
                  const SizedBox(width: 8),
                  Text(
                    '$startStr - $endStr',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  if (window.reasonableBoth) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Good for both',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Gemini suggestion
            if (window.suggestedActivity != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      size: 13, color: Colors.white70),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      window.suggestedActivity!,
                      style: const TextStyle(
                        fontSize: 12,
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Icon(Icons.favorite_border_rounded,
              size: 40, color: AppColors.rose.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            'Pair with your partner',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Use an invite code to connect and find free time together',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => context.go('/pairing'),
            icon: const Icon(Icons.link_rounded, size: 18),
            label: const Text('Pair now'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.rose,
              foregroundColor: Colors.white,
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
        Text(
          'Patterns',
          style: Theme.of(context).textTheme.titleLarge,
        ),
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            // Day icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.lavenderLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  pattern.dayOfWeek.substring(0, 3),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.lavenderDark,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${pattern.dayOfWeek}  ${pattern.startTime} - ${pattern.endTime}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _consistencyColor(pattern.consistency)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          pattern.consistency,
                          style: TextStyle(
                            fontSize: 10,
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
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.onSurfaceMuted,
                            ),
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

class _QuickActionsRow extends ConsumerWidget {
  const _QuickActionsRow({required this.coupleId});
  final String? coupleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick actions',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _ActionChip(
              icon: Icons.add_rounded,
              label: 'Add Block',
              onTap: () => context.go('/blocks/add'),
            ),
            const SizedBox(width: 10),
            _ActionChip(
              icon: Icons.sync_rounded,
              label: 'Sync Calendars',
              onTap: () async {
                final user = ref.read(currentUserProvider);
                if (user == null || coupleId == null) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Syncing calendars...')),
                );
                try {
                  final service = ref.read(googleCalendarServiceProvider);
                  await service.syncToFirestore(
                    userId: user.uid,
                    coupleId: coupleId!,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Calendars synced!')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Sync failed: $e')),
                    );
                  }
                }
              },
            ),
            const SizedBox(width: 10),
            _ActionChip(
              icon: Icons.view_timeline_rounded,
              label: 'All Windows',
              onTap: () => context.go('/overlap'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.roseLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: AppColors.roseDark),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
