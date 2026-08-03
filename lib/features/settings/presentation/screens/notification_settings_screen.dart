import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_providers.dart';

/// Notification settings — toggle each notification type.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        children: [
          const _SectionHeader(title: 'Backup'),
          SwitchListTile(
            secondary: const Icon(Icons.backup),
            title: const Text('Backup Progress'),
            subtitle: const Text('Show ongoing backup notifications'),
            value: settings.backupProgressNotification,
            onChanged: (value) {
              ref
                  .read(appSettingsProvider.notifier)
                  .updateField(
                    (s) => s.copyWith(backupProgressNotification: value),
                  );
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.check_circle),
            title: const Text('Backup Completed'),
            subtitle: const Text('Notify when backup finishes'),
            value: settings.backupCompletedNotification,
            onChanged: (value) {
              ref
                  .read(appSettingsProvider.notifier)
                  .updateField(
                    (s) => s.copyWith(backupCompletedNotification: value),
                  );
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.error),
            title: const Text('Backup Failed'),
            subtitle: const Text('Notify when backup fails'),
            value: settings.backupFailedNotification,
            onChanged: (value) {
              ref
                  .read(appSettingsProvider.notifier)
                  .updateField(
                    (s) => s.copyWith(backupFailedNotification: value),
                  );
            },
          ),

          const Divider(),

          const _SectionHeader(title: 'Restore'),
          SwitchListTile(
            secondary: const Icon(Icons.restore),
            title: const Text('Restore Completed'),
            subtitle: const Text('Notify when restore finishes'),
            value: settings.restoreCompletedNotification,
            onChanged: (value) {
              ref
                  .read(appSettingsProvider.notifier)
                  .updateField(
                    (s) => s.copyWith(restoreCompletedNotification: value),
                  );
            },
          ),

          const Divider(),

          const _SectionHeader(title: 'System'),
          SwitchListTile(
            secondary: const Icon(Icons.storage),
            title: const Text('Storage Warning'),
            subtitle: const Text('Warn when Telegram storage is low'),
            value: settings.storageWarningNotification,
            onChanged: (value) {
              ref
                  .read(appSettingsProvider.notifier)
                  .updateField(
                    (s) => s.copyWith(storageWarningNotification: value),
                  );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
