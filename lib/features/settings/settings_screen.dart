import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// App settings screen with account, partner, and notification options.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(label: 'Account'),
          _SettingsTile(icon: Icons.person_rounded, title: 'Profile', onTap: () {}),
          _SettingsTile(icon: Icons.schedule_rounded, title: 'Timezone', onTap: () {}),
          const Divider(height: 32),
          _SectionHeader(label: 'Partner'),
          _SettingsTile(icon: Icons.favorite_rounded, title: 'Partner Profile', onTap: () {}),
          _SettingsTile(icon: Icons.link_rounded, title: 'Pairing Code', onTap: () {}),
          const Divider(height: 32),
          _SectionHeader(label: 'Notifications'),
          _SettingsTile(icon: Icons.notifications_rounded, title: 'Push Notifications', onTap: () {}),
          const Divider(height: 32),
          _SectionHeader(label: 'Account'),
          _SettingsTile(
            icon: Icons.logout_rounded,
            title: 'Sign Out',
            onTap: () {},
            color: AppColors.error,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? color;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: c),
        title: Text(title, style: TextStyle(color: c, fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
        onTap: onTap,
      ),
    );
  }
}
