import 'package:flutter/material.dart';

/// Card widget for LumoVault with consistent styling.
class LumoCard extends StatelessWidget {
  const LumoCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
