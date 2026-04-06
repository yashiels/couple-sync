import 'package:flutter/material.dart';

/// Placeholder screen for overlap/windows view.
/// Will be implemented in STORY-027+ (UI implementation phase).
class OverlapScreen extends StatelessWidget {
  const OverlapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mutual Free Time'),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.access_time,
                size: 64,
                color: Colors.grey,
              ),
              SizedBox(height: 24),
              Text(
                'Overlap Windows',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Text(
                'View mutual free time with your partner\n(Coming soon)',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
