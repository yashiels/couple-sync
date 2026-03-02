import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/apple_calendar_provider.dart';
import '../providers/google_calendar_provider.dart';

/// Screen that lists available calendar sources and lets the user
/// connect or disconnect each one.
class CalendarConnectScreen extends ConsumerWidget {
  const CalendarConnectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Calendars'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          Text(
            'Link your calendars to automatically surface your busy times.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.onSurfaceMuted),
          ),
          const SizedBox(height: 24),
          _GoogleCalendarTile(),
          const SizedBox(height: 12),
          if (Platform.isIOS) ...[
            _AppleCalendarTile(),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

// ── Google Calendar tile ──────────────────────────────────────────────────────

class _GoogleCalendarTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(googleCalendarConnectionProvider);
    final lastSync = ref.watch(googleCalendarLastSyncProvider);
    final syncState = ref.watch(googleCalendarSyncProvider);
    final connectionNotifier =
        ref.read(googleCalendarConnectionProvider.notifier);

    return _CalendarSourceCard(
      icon: _GoogleIcon(),
      name: 'Google Calendar',
      subtitle: connected
          ? (lastSync != null
              ? 'Last synced ${_formatRelative(lastSync)}'
              : 'Connected — not yet synced')
          : 'Connect to sync your busy times',
      connected: connected,
      isSyncing: syncState.isLoading,
      errorMessage: syncState.hasError ? syncState.error.toString() : null,
      onConnect: () async {
        final success = await connectionNotifier.connect();
        if (!success && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Google sign-in cancelled')),
          );
        }
      },
      onDisconnect: () async {
        final confirm = await _showDisconnectDialog(context, 'Google Calendar');
        if (confirm == true) {
          await connectionNotifier.disconnect();
        }
      },
    );
  }
}

// ── Apple Calendar tile ───────────────────────────────────────────────────────

class _AppleCalendarTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissionAsync = ref.watch(appleCalendarPermissionProvider);
    final lastSync = ref.watch(appleCalendarLastSyncProvider);
    final syncState = ref.watch(appleCalendarSyncProvider);
    final permissionNotifier =
        ref.read(appleCalendarPermissionProvider.notifier);

    final granted = permissionAsync.valueOrNull ?? false;

    return _CalendarSourceCard(
      icon: const Icon(Icons.calendar_month_rounded,
          size: 28, color: Color(0xFF555555)),
      name: 'Apple Calendar',
      subtitle: granted
          ? (lastSync != null
              ? 'Last synced ${_formatRelative(lastSync)}'
              : 'Allowed — not yet synced')
          : 'Allow access to read your events',
      connected: granted,
      isSyncing: syncState.isLoading,
      errorMessage: syncState.hasError ? syncState.error.toString() : null,
      onConnect: () async {
        final success = await permissionNotifier.request();
        if (!success && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Calendar access denied. Enable it in Settings > Privacy.'),
            ),
          );
        }
      },
      onDisconnect: null, // iOS permission can only be revoked in Settings.
      disconnectHint: 'Revoke access in Settings > Privacy > Calendars.',
    );
  }
}

// ── Shared card widget ────────────────────────────────────────────────────────

class _CalendarSourceCard extends StatelessWidget {
  const _CalendarSourceCard({
    required this.icon,
    required this.name,
    required this.subtitle,
    required this.connected,
    required this.isSyncing,
    this.errorMessage,
    this.onConnect,
    this.onDisconnect,
    this.disconnectHint,
  });

  final Widget icon;
  final String name;
  final String subtitle;
  final bool connected;
  final bool isSyncing;
  final String? errorMessage;
  final VoidCallback? onConnect;
  final VoidCallback? onDisconnect;
  final String? disconnectHint;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: connected ? AppColors.lavenderDark : AppColors.divider,
          width: connected ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 32, height: 32, child: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (isSyncing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                _ConnectButton(
                  connected: connected,
                  onConnect: onConnect,
                  onDisconnect: onDisconnect,
                ),
            ],
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      size: 16, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(
                          color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (disconnectHint != null && connected) ...[
            const SizedBox(height: 8),
            Text(disconnectHint!,
                style: Theme.of(context).textTheme.labelSmall),
          ],
        ],
      ),
    );
  }
}

class _ConnectButton extends StatelessWidget {
  const _ConnectButton({
    required this.connected,
    this.onConnect,
    this.onDisconnect,
  });

  final bool connected;
  final VoidCallback? onConnect;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    if (connected) {
      return TextButton(
        onPressed: onDisconnect,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.onSurfaceMuted,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppColors.divider),
          ),
        ),
        child: const Text('Disconnect', style: TextStyle(fontSize: 13)),
      );
    }
    return FilledButton(
      onPressed: onConnect,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.lavender,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: const Text('Connect'),
    );
  }
}

// ── Google logo (SVG-like painted widget) ─────────────────────────────────────

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(28, 28),
      painter: _GoogleLogoPainter(),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Background circle
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = Colors.white,
    );

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'G',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF4285F4),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_GoogleLogoPainter old) => false;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Returns a human-readable relative time string for [dt] (e.g. `"5m ago"`).
String _formatRelative(DateTime dt) {
  final diff = DateTime.now().toUtc().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Shows a confirmation dialog before disconnecting [calendarName].
Future<bool?> _showDisconnectDialog(
    BuildContext context, String calendarName) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Disconnect $calendarName?'),
      content: const Text(
        'Your synced busy blocks will be removed. You can reconnect at any time.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade400,
          ),
          child: const Text('Disconnect'),
        ),
      ],
    ),
  );
}
