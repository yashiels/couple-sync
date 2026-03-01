import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/user_model.dart';
import '../../shared/providers/pairing_providers.dart';

// Fetches partner user document from Firestore
final partnerProfileProvider = FutureProvider.family<UserModel?, String>((ref, partnerUid) async {
  final snap = await FirebaseFirestore.instance.collection('users').doc(partnerUid).get();
  if (!snap.exists) return null;
  return UserModel.fromFirestore(snap);
});

class PartnerProfileScreen extends ConsumerWidget {
  final String partnerUid;
  const PartnerProfileScreen({super.key, required this.partnerUid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnerAsync = ref.watch(partnerProfileProvider(partnerUid));

    return Scaffold(
      appBar: AppBar(title: const Text('Partner Profile')),
      body: partnerAsync.when(
        data: (partner) => partner == null
            ? const Center(child: Text('Partner not found'))
            : _ProfileBody(partner: partner),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  final UserModel partner;
  const _ProfileBody({required this.partner});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              shape: BoxShape.circle,
            ),
            child: partner.photoUrl != null
                ? ClipOval(child: Image.network(partner.photoUrl!, fit: BoxFit.cover))
                : Center(
                    child: Text(
                      partner.displayName.isNotEmpty ? partner.displayName[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          Text(partner.displayName, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 4),
          Text(partner.email, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 32),

          // Info cards
          _InfoCard(
            icon: Icons.schedule_rounded,
            label: 'Timezone',
            value: partner.timezone,
          ),
          const SizedBox(height: 12),
          _InfoCard(
            icon: Icons.calendar_today_rounded,
            label: 'Paired since',
            value: 'Connected',
          ),
          const SizedBox(height: 32),

          // Unpair button
          OutlinedButton.icon(
            onPressed: () => _confirmUnpair(context, ref),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.link_off_rounded),
            label: const Text('Disconnect Partner'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmUnpair(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Partner?'),
        content: const Text(
          'This will remove your connection. You can reconnect later with a new invite code.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final couple = ref.read(currentCoupleProvider);
      if (couple != null) {
        await ref.read(pairingServiceProvider).unpair(couple);
        ref.read(currentCoupleProvider.notifier).state = null;
      }
    }
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: AppColors.lavenderDeep),
        title: Text(label, style: Theme.of(context).textTheme.titleSmall),
        subtitle: Text(value, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}
