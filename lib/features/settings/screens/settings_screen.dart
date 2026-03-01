import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/notification_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_section.dart';
import '../widgets/time_range_picker.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: const [
          _CalendarConnectionsSection(),
          _PrivacySection(),
          _NotificationsSection(),
          _SchedulingSection(),
          _AccountSection(),
          SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Calendar Connections ──────────────────────────────────────────────────────

class _CalendarConnectionsSection extends ConsumerWidget {
  const _CalendarConnectionsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesAsync = ref.watch(calendarSourcesProvider);

    return SettingsSection(
      title: 'Calendar Connections',
      children: [
        ...sourcesAsync.when(
          data: (sources) => sources.map((s) => _CalendarTile(source: s)).toList(),
          loading: () => [const _LoadingTile()],
          error: (_, _) => [const _ErrorTile('Could not load calendars')],
        ),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Connect a calendar'),
          onTap: () => _showConnectSheet(context),
        ),
      ],
    );
  }

  void _showConnectSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Google Calendar'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.apple),
              title: const Text('Apple Calendar'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Outlook'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarTile extends StatelessWidget {
  const _CalendarTile({required this.source});
  final CalendarSource source;

  @override
  Widget build(BuildContext context) {
    final icon = switch (source.type) {
      CalendarSourceType.googleCalendar => Icons.calendar_today,
      CalendarSourceType.appleCalendar => Icons.apple,
      CalendarSourceType.outlook => Icons.email_outlined,
    };

    return ListTile(
      leading: Icon(icon),
      title: Text(source.displayName ?? source.email),
      subtitle: Text(source.email),
      trailing: TextButton(
        child: const Text('Disconnect'),
        onPressed: () => _confirmDisconnect(context),
      ),
    );
  }

  void _confirmDisconnect(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect calendar?'),
        content: Text(
            'Remove ${source.displayName ?? source.email} from Couple Schedule?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }
}

// ── Privacy ───────────────────────────────────────────────────────────────────

class _PrivacySection extends ConsumerWidget {
  const _PrivacySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(coupleSettingsProvider);
    final showTitles = settingsAsync.valueOrNull?.showTitles ?? true;

    return SettingsSection(
      title: 'Privacy',
      children: [
        SwitchListTile(
          title: const Text('Show event titles'),
          subtitle: const Text(
            'When off your partner only sees you as "busy"',
          ),
          value: showTitles,
          onChanged: (v) =>
              ref.read(coupleSettingsNotifierProvider.notifier).setShowTitles(v),
        ),
      ],
    );
  }
}

// ── Notifications ─────────────────────────────────────────────────────────────

class _NotificationsSection extends ConsumerWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final windowAlerts = ref.watch(newWindowAlertsProvider);
    final digest = ref.watch(dailyDigestProvider);
    final quietStart = ref.watch(quietHoursStartProvider);
    final quietEnd = ref.watch(quietHoursEndProvider);

    return SettingsSection(
      title: 'Notifications',
      children: [
        SwitchListTile(
          title: const Text('New window alerts'),
          subtitle: const Text('Notify when a mutual free window opens up'),
          value: windowAlerts,
          onChanged: (v) =>
              ref.read(newWindowAlertsProvider.notifier).set(v),
        ),
        SwitchListTile(
          title: const Text('Daily digest'),
          subtitle: const Text("Morning summary of today's free windows"),
          value: digest,
          onChanged: (v) =>
              ref.read(dailyDigestProvider.notifier).set(v),
        ),
        const ListTile(
          title: Text('Quiet hours'),
          subtitle: Text('No notifications during this window'),
          isThreeLine: false,
        ),
        TimeRangePicker(
          start: quietStart,
          end: quietEnd,
          onStartChanged: (t) =>
              ref.read(quietHoursStartProvider.notifier).set(t),
          onEndChanged: (t) =>
              ref.read(quietHoursEndProvider.notifier).set(t),
        ),
      ],
    );
  }
}

// ── Scheduling ────────────────────────────────────────────────────────────────

class _SchedulingSection extends ConsumerWidget {
  const _SchedulingSection();

  static const _durations = [15, 30, 45, 60];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(coupleSettingsProvider);
    final current = settingsAsync.valueOrNull?.minSlotDurationMinutes ?? 30;

    return SettingsSection(
      title: 'Scheduling',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Minimum slot duration',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: _durations
                    .map(
                      (d) => ButtonSegment(
                        value: d,
                        label: Text('${d}m'),
                      ),
                    )
                    .toList(),
                selected: {current},
                onSelectionChanged: (set) => ref
                    .read(coupleSettingsNotifierProvider.notifier)
                    .setMinSlotDuration(set.first),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Account ───────────────────────────────────────────────────────────────────

class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsSection(
      title: 'Account',
      children: [
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Log out'),
          onTap: () => _confirmLogout(context),
        ),
        ListTile(
          leading: const Icon(Icons.link_off),
          title: const Text('Unlink partner'),
          onTap: () => _confirmUnlinkPartner(context),
        ),
        ListTile(
          leading: Icon(Icons.delete_forever,
              color: Theme.of(context).colorScheme.error),
          title: Text(
            'Delete account',
            style:
                TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          onTap: () => _confirmDeleteAccount(context),
        ),
      ],
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }

  void _confirmUnlinkPartner(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlink partner?'),
        content: const Text(
          'You and your partner will no longer share calendars. This cannot be undone without re-linking.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'All your data will be permanently removed. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => _secondDeleteConfirm(ctx),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _secondDeleteConfirm(BuildContext context) {
    Navigator.pop(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Are you absolutely sure?'),
        content: const Text(
          'Type DELETE to confirm permanent account deletion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _LoadingTile extends StatelessWidget {
  const _LoadingTile();

  @override
  Widget build(BuildContext context) =>
      const ListTile(title: LinearProgressIndicator());
}

class _ErrorTile extends StatelessWidget {
  const _ErrorTile(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.error_outline),
        title: Text(message),
      );
}
