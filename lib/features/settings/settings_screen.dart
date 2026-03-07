import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/calendar_connection.dart';
import '../../shared/providers/auth_providers.dart';
import '../../shared/providers/pairing_providers.dart';
import '../calendar/providers/google_calendar_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final connections = ref.watch(googleCalendarConnectionsProvider);

    return Scaffold(
      backgroundColor: AppColors.groupedBackground,
      appBar: AppBar(
        backgroundColor: AppColors.groupedBackground,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // 1. Calendar Connections
          _SectionHeader(title: 'CALENDAR CONNECTIONS'),
          _GroupedCard(
            children: [
              for (int i = 0; i < connections.length; i++) ...[
                if (i > 0) const _Separator(),
                _GoogleAccountRow(
                  connection: connections[i],
                  onRemove: () async {
                    if (user?.uid == null) return;
                    await ref
                        .read(googleCalendarConnectionsProvider.notifier)
                        .removeAccount(user!.uid, connections[i].id);
                  },
                ),
              ],
              if (connections.isNotEmpty) const _Separator(),
              _TapRow(
                leading: const Icon(Icons.add, size: 20, color: AppColors.primary),
                label: 'Add Google Account',
                labelColor: AppColors.primary,
                onTap: () async {
                  if (user?.uid == null) return;
                  await ref
                      .read(googleCalendarConnectionsProvider.notifier)
                      .connectAccount(user!.uid);
                },
              ),
            ],
          ),

          const SizedBox(height: 28),

          // 2. Timezone
          _SectionHeader(title: 'TIMEZONE'),
          _GroupedCard(
            children: [
              _ValueRow(
                label: 'Current timezone',
                value: user?.timezone ?? 'UTC',
              ),
            ],
          ),

          const SizedBox(height: 28),

          // 3. Account
          _SectionHeader(title: 'ACCOUNT'),
          _GroupedCard(
            children: [
              _TapRow(
                label: 'Sign Out',
                labelColor: AppColors.destructive,
                onTap: () => _confirmSignOut(context),
              ),
              if (ref.watch(currentCoupleProvider) != null) ...[
                const _Separator(),
                _TapRow(
                  label: 'Unpair from Partner',
                  labelColor: AppColors.destructive,
                  onTap: () => _confirmUnpair(context),
                ),
              ],
            ],
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Sign Out?'),
        content: const Text(
          'You will need to sign in again to access your shared calendar.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(authNotifierProvider.notifier).signOut();
    }
  }

  Future<void> _confirmUnpair(BuildContext context) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Unpair from Partner?'),
        content: const Text(
          'This will remove the pairing and unlink your calendars. '
          'You can pair again later with a new invite code.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final couple = ref.read(currentCoupleProvider);
      final pairingService = ref.read(pairingServiceProvider);
      if (couple != null) {
        await pairingService.unpair(couple);
        if (!mounted) return;
        ref.read(currentCoupleProvider.notifier).state = null;
      }
      if (context.mounted) {
        context.go('/pairing');
      }
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// iOS Grouped List Helpers
// ══════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 6),
      child: Text(
        title,
        style: AppTypography.footnote.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _GroupedCard extends StatelessWidget {
  final List<Widget> children;
  const _GroupedCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 16),
      child: Divider(height: 0.33, thickness: 0.33, color: AppColors.separator),
    );
  }
}

class _TapRow extends StatelessWidget {
  final String label;
  final Color? labelColor;
  final Widget? leading;
  final VoidCallback onTap;

  const _TapRow({
    required this.label,
    required this.onTap,
    this.labelColor,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                label,
                style: AppTypography.body.copyWith(
                  color: labelColor ?? AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  final String label;
  final String value;

  const _ValueRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: AppTypography.body),
          ),
          Text(
            value,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _GoogleAccountRow extends StatelessWidget {
  final CalendarConnection connection;
  final VoidCallback onRemove;

  const _GoogleAccountRow({
    required this.connection,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final syncText = connection.lastSync != null
        ? 'Synced ${DateFormat.yMMMd().add_jm().format(connection.lastSync!.toLocal())}'
        : 'Not synced yet';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connection.email,
                  style: AppTypography.body,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  syncText,
                  style: AppTypography.footnote,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
