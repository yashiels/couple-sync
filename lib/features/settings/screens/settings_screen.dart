import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/couple_model.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../services/calendar_service.dart';
import '../../../services/providers/auth_state_provider.dart';
import '../../../services/providers/calendar_provider.dart';
import '../../../services/providers/couple_providers.dart';
import '../../../services/providers/sync_provider.dart';
import '../widgets/settings_section_widget.dart';

/// Provider for notification settings (local flag, doesn't affect FCM registration).
/// Persisted to flutter_secure_storage so the toggle survives restarts.
final notificationSettingsProvider =
    StateNotifierProvider<NotificationSettingsNotifier, bool>((ref) {
      return NotificationSettingsNotifier();
    });

class NotificationSettingsNotifier extends StateNotifier<bool> {
  static const _key = 'notif_enabled';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  NotificationSettingsNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final stored = await _storage.read(key: _key);
    if (stored != null) {
      state = stored == 'true';
    }
  }

  void toggle() {
    state = !state;
    _storage.write(key: _key, value: state.toString());
  }
}

/// Settings screen with sections for Calendar, Timezone, Routine, Notifications, Couple, and Account.
/// STORY-030: Create settings screen with all configuration sections.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final userProfile = authState.profile;
    final notificationsEnabled = ref.watch(notificationSettingsProvider);
    final syncState = ref.watch(calendarSyncNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Calendar Section
          SettingsSectionWidget(
            title: 'Calendar',
            icon: Icons.calendar_today,
            children: [
              // Calendar connection status
              Consumer(
                builder: (context, ref, child) {
                  final connectionState = ref.watch(
                    calendarConnectionNotifierProvider,
                  );
                  return connectionState.when(
                    data: (isConnected) => SettingsStatusItem(
                      title: 'Google Calendar',
                      subtitle:
                          'Connect your Google Calendar for automatic sync',
                      status: isConnected ? 'Connected' : 'Not Connected',
                      statusColor: isConnected
                          ? AppColors.successLight
                          : AppColors.categoryCommuteLight,
                      statusIcon: isConnected
                          ? Icons.cloud_done
                          : Icons.cloud_off,
                    ),
                    loading: () => const SettingsStatusItem(
                      title: 'Google Calendar',
                      subtitle:
                          'Connect your Google Calendar for automatic sync',
                      status: 'Checking...',
                      statusColor: AppColors.outlineLight,
                      statusIcon: Icons.hourglass_empty,
                    ),
                    error: (error, _) => SettingsStatusItem(
                      title: 'Google Calendar',
                      subtitle:
                          'Connect your Google Calendar for automatic sync',
                      status: 'Error',
                      statusColor: AppColors.errorLight,
                      statusIcon: Icons.error_outline,
                    ),
                  );
                },
              ),
              // Last sync status from calendarSyncNotifierProvider
              SettingsStatusItem(
                title: 'Last Sync',
                subtitle: 'Last time your calendar was synced',
                status: _formatLastSyncTime(syncState.lastSyncTime),
                statusColor: syncState.lastSyncTime != null
                    ? AppColors.successLight
                    : AppColors.outlineLight,
                statusIcon: syncState.lastSyncTime != null
                    ? Icons.sync
                    : Icons.sync_disabled,
              ),
              // Connect/Disconnect button
              Consumer(
                builder: (context, ref, child) {
                  final connectionState = ref.watch(
                    calendarConnectionNotifierProvider,
                  );
                  return connectionState.when(
                    data: (isConnected) => SettingsButton(
                      title: isConnected ? 'Disconnect' : 'Connect Calendar',
                      subtitle: isConnected
                          ? 'Remove Google Calendar access'
                          : 'Authorize Google Calendar access',
                      label: isConnected ? 'Disconnect' : 'Connect',
                      icon: isConnected ? Icons.link_off : Icons.link,
                      isDestructive: isConnected,
                      onTap: () =>
                          _handleCalendarConnection(context, ref, isConnected),
                    ),
                    loading: () => const SettingsButton(
                      title: 'Connect Calendar',
                      subtitle: 'Authorize Google Calendar access',
                      label: 'Connect',
                      icon: Icons.link,
                      enabled: false,
                      onTap: null,
                    ),
                    error: (error, _) => SettingsButton(
                      title: 'Connect Calendar',
                      subtitle: 'Authorize Google Calendar access',
                      label: 'Connect',
                      icon: Icons.link,
                      onTap: () =>
                          _handleCalendarConnection(context, ref, false),
                    ),
                  );
                },
              ),
              // Manual Sync
              Consumer(
                builder: (context, ref, child) {
                  final connectionState = ref.watch(
                    calendarConnectionNotifierProvider,
                  );
                  final isConnected = connectionState.valueOrNull ?? false;
                  final currentSyncState = ref.watch(
                    calendarSyncNotifierProvider,
                  );
                  return SettingsButton(
                    title: 'Manual Sync',
                    subtitle: 'Force sync your calendar now',
                    label: currentSyncState.isSyncing ? 'Syncing...' : 'Sync',
                    icon: Icons.sync,
                    enabled: isConnected && !currentSyncState.isSyncing,
                    onTap: isConnected && !currentSyncState.isSyncing
                        ? () => _handleManualSync(context, ref)
                        : null,
                  );
                },
              ),
            ],
          ),

          // Timezone Section
          SettingsSectionWidget(
            title: 'Timezone',
            icon: Icons.access_time,
            children: [
              SettingsStatusItem(
                title: 'Your Timezone',
                subtitle: 'Your current timezone setting',
                status: userProfile?.timezone ?? 'Not set',
                statusColor: userProfile?.timezone.isNotEmpty == true
                    ? AppColors.successLight
                    : AppColors.outlineLight,
                statusIcon: Icons.public,
              ),
              SettingsButton(
                title: 'Change Timezone',
                subtitle: 'Update your timezone preference',
                label: 'Change',
                icon: Icons.edit,
                onTap: () => context.go(AppRoutes.timezoneSetup),
              ),
            ],
          ),

          // Window Preferences Section
          SettingsSectionWidget(
            title: 'Window Preferences',
            icon: Icons.schedule,
            children: [
              SettingsToggle(
                title: 'Show late-night windows',
                subtitle: 'Include 23:00–07:00 local time in overlap windows',
                value: userProfile?.showLateNightWindows ?? false,
                onChanged: (value) =>
                    _setLateNightWindows(context, ref, authState.uid, value),
              ),
            ],
          ),

          // Notifications Section
          SettingsSectionWidget(
            title: 'Notifications',
            icon: Icons.notifications,
            children: [
              SettingsToggle(
                title: 'New Window Alerts',
                subtitle: 'Get notified when new free windows are found',
                value: notificationsEnabled,
                onChanged: (_) {
                  ref.read(notificationSettingsProvider.notifier).toggle();
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  'Toggle enables/disables local notifications. '
                  'This does not affect FCM registration.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),

          // Couple Section (only show if paired)
          if (userProfile?.coupleId != null)
            _buildCoupleSectionFromProvider(context, ref),

          // Account Section
          SettingsSectionWidget(
            title: 'Account',
            icon: Icons.person,
            children: [
              SettingsStatusItem(
                title: 'Email',
                subtitle: 'Your account email',
                status: userProfile?.email ?? 'Unknown',
                statusIcon: Icons.email,
              ),
              SettingsStatusItem(
                title: 'Display Name',
                subtitle: 'Your display name',
                status: userProfile?.displayName ?? userProfile?.email ?? 'Unknown',
                statusIcon: Icons.person_outline,
              ),
              const SizedBox(height: 8),
              SettingsButton(
                title: 'Sign Out',
                subtitle: 'Sign out from your account',
                label: 'Sign Out',
                icon: Icons.logout,
                isDestructive: true,
                onTap: () => _handleSignOut(context, ref),
              ),
            ],
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _setLateNightWindows(
    BuildContext context,
    WidgetRef ref,
    String? uid,
    bool value,
  ) async {
    if (uid == null) return;
    try {
      await ref.read(syncServiceProvider).updateUser(uid, {
        'showLateNightWindows': value,
      });
      await ref.read(authStateProvider.notifier).refreshProfile();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update preference: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Format the last sync time for display.
  String _formatLastSyncTime(DateTime? lastSyncTime) {
    if (lastSyncTime == null) return 'Never';
    final now = DateTime.now();
    final diff = now.difference(lastSyncTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return formatDateYMd(lastSyncTime);
  }

  /// Build the Couple section using coupleProvider and partnerProfileProvider.
  Widget _buildCoupleSectionFromProvider(BuildContext context, WidgetRef ref) {
    final coupleAsync = ref.watch(coupleProvider);

    return coupleAsync.when(
      loading: () => const SettingsSectionWidget(
        title: 'Couple',
        icon: Icons.favorite,
        children: [Center(child: CircularProgressIndicator())],
      ),
      error: (error, _) => SettingsSectionWidget(
        title: 'Couple',
        icon: Icons.favorite,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Failed to load couple data',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      data: (couple) {
        if (couple == null) {
          return SettingsSectionWidget(
            title: 'Couple',
            icon: Icons.favorite,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Couple data not available',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          );
        }
        return _buildCoupleSection(context, ref, couple);
      },
    );
  }

  Widget _buildCoupleSection(
    BuildContext context,
    WidgetRef ref,
    CoupleModel couple,
  ) {
    final partnerAsync = ref.watch(partnerProfileProvider);

    return partnerAsync.when(
      loading: () => SettingsSectionWidget(
        title: 'Couple',
        icon: Icons.favorite,
        children: [
          const SettingsStatusItem(
            title: 'Partner Name',
            subtitle: 'Your paired partner',
            status: 'Loading...',
            statusIcon: Icons.person,
          ),
          const SettingsStatusItem(
            title: 'Partner Email',
            subtitle: 'Partner\'s email address',
            status: 'Loading...',
            statusIcon: Icons.email,
          ),
          const SettingsStatusItem(
            title: 'Partner Timezone',
            subtitle: 'Partner\'s timezone',
            status: 'Loading...',
            statusIcon: Icons.public,
          ),
          const SizedBox(height: 8),
          SettingsButton(
            title: 'Unpair',
            subtitle: 'Remove pairing with your partner',
            label: 'Unpair',
            icon: Icons.link_off,
            isDestructive: true,
            onTap: () => _showUnpairDialog(context, ref, couple),
          ),
        ],
      ),
      error: (error, _) => SettingsSectionWidget(
        title: 'Couple',
        icon: Icons.favorite,
        children: [
          const SettingsStatusItem(
            title: 'Partner Name',
            subtitle: 'Your paired partner',
            status: 'Error loading',
            statusIcon: Icons.person,
          ),
          const SizedBox(height: 8),
          SettingsButton(
            title: 'Unpair',
            subtitle: 'Remove pairing with your partner',
            label: 'Unpair',
            icon: Icons.link_off,
            isDestructive: true,
            onTap: () => _showUnpairDialog(context, ref, couple),
          ),
        ],
      ),
      data: (partner) => SettingsSectionWidget(
        title: 'Couple',
        icon: Icons.favorite,
        children: [
          SettingsStatusItem(
            title: 'Partner Name',
            subtitle: 'Your paired partner',
            status: partner?.displayName ?? partner?.email ?? 'Unknown',
            statusIcon: Icons.person,
          ),
          SettingsStatusItem(
            title: 'Partner Email',
            subtitle: 'Partner\'s email address',
            status: partner?.email ?? 'Unknown',
            statusIcon: Icons.email,
          ),
          SettingsStatusItem(
            title: 'Partner Timezone',
            subtitle: 'Partner\'s timezone',
            status: partner?.timezone ?? 'Unknown',
            statusIcon: Icons.public,
          ),
          const SizedBox(height: 8),
          SettingsButton(
            title: 'Unpair',
            subtitle: 'Remove pairing with your partner',
            label: 'Unpair',
            icon: Icons.link_off,
            isDestructive: true,
            onTap: () => _showUnpairDialog(context, ref, couple),
          ),
        ],
      ),
    );
  }

  /// Handle manual calendar sync.
  Future<void> _handleManualSync(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref
          .read(calendarSyncNotifierProvider.notifier)
          .sync();
      if (context.mounted) {
        if (result.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sync error: ${result.error}'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Sync complete: ${result.blocksCreated} blocks synced',
              ),
              backgroundColor: AppColors.successLight,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to sync: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _handleCalendarConnection(
    BuildContext context,
    WidgetRef ref,
    bool isConnected,
  ) async {
    final notifier = ref.read(calendarConnectionNotifierProvider.notifier);

    if (isConnected) {
      // Show confirmation dialog before disconnecting
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Disconnect Calendar'),
          content: const Text(
            'Are you sure you want to disconnect Google Calendar? '
            'You will need to reconnect to sync your calendar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Disconnect'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      try {
        await notifier.disconnect();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Google Calendar disconnected')),
          );
        }
      } on CalendarException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to disconnect: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } else {
      // Connect to Google Calendar
      try {
        final connected = await notifier.connect();
        if (context.mounted) {
          if (connected) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Google Calendar connected successfully'),
                backgroundColor: AppColors.successLight,
              ),
            );
          }
        }
      } on CalendarException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to connect: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  void _showUnpairDialog(
    BuildContext context,
    WidgetRef ref,
    CoupleModel couple,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unpair from Partner'),
        content: const Text(
          'Are you sure you want to unpair? This will remove your connection '
          'with your partner and delete all shared data. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _handleUnpair(context, ref);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleUnpair(BuildContext context, WidgetRef ref) async {
    try {
      final authState = ref.read(authStateProvider);
      final profile = authState.profile;
      if (profile?.coupleId == null) return;

      // Delegate to the backend (POST /couples/:id/unpair). It atomically
      // marks the couple inactive (appending unpairHistory), clears coupleId
      // on BOTH users, and deletes shared timeblocks/overlaps. Client-side
      // writes to the partner's user doc are blocked by the backend's
      // couple-membership authz, so unpair MUST go through this endpoint.
      await ref.read(syncServiceProvider).unpair(profile!.coupleId!);

      // Refresh local profile so providers reflect the cleared coupleId.
      await ref.read(authStateProvider.notifier).refreshProfile();

      // Navigate to pairing screen so the user can pair again if desired.
      if (context.mounted) {
        context.go(AppRoutes.pairing);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unpair: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _handleSignOut(BuildContext context, WidgetRef ref) async {
    try {
      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sign Out'),
          content: const Text('Are you sure you want to sign out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Sign Out'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Sign out from Firebase Auth
      final auth = ref.read(authServiceProvider);
      await auth.signOut();

      // Clear all Riverpod state by invalidating providers
      ref.invalidate(authStateProvider);
      ref.invalidate(notificationSettingsProvider);

      // Navigation will be handled by GoRouter redirect guard
      // User will be redirected to /auth automatically
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to sign out: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}
