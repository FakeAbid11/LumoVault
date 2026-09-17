import 'package:flutter/material.dart';

/// Loading indicator widget.
///
/// Defaults to an indeterminate spinner. Pass [value] (0.0–1.0) for a
/// determinate progress ring, and [sub] for a secondary line beneath
/// [message] (e.g. "12 / 340 items") — used by scanning/backup states so they
/// share one loader instead of hand-rolled grey-text columns.
class LumoLoading extends StatelessWidget {
  const LumoLoading({
    this.message,
    this.sub,
    this.value,
    this.size = 48,
    super.key,
  });

  final String? message;
  final String? sub;
  final double? value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(value: value),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(
              sub!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
