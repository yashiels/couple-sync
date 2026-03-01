import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class PairingScreen extends StatelessWidget {
  const PairingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Connect with Partner'),
          bottom: TabBar(
            labelColor: AppColors.roseDeep,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.roseDeep,
            tabs: const [
              Tab(text: 'Share Code'),
              Tab(text: 'Enter Code'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ShareCodeTab(),
            _EnterCodeTab(),
          ],
        ),
      ),
    );
  }
}

class _ShareCodeTab extends StatelessWidget {
  const _ShareCodeTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.share_rounded, size: 64, color: AppColors.lavender),
            const SizedBox(height: 24),
            Text('Your Invite Code', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'ABC123',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 8,
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy Code'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnterCodeTab extends StatelessWidget {
  const _EnterCodeTab();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.person_add_rounded, size: 64, color: AppColors.rose),
          const SizedBox(height: 24),
          Text('Enter Partner\'s Code', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),
          TextField(
            decoration: const InputDecoration(
              hintText: 'e.g. ABC123',
              prefixIcon: Icon(Icons.vpn_key_rounded),
            ),
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {},
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}
