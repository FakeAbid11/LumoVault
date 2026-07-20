import 'package:flutter/material.dart';

import '../../../../core/permissions/permission_service.dart';

/// A widget displayed when a required permission is denied.
///
/// Shows an icon, message, and action button to grant or open settings.
class PermissionBlockedWidget extends StatelessWidget {
  const PermissionBlockedWidget({
    required this.status,
    required this.onGrantPressed,
    required this.onSettingsPressed,
    this.icon = Icons.photo_library_outlined,
    this.title = 'Permission required',
    this.grantLabel = 'Grant Permission',
    this.settingsLabel = 'Open Settings',
    super.key,
  });

  final PermissionStatus status;
  final VoidCallback onGrantPressed;
  final VoidCallback onSettingsPressed;
  final IconData icon;
  final String title;
  final String grantLabel;
  final String settingsLabel;

  bool get _isPermanentlyDenied => status == PermissionStatus.permanentlyDenied;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: colorScheme.error),
            const SizedBox(height: 24),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              _isPermanentlyDenied
                  ? 'Please enable this permission in Settings to continue.'
                  : 'Grant this permission to access this feature.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isPermanentlyDenied
                  ? onSettingsPressed
                  : onGrantPressed,
              icon: Icon(
                _isPermanentlyDenied ? Icons.settings : Icons.lock_open,
              ),
              label: Text(_isPermanentlyDenied ? settingsLabel : grantLabel),
            ),
          ],
        ),
      ),
    );
  }
}
