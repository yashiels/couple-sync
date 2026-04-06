import 'package:flutter/material.dart';

/// Placeholder screen for routine setup wizard.
/// Will be implemented in STORY-027+ (UI implementation phase).
class RoutineSetupScreen extends StatelessWidget {
  const RoutineSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Routine Setup'),
        automaticallyImplyLeading: false,
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.schedule,
                size: 64,
                color: Colors.grey,
              ),
              SizedBox(height: 24),
              Text(
                'Routine Setup Wizard',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Text(
                'Set up your weekly routine\n(Coming soon)',
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
