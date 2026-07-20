import 'package:flutter/material.dart';

/// Standard floating action button for LumoVault.
class LumoFab extends StatelessWidget {
  const LumoFab({
    required this.onPressed,
    required this.icon,
    this.label,
    this.tooltip,
    super.key,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String? label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    if (label != null) {
      return FloatingActionButton.extended(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label!),
        tooltip: tooltip,
      );
    }

    return FloatingActionButton(
      onPressed: onPressed,
      tooltip: tooltip ?? '',
      child: Icon(icon),
    );
  }
}
