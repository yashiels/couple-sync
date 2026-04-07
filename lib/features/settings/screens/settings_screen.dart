import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/couple_model.dart';
import '../../../core/models/user_model.dart';
import '../../../core/router/routes.dart';
import '../../../services/auth_service.dart';
import '../../../services/providers/auth_state_provider.dart';
import '../../../services/providers/firestore_provider.dart';
import '../widgets/settings_section_widget.dart';

// TODO: STORY-018 - Implement Google Calendar OAuth
// TODO: STORY-019 - Implement Google Calendar sync functionality

/// Provider for notification settings (local flag, doesn't affect FCM registration).
/// This is a simple local preference that can be extended to persist to Firestore.
final notificationSettingsProvider = StateNotifierProvider<NotificationSettingsNotifier, bool>((ref) {
  return NotificationSettingsNotifier();
});

class NotificationSettingsNotifier extends StateNotifier<bool> {
  NotificationSettingsNotifier() : super(true); // Default to enabled

  void toggle() {
    state = !state;
    // TODO: Persist to Firestore user preferences if needed
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // Calendar Section
          SettingsSectionWidget(
            title: 'Calendar',
            icon: Icons.calendar_today,
            children: [
              // TODO: STORY-018 - Connect to Google Calendar OAuth status
              const SettingsStatusItem(
                title: 'Google Calendar',
                subtitle: 'Connect your Google Calendar for automatic sync',
                status: 'Not Connected',
                statusColor: Colors.orange,
                statusIcon: Icons.cloud_off,
              ),
              // TODO: STORY-019 - Show last sync time from sync service
              const SettingsStatusItem(
                title: 'Last Sync',
                subtitle: 'Last time your calendar was synced',
                status: 'Never',
                statusColor: Colors.grey,
                statusIcon: Icons.sync_disabled,
              ),
              // TODO: STORY-018 - Add Connect/Disconnect button functionality
              SettingsButton(
                title: 'Connect Calendar',
                subtitle: 'Authorize Google Calendar access',
                label: 'Connect',
                icon: Icons.link,
                onTap: () {
                  // TODO: STORY-018 - Trigger OAuth flow
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Calendar integration coming soon'),
                    ),
                  );
                },
              ),
              // TODO: STORY-019 - Add Manual Sync functionality
              SettingsButton(
                title: 'Manual Sync',
                subtitle: 'Force sync your calendar now',
                label: 'Sync',
                icon: Icons.sync,
                enabled: false, // Disabled until OAuth implemented
                onTap: () {
                  // TODO: STORY-019 - Trigger manual sync
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
                    ? Colors.green
                    : Colors.grey,
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

          // Routine Section
          SettingsSectionWidget(
            title: 'Routine',
            icon: Icons.schedule,
            children: [
              const SettingsItem(
                title: 'Weekly Routine',
                subtitle: 'Your weekly availability blocks',
                trailing: Icon(Icons.info_outline, size: 20),
              ),
              SettingsButton(
                title: 'Re-run Setup',
                subtitle: 'Configure your weekly routine again',
                label: 'Setup',
                icon: Icons.refresh,
                onTap: () => context.go(AppRoutes.routineSetup),
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  'Toggle enables/disables local notifications. '
                  'This does not affect FCM registration.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),

          // Couple Section (only show if paired)
          if (userProfile?.coupleId != null)
            FutureBuilder<CoupleModel?>(
              future: _fetchCouple(ref, userProfile!.coupleId!),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SettingsSectionWidget(
                    title: 'Couple',
                    icon: Icons.favorite,
                    children: [
                      Center(child: CircularProgressIndicator()),
                    ],
                  );
                }

                final couple = snapshot.data!;
                return _buildCoupleSection(context, ref, couple, userProfile);
              },
            ),

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
                status: userProfile?.displayName ?? 'Unknown',
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

  Future<CoupleModel?> _fetchCouple(WidgetRef ref, String coupleId) async {
    final firestore = ref.read(firestoreServiceProvider);
    return firestore.getCouple(coupleId);
  }

  Widget _buildCoupleSection(
    BuildContext context,
    WidgetRef ref,
    CoupleModel couple,
    UserModel userProfile,
  ) {
    return FutureBuilder<UserModel?>(
      future: _fetchPartner(ref, couple, userProfile),
      builder: (context, snapshot) {
        final partner = snapshot.data;
        
        return SettingsSectionWidget(
          title: 'Couple',
          icon: Icons.favorite,
          children: [
            SettingsStatusItem(
              title: 'Partner Name',
              subtitle: 'Your paired partner',
              status: partner?.displayName ?? 'Loading...',
              statusIcon: Icons.person,
            ),
            SettingsStatusItem(
              title: 'Partner Email',
              subtitle: 'Partner\'s email address',
              status: partner?.email ?? 'Loading...',
              statusIcon: Icons.email,
            ),
            SettingsStatusItem(
              title: 'Partner Timezone',
              subtitle: 'Partner\'s timezone',
              status: partner?.timezone ?? 'Loading...',
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
        );
      },
    );
  }

  Future<UserModel?> _fetchPartner(
    WidgetRef ref,
    CoupleModel couple,
    UserModel userProfile,
  ) async {
    final partnerUid = couple.getPartnerUid(userProfile.email);
    if (partnerUid == null) return null;
    
    final firestore = ref.read(firestoreServiceProvider);
    return firestore.getUser(partnerUid);
  }

  void _showUnpairDialog(BuildContext context, WidgetRef ref, CoupleModel couple) {
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
              await _handleUnpair(context, ref, couple);
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

  Future<void> _handleUnpair(BuildContext context, WidgetRef ref, CoupleModel couple) async {
    try {
      final authState = ref.read(authStateProvider);
      final userProfile = authState.profile;
      
      if (userProfile == null) return;
      
      // TODO: STORY-011 - Implement unpair functionality in FirestoreService
      // This should:
      // 1. Update couple status to 'inactive'
      // 2. Add unpair history entry
      // 3. Clear coupleId from both users
      // 4. Optionally delete shared time blocks
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unpair functionality coming soon'),
        ),
      );
      
      // For now, just show a message
      // When implemented, navigate to pairing screen after unpair
      // context.go(AppRoutes.pairing);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to unpair: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to sign out: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}
