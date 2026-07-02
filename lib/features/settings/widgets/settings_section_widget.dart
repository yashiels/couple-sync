import 'package:flutter/material.dart';

/// Reusable settings section widget with consistent styling.
/// Groups related settings items under a titled card.
class SettingsSectionWidget extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final IconData? icon;

  const SettingsSectionWidget({
    super.key,
    required this.title,
    required this.children,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                ],
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Settings item with a title, subtitle, and trailing widget.
class SettingsItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget trailing;
  final VoidCallback? onTap;
  final bool enabled;

  const SettingsItem({
    super.key,
    required this.title,
    this.subtitle,
    required this.trailing,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: enabled
                          ? theme.textTheme.bodyLarge?.color
                          : theme.disabledColor,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: enabled
                            ? theme.textTheme.bodySmall?.color
                            : theme.disabledColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// Settings item with a toggle switch.
class SettingsToggle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  const SettingsToggle({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsItem(
      title: title,
      subtitle: subtitle,
      enabled: enabled,
      trailing: Switch(value: value, onChanged: enabled ? onChanged : null),
    );
  }
}

/// Settings item with a button action.
class SettingsButton extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool enabled;
  final Color? color;
  final bool isDestructive;

  const SettingsButton({
    super.key,
    required this.title,
    this.subtitle,
    required this.label,
    this.icon,
    this.onTap,
    this.enabled = true,
    this.color,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonColor = isDestructive
        ? theme.colorScheme.error
        : (color ?? theme.colorScheme.primary);

    return SettingsItem(
      title: title,
      subtitle: subtitle,
      enabled: enabled,
      onTap: onTap,
      trailing: TextButton.icon(
        onPressed: enabled ? onTap : null,
        icon: icon != null
            ? Icon(icon, size: 18, color: buttonColor)
            : const SizedBox.shrink(),
        label: Text(label, style: TextStyle(color: buttonColor)),
      ),
    );
  }
}

/// Settings item with a status indicator.
class SettingsStatusItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String status;
  final Color? statusColor;
  final IconData? statusIcon;

  const SettingsStatusItem({
    super.key,
    required this.title,
    this.subtitle,
    required this.status,
    this.statusColor,
    this.statusIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = statusColor ?? theme.colorScheme.onSurface;

    return SettingsItem(
      title: title,
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (statusIcon != null) ...[
            Icon(statusIcon, size: 16, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            status,
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
