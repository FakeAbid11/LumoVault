import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Storage settings — usage display and cache management.
class StorageSettingsScreen extends ConsumerWidget {
  const StorageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Storage')),
      body: ListView(
        children: [
          const _SectionHeader(title: 'Usage'),
          _usageTile(context, 'Telegram Storage', '0 B', Icons.cloud),
          _usageTile(context, 'Local Cache', '0 MB', Icons.storage),
          _usageTile(context, 'Metadata', '0 KB', Icons.data_object),
          _usageTile(
            context,
            'Thumbnail Cache',
            '0 MB',
            Icons.photo_size_select_actual,
          ),
          _usageTile(context, 'Database', '0 KB', Icons.storage),

          const Divider(),

          const _SectionHeader(title: 'Cache Management'),
          ListTile(
            leading: const Icon(Icons.delete_sweep),
            title: const Text('Clear Cache'),
            subtitle: const Text('Remove cached thumbnails and temp files'),
            onTap: () => _confirmClearCache(context),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Rebuild Thumbnails'),
            subtitle: const Text('Regenerate all thumbnail images'),
            onTap: () => _confirmRebuildThumbnails(context),
          ),

          const Divider(),

          const _SectionHeader(title: 'Maintenance'),
          ListTile(
            leading: const Icon(Icons.build),
            title: const Text('Repair Metadata'),
            subtitle: const Text('Fix corrupted metadata entries'),
            onTap: () => _confirmRepairMetadata(context),
          ),
          ListTile(
            leading: const Icon(Icons.compress),
            title: const Text('Optimize Database'),
            subtitle: const Text('Compact and optimize Isar database'),
            onTap: () => _confirmOptimizeDatabase(context),
          ),
        ],
      ),
    );
  }

  Widget _usageTile(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  void _confirmClearCache(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache?'),
        content: const Text(
          'This will remove cached thumbnails. They will be regenerated on next access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Cache cleared')));
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _confirmRebuildThumbnails(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rebuild Thumbnails?'),
        content: const Text('This may take a while for large libraries.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Thumbnail rebuild started')),
              );
            },
            child: const Text('Rebuild'),
          ),
        ],
      ),
    );
  }

  void _confirmRepairMetadata(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Repair Metadata?'),
        content: const Text(
          'This will scan and repair any corrupted metadata entries.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Metadata repair started')),
              );
            },
            child: const Text('Repair'),
          ),
        ],
      ),
    );
  }

  void _confirmOptimizeDatabase(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Optimize Database?'),
        content: const Text(
          'This will compact the database. No data will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Database optimization started')),
              );
            },
            child: const Text('Optimize'),
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
