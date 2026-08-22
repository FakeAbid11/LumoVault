import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../metadata/data/repositories/metadata_repository.dart'
    show MetadataSyncStatus;
import '../../../metadata/presentation/providers/metadata_providers.dart';
import '../providers/settings_providers.dart';

/// Developer settings — debug info, diagnostics, live sync state.
class DeveloperSettingsScreen extends ConsumerWidget {
  const DeveloperSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packageInfo = ref.watch(appPackageInfoProvider);
    final appVersion = packageInfo.when(
      data: (info) => '${info.version} (build ${info.buildNumber})',
      loading: () => '…',
      error: (_, __) => 'unavailable',
    );
    final debugMode = ref.watch(appSettingsProvider).debugMode;

    return Scaffold(
      appBar: AppBar(title: const Text('Developer Options')),
      body: ListView(
        children: [
          const _SectionHeader(title: 'Debug Information'),
          _infoTile(context, 'App Version', appVersion),
          _infoTile(context, 'Dart SDK', Platform.version.split(' ').first),
          _infoTile(context, 'Database Engine', 'Drift (SQLite)'),
          _infoTile(context, 'Schema Version', 'v4'),
          _infoTile(context, 'Platform', Platform.operatingSystem),

          const Divider(),

          const _SectionHeader(title: 'Database'),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('Database Information'),
            subtitle: const Text('View Drift database details'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showDatabaseInfo(context),
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Sync Status'),
            subtitle: const Text('View metadata sync state'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showSyncStatus(context, ref),
          ),

          const Divider(),

          const _SectionHeader(title: 'Experimental'),
          SwitchListTile(
            secondary: const Icon(Icons.science),
            title: const Text('Debug Mode'),
            subtitle: const Text('Emit verbose diagnostic logs (logcat)'),
            value: debugMode,
            onChanged: (value) => ref
                .read(appSettingsProvider.notifier)
                .updateField((s) => s.copyWith(debugMode: value)),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(BuildContext context, String label, String value) {
    return ListTile(
      title: Text(label),
      subtitle: Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
      ),
    );
  }

  void _showDatabaseInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Database Information'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Engine: Drift (SQLite)'),
            SizedBox(height: 8),
            Text('Schema version: v4'),
            SizedBox(height: 8),
            Text('Status: Active'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSyncStatus(BuildContext context, WidgetRef ref) {
    final MetadataSyncStatus status = ref.read(metadataSyncStatusProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync Status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last sync: ${status.lastSyncDisplay}'),
            const SizedBox(height: 8),
            Text('Pending changes: ${status.pendingChangesCount}'),
            const SizedBox(height: 8),
            Text('Sync in progress: ${status.syncInProgress ? 'Yes' : 'No'}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
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
