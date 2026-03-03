import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/calendar_connection.dart';
import '../../shared/providers/auth_providers.dart';
import '../calendar/providers/google_calendar_provider.dart';

/// Full settings screen with calendar connections, notifications, privacy,
/// scheduling, timezone, and account sections.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Local notification toggle state (not persisted yet).
  bool _newWindowAlerts = true;
  bool _dailyDigest = false;
  final bool _quietHoursEnabled = false;

  // Local privacy toggle state.
  bool _showEventTitles = true;

  // Local scheduling state.
  int _minSlotMinutes = 30;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final connections = ref.watch(googleCalendarConnectionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // 1. Calendar Connections
          _buildCalendarConnectionsSection(
            connections: connections,
            userId: user?.uid,
          ),
          const SizedBox(height: 16),

          // 2. Notifications
          _buildNotificationsSection(),
          const SizedBox(height: 16),

          // 3. Privacy
          _buildPrivacySection(),
          const SizedBox(height: 16),

          // 4. Scheduling
          _buildSchedulingSection(),
          const SizedBox(height: 16),

          // 5. Timezone
          _buildTimezoneSection(user?.timezone ?? 'UTC'),
          const SizedBox(height: 16),

          // 6. Account
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

  // ── Section 2: Notifications ──────────────────────────────────────────────

  Widget _buildNotificationsSection() {
    return _SettingsSection(
      icon: Icons.notifications_rounded,
      title: 'Notifications',
      children: [
        SwitchListTile(
          title: const Text(
            'New window alerts',
            style: TextStyle(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: const Text(
            'Get notified when a new overlap window opens',
            style: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12),
          ),
          value: _newWindowAlerts,
          onChanged: (v) => setState(() => _newWindowAlerts = v),
          activeThumbColor: AppColors.rose,
          activeTrackColor: AppColors.roseLight,
          inactiveTrackColor: AppColors.inputFill,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        const Divider(height: 1, color: AppColors.divider),
        SwitchListTile(
          title: const Text(
            'Daily digest',
            style: TextStyle(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: const Text(
            'Receive a summary of upcoming windows each morning',
            style: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12),
          ),
          value: _dailyDigest,
          onChanged: (v) => setState(() => _dailyDigest = v),
          activeThumbColor: AppColors.rose,
          activeTrackColor: AppColors.roseLight,
          inactiveTrackColor: AppColors.inputFill,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        const Divider(height: 1, color: AppColors.divider),
        SwitchListTile(
          title: const Text(
            'Quiet hours',
            style: TextStyle(
              color: AppColors.onSurfaceMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: const Text(
            'Coming soon',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
          value: _quietHoursEnabled,
          onChanged: null,
          activeThumbColor: AppColors.rose,
          inactiveTrackColor: AppColors.inputFill,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ],
    );
  }

  // ── Section 3: Privacy ────────────────────────────────────────────────────

  Widget _buildPrivacySection() {
    return _SettingsSection(
      icon: Icons.lock_rounded,
      title: 'Privacy',
      children: [
        SwitchListTile(
          title: const Text(
            'Show event titles to partner',
            style: TextStyle(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: const Text(
            'When off, your partner only sees busy/free status',
            style: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12),
          ),
          value: _showEventTitles,
          onChanged: (v) => setState(() => _showEventTitles = v),
          activeThumbColor: AppColors.rose,
          activeTrackColor: AppColors.roseLight,
          inactiveTrackColor: AppColors.inputFill,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ],
    );
  }

  // ── Section 4: Scheduling ─────────────────────────────────────────────────

  Widget _buildSchedulingSection() {
    return _SettingsSection(
      icon: Icons.tune_rounded,
      title: 'Scheduling',
      children: [
        ListTile(
          title: const Text(
            'Minimum slot duration',
            style: TextStyle(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: const Text(
            'Ignore overlap windows shorter than this',
            style: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12),
          ),
          trailing: _DurationChipRow(
            selectedMinutes: _minSlotMinutes,
            onChanged: (v) => setState(() => _minSlotMinutes = v),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        const Divider(height: 1, color: AppColors.divider),
        ListTile(
          title: const Text(
            'Default couple calendar',
            style: TextStyle(
              color: AppColors.onSurfaceMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: const Text(
            'Coming soon',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textHint,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ],
    );
  }

  // ── Section 5: Timezone ───────────────────────────────────────────────────

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
          trailing: const Chip(
            label: Text('Auto', style: TextStyle(fontSize: 11)),
            backgroundColor: AppColors.inputFill,
            side: BorderSide.none,
            padding: EdgeInsets.zero,
            labelPadding: EdgeInsets.symmetric(horizontal: 8),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ],
    );
  }

  // ── Section 6: Account ────────────────────────────────────────────────────

  Widget _buildAccountSection(BuildContext context) {
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
          'This will remove the connection with your partner. '
          'You can pair again later with a new code.',
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
      // TODO: Implement unpair logic via a dedicated service.
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

/// Compact chip row for selecting a minimum slot duration.
class _DurationChipRow extends StatelessWidget {
  final int selectedMinutes;
  final ValueChanged<int> onChanged;

  const _DurationChipRow({
    required this.selectedMinutes,
    required this.onChanged,
  });

  static const _options = [15, 30, 60];

  String _label(int minutes) {
    if (minutes >= 60) return '${minutes ~/ 60}hr';
    return '${minutes}min';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _options.map((mins) {
        final selected = mins == selectedMinutes;
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: ChoiceChip(
            label: Text(
              _label(mins),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.onSurfaceMuted,
              ),
            ),
            selected: selected,
            onSelected: (_) => onChanged(mins),
            selectedColor: AppColors.lavenderDark,
            backgroundColor: AppColors.inputFill,
            side: BorderSide.none,
            padding: EdgeInsets.zero,
            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
            visualDensity: VisualDensity.compact,
          ),
        );
      }).toList(),
    );
  }
}
