import 'package:flutter/material.dart';

/// Filter chip widget for LumoVault.
class LumoChip extends StatelessWidget {
  const LumoChip({
    required this.label,
    this.selected = false,
    this.onSelected,
    this.icon,
    super.key,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      avatar: icon != null
          ? Icon(
              icon,
              size: 18,
              color: selected
                  ? Theme.of(context).colorScheme.onSecondaryContainer
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            )
          : null,
    );
  }
}
