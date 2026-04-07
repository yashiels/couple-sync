import 'package:flutter/material.dart';
import '../../../core/router/routes.dart';

/// Placeholder screen for the block form (create/edit).
/// Will be implemented in STORY-027+ (UI implementation phase).
class BlockFormScreen extends StatelessWidget {
  final BlockFormArgs? args;

  const BlockFormScreen({super.key, this.args});

  @override
  Widget build(BuildContext context) {
    final isEditing = args?.blockId != null;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Block' : 'New Block'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isEditing ? Icons.edit : Icons.add,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 24),
              Text(
                isEditing ? 'Edit Time Block' : 'Create Time Block',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                isEditing 
                    ? 'Editing block: ${args?.blockId}\n(Coming soon)'
                    : 'Create a new time block\n(Coming soon)',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
