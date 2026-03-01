import 'package:flutter/material.dart';

/// A labelled group of settings tiles with a divider at the bottom.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            title.toUpperCase(),
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          child: Column(children: _separated(children)),
        ),
      ],
    );
  }

  List<Widget> _separated(List<Widget> items) {
    if (items.isEmpty) return [];
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      result.add(items[i]);
      if (i < items.length - 1) {
        result.add(const Divider(height: 1, indent: 16, endIndent: 16));
      }
    }
    return result;
  }
}
