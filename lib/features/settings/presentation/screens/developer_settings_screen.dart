import 'package:flutter/material.dart';
import 'dart:io';

/// Developer settings — debug info, diagnostics, export logs.
class DeveloperSettingsScreen extends StatelessWidget {
  const DeveloperSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Developer Options')),
      body: ListView(
        children: [
          const _SectionHeader(title: 'Debug Information'),
          _infoTile(context, 'App Version', '1.0.0+1'),
          _infoTile(context, 'Dart Version', Platform.version.split(' ').first),
          _infoTile(context, 'Flutter Version', '3.12.2'),
          _infoTile(context, 'Platform', Platform.operatingSystem),
          _infoTile(context, 'Metadata Schema', 'v1'),
          _infoTile(context, 'Settings Version', '1.0.0'),

          const Divider(),

          const _SectionHeader(title: 'Database'),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('Database Information'),
            subtitle: const Text('View Isar database details'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showDatabaseInfo(context),
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Sync Status'),
            subtitle: const Text('View metadata sync state'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showSyncStatus(context),
          ),

          const Divider(),

          const _SectionHeader(title: 'Actions'),
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('Export Logs'),
            subtitle: const Text('Share diagnostic logs'),
            onTap: () => _exportLogs(context),
          ),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('Run Diagnostics'),
            subtitle: const Text('Check app health'),
            onTap: () => _runDiagnostics(context),
          ),

          const Divider(),

          const _SectionHeader(title: 'Experimental'),
          SwitchListTile(
            secondary: const Icon(Icons.science),
            title: const Text('Debug Mode'),
            subtitle: const Text('Enable verbose logging'),
            value: false,
            onChanged: (value) {
              // Wire to debug logging in production.
            },
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
            Text('Engine: Isar 3.1.0'),
            SizedBox(height: 8),
            Text('Schemas: MediaItem, UploadTask, BackupQueue'),
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

  void _showSyncStatus(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync Status'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last sync: Never'),
            SizedBox(height: 8),
            Text('Pending changes: 0'),
            SizedBox(height: 8),
            Text('Sync in progress: No'),
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

  void _exportLogs(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Log export — coming soon')));
  }

  void _runDiagnostics(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Diagnostics'),
        content: const Text('All systems operational.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
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
