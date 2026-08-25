import 'package:flutter/material.dart';

/// A titled, grouped settings section rendered as a rounded card.
///
/// Replaces the old flat `ListView` of `ListTile`s split by `Divider`s and a
/// private `_SectionHeader`. Each section is a rounded `surfaceContainerLow`
/// container with a small header above it; child rows are separated by hairline
/// inset dividers so grouped options read as one unit.
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Material(
            clipBehavior: Clip.antiAlias,
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            child: Column(children: _withDividers(context, children)),
          ),
        ],
      ),
    );
  }

  List<Widget> _withDividers(BuildContext context, List<Widget> rows) {
    if (rows.length <= 1) return rows;
    final divided = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      divided.add(rows[i]);
      if (i != rows.length - 1) {
        divided.add(
          const Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
        );
      }
    }
    return divided;
  }
}
