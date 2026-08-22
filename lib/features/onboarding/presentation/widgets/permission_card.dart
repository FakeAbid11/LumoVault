import 'package:flutter/material.dart';

import '../../../../core/permissions/permission_service.dart'
    show PermissionStatus;

/// A card for requesting a specific permission during onboarding.
///
/// Displays permission icon, title, description, and action buttons
/// based on the current permission status.
class PermissionCard extends StatelessWidget {
  const PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.status,
    required this.onGrant,
    this.onOpenSettings,
    this.onManageLimited,
    super.key,
  });

  /// Convenience constructor for simple granted/not-granted states.
  factory PermissionCard.simple({
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    required VoidCallback onGrant,
    Key? key,
  }) {
    return PermissionCard(
      icon: icon,
      title: title,
      description: description,
      status: isGranted ? PermissionStatus.granted : PermissionStatus.denied,
      onGrant: onGrant,
      key: key,
    );
  }

  final IconData icon;
  final String title;
  final String description;
  final PermissionStatus status;
  final VoidCallback onGrant;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onManageLimited;

  bool get _isGranted =>
      status == PermissionStatus.granted || status == PermissionStatus.limited;

  bool get _isPermanentlyDenied => status == PermissionStatus.permanentlyDenied;

  bool get _isLimited => status == PermissionStatus.limited;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _isGranted
                        ? colorScheme.primaryContainer
                        : _isPermanentlyDenied
                        ? colorScheme.errorContainer
                        : colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: _isGranted
                        ? colorScheme.onPrimaryContainer
                        : _isPermanentlyDenied
                        ? colorScheme.onErrorContainer
                        : colorScheme.onSurfaceVariant,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isPermanentlyDenied
                            ? '$description — Please enable in Settings'
                            : _isLimited
                            ? '$description — Limited access'
                            : description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _isPermanentlyDenied
                              ? colorScheme.error
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isGranted && !_isLimited)
                  Icon(
                    Icons.check_circle,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                if (_isLimited)
                  Icon(
                    Icons.check_circle_outline,
                    color: colorScheme.tertiary,
                    size: 24,
                  ),
                if (_isPermanentlyDenied)
                  Icon(Icons.error_outline, color: colorScheme.error, size: 24),
              ],
            ),
            if (!_isGranted && !_isPermanentlyDenied) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: onGrant,
                  child: const Text('Grant'),
                ),
              ),
            ],
            if (_isPermanentlyDenied) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: onOpenSettings,
                  child: const Text('Open Settings'),
                ),
              ),
            ],
            if (_isLimited) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: onManageLimited,
                  child: const Text('Manage Access'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
