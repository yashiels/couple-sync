import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/calendar_connection.dart';
import '../../shared/providers/auth_providers.dart';
import '../../shared/providers/pairing_providers.dart';
import '../calendar/providers/google_calendar_provider.dart';

/// Full settings screen with calendar connections, notifications, privacy,
/// scheduling, timezone, and account sections.
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
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
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
          _buildCalendarConnectionsSection(
            connections: connections,
            userId: user?.uid,
          ),
          const SizedBox(height: 16),

          // 2. Timezone
          _buildTimezoneSection(user?.timezone ?? 'UTC'),
          const SizedBox(height: 16),

          // 3. Account
          _buildAccountSection(context),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Section 1: Calendar Connections ────────────────────────────────────────

  Widget _buildCalendarConnectionsSection({
    required List<CalendarConnection> connections,
    required String? userId,
  }) {
    return _SettingsSection(
      icon: Icons.calendar_month_rounded,
      title: 'Calendar Connections',
      children: [
        // Connected account tiles
        for (int i = 0; i < connections.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: AppColors.divider),
          _GoogleAccountTile(
            connection: connections[i],
            onRemove: () async {
              if (userId == null) return;
              await ref
                  .read(googleCalendarConnectionsProvider.notifier)
                  .removeAccount(userId, connections[i].id);
            },
          ),
        ],
        if (connections.isNotEmpty)
          const Divider(height: 1, color: AppColors.divider),
        // Add account tile
        ListTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.inputFill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.add_rounded,
              size: 20,
              color: AppColors.lavenderDark,
            ),
          ),
          title: const Text(
            'Add Google Account',
            style: TextStyle(
              color: AppColors.lavenderDark,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: const Text(
            'Connect another Google Calendar',
            style: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12),
          ),
          onTap: () async {
            if (userId == null) return;
            await ref
                .read(googleCalendarConnectionsProvider.notifier)
                .connectAccount(userId);
          },
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ],
    );
  }

  // ── Section 2: Timezone ────────────────────────────────────────────────────

  Widget _buildTimezoneSection(String timezone) {
    return _SettingsSection(
      icon: Icons.language_rounded,
      title: 'Timezone',
      children: [
        ListTile(
          title: const Text(
            'Current timezone',
            style: TextStyle(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            timezone,
            style: const TextStyle(
              color: AppColors.lavenderDark,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          trailing: Chip(
            label: Text(
              DateTime.now().timeZoneName,
              style: const TextStyle(fontSize: 11),
            ),
            backgroundColor: AppColors.inputFill,
            side: BorderSide.none,
            padding: EdgeInsets.zero,
            labelPadding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ],
    );
  }

  // ── Section 3: Account ────────────────────────────────────────────────────

  Widget _buildAccountSection(BuildContext context) {
    final couple = ref.watch(currentCoupleProvider);

    return _SettingsSection(
      icon: Icons.person_rounded,
      title: 'Account',
      children: [
        ListTile(
          leading: const Icon(Icons.logout_rounded, color: AppColors.roseDark),
          title: const Text(
            'Sign out',
            style: TextStyle(
              color: AppColors.roseDark,
              fontWeight: FontWeight.w600,
            ),
          ),
          onTap: () => _confirmSignOut(context),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        if (couple != null) ...[
          const Divider(height: 1, color: AppColors.divider),
          ListTile(
            leading: const Icon(Icons.link_off_rounded, color: AppColors.error),
            title: const Text(
              'Unpair from partner',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () => _confirmUnpair(context),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ],
      ],
    );
  }

  // ── Confirmation dialogs ──────────────────────────────────────────────────

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to sign in again to access your shared calendar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.roseDark),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(authNotifierProvider.notifier).signOut();
    }
  }

  Future<void> _confirmUnpair(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unpair from partner?'),
        content: const Text(
          'This will remove the pairing and unlink your calendars. '
          'You can pair again later with a new invite code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final couple = ref.read(currentCoupleProvider);
      if (couple != null) {
        await ref.read(pairingServiceProvider).unpair(couple);
        ref.read(currentCoupleProvider.notifier).state = null;
      }
      if (context.mounted) {
        context.go('/pairing');
      }
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Private helper widgets
// ══════════════════════════════════════════════════════════════════════════════

/// A card-based section with a bold header row and child content tiles.
class _SettingsSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.lavenderDark),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.lavenderDark,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          color: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }
}

/// A tile showing a connected Google account with email, last sync, and remove.
class _GoogleAccountTile extends StatelessWidget {
  final CalendarConnection connection;
  final VoidCallback onRemove;

  const _GoogleAccountTile({
    required this.connection,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final syncText = connection.lastSync != null
        ? 'Last sync: ${DateFormat.yMMMd().add_jm().format(connection.lastSync!.toLocal())}'
        : 'Not synced yet';

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.g_mobiledata_rounded,
          size: 22,
          color: AppColors.onSurface,
        ),
      ),
      title: Text(
        connection.email,
        style: const TextStyle(
          color: AppColors.onSurface,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        syncText,
        style: const TextStyle(
          color: AppColors.onSurfaceMuted,
          fontSize: 12,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close_rounded, size: 20),
        color: AppColors.onSurfaceMuted,
        onPressed: onRemove,
        tooltip: 'Remove account',
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}

