import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/mock_data.dart';
import '../widgets/daily_timeline.dart';
import '../widgets/next_window_card.dart';
import '../widgets/timezone_clock.dart';

/// Rich home screen showing dual timezone clocks, the next free window card,
/// and today's horizontal timeline of both partners' blocks.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  // UTC offsets for demo (New York = -5, London = 0)
  static const Duration _myOffset = Duration(hours: -5);
  static const Duration _partnerOffset = Duration(hours: 0);

  @override
  Widget build(BuildContext context) {
    final windows = MockData.upcomingWindows();
    final blocks = MockData.todayBlocks();
    final nextWindow = windows.isNotEmpty ? windows.first : null;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _Header(),
                ),
              ),
              // Dual timezone clocks
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TimezoneClock(
                          city: MockData.myCity,
                          utcOffset: _myOffset,
                          isMe: true,
                          label: 'You',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TimezoneClock(
                          city: MockData.partnerCity,
                          utcOffset: _partnerOffset,
                          isMe: false,
                          label: 'Alex',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Next free window hero card
              if (nextWindow != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: NextWindowCard(
                      window: nextWindow,
                      myUtcOffset: _myOffset,
                      partnerUtcOffset: _partnerOffset,
                    ),
                  ),
                ),
              // Today's timeline
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: DailyTimeline(
                    blocks: blocks,
                    myUtcOffset: _myOffset,
                    myCity: MockData.myCity,
                  ),
                ),
              ),
              // Quick action buttons
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: _QuickActions(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Good morning',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.onSurfaceMuted,
                fontWeight: FontWeight.w400,
              ),
            ),
            const Text(
              'Jordan & Alex',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
        Row(
          children: [
            _HeaderButton(
              icon: Icons.notifications_outlined,
              onTap: () {},
            ),
            const SizedBox(width: 8),
            _HeaderButton(
              icon: Icons.settings_outlined,
              onTap: () {},
            ),
          ],
        ),
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.lavender.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: AppColors.onSurfaceMuted),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick actions',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceMuted,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.add_rounded,
                label: 'Add block',
                gradient: const LinearGradient(
                  colors: [Color(0xFFF4A0B5), Color(0xFFE07898)],
                ),
                onTap: () {},
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                icon: Icons.calendar_today_rounded,
                label: 'Calendar',
                gradient: const LinearGradient(
                  colors: [Color(0xFFCBA8EA), Color(0xFFAA7DD0)],
                ),
                onTap: () {},
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                icon: Icons.access_time_rounded,
                label: 'Free windows',
                gradient: const LinearGradient(
                  colors: [Color(0xFF9BC4F5), Color(0xFF5A9FE0)],
                ),
                onTap: () {},
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Gradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 5),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
