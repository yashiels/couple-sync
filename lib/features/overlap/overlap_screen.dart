import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class OverlapScreen extends StatelessWidget {
  const OverlapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Free Windows')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite_rounded, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text('Free Windows', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Moments when you are both free\nwill appear here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
