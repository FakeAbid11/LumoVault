import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/database_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../../../core/storage/thumbnail_cache.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../metadata/data/repositories/metadata_validator.dart';
import '../providers/storage_providers.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Storage settings — usage display and cache management.
///
/// Usage tiles are populated from [storageUsageProvider]; every maintenance
/// action performs real work and reports its outcome in a snackbar.
class StorageSettingsScreen extends ConsumerWidget {
  const StorageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usageAsync = ref.watch(storageUsageProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Storage')),
      body: ListView(
        children: [
          const _SectionHeader(title: 'Usage'),
          usageAsync.when(
            data: (usage) => _buildUsageTiles(context, usage),
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _usageTile(
              context,
              'Storage usage',
              'Unavailable',
              Symbols.error,
            ),
          ),
          const Divider(),
          const _SectionHeader(title: 'Cache Management'),
          ListTile(
            leading: const Icon(Symbols.delete_sweep),
            title: const Text('Clear Cache'),
            subtitle: const Text('Remove cached thumbnails and temp files'),
            onTap: () => _confirmClearCache(context, ref),
          ),
          ListTile(
            leading: const Icon(Symbols.photo_library),
            title: const Text('Rebuild Thumbnails'),
            subtitle: const Text('Regenerate all thumbnail images'),
            onTap: () => _confirmRebuildThumbnails(context, ref),
          ),
          const Divider(),
          const _SectionHeader(title: 'Maintenance'),
          ListTile(
            leading: const Icon(Symbols.build),
            title: const Text('Repair Metadata'),
            subtitle: const Text('Fix corrupted metadata entries'),
            onTap: () => _confirmRepairMetadata(context, ref),
          ),
          ListTile(
            leading: const Icon(Symbols.compress),
            title: const Text('Optimize Database'),
            subtitle: const Text('Compact and optimize the database'),
            onTap: () => _confirmOptimizeDatabase(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageTiles(BuildContext context, StorageUsage usage) {
    return Column(
      children: [
        _usageTile(
          context,
          'Photos & Videos',
          formatBytes(usage.deviceMediaBytes),
          Symbols.perm_media,
          subtitle: usage.deviceMediaCount > 0
              ? '${usage.deviceMediaCount} items on device'
              : null,
        ),
        _usageTile(
          context,
          'Telegram Storage',
          formatBytes(usage.telegramBytes),
          Symbols.cloud,
          subtitle: usage.telegramItemCount > 0
              ? '${usage.telegramItemCount} items backed up'
              : null,
        ),
        _usageTile(
          context,
          'Local Cache',
          formatBytes(usage.localCacheBytes),
          Symbols.storage,
        ),
        _usageTile(
          context,
          'Metadata',
          formatBytes(usage.metadataBytes),
          Symbols.data_object,
        ),
        _usageTile(
          context,
          'Thumbnail Cache',
          formatBytes(usage.thumbnailCacheBytes),
          Symbols.photo_size_select_actual,
        ),
        _usageTile(
          context,
          'Database',
          formatBytes(usage.databaseBytes),
          Symbols.storage,
        ),
      ],
    );
  }

  Widget _usageTile(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    String? subtitle,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  void _confirmClearCache(BuildContext context, WidgetRef ref) {
    _confirmAction(
      context: context,
      title: 'Clear Cache?',
      content:
          'This will remove cached thumbnails. They will be regenerated on '
          'next access.',
      confirmLabel: 'Clear',
      onConfirm: () async {
        final messenger = ScaffoldMessenger.of(context);
        await ThumbnailCache.instance.clear();
        if (!context.mounted) return;
        // Force timeline tiles to reload instead of staying on the stale
        // placeholder after the cache is wiped.
        ref.read(thumbnailGenerationProvider.notifier).state++;
        ref.invalidate(storageUsageProvider);
        messenger.showSnackBar(const SnackBar(content: Text('Cache cleared')));
      },
    );
  }

  void _confirmRebuildThumbnails(BuildContext context, WidgetRef ref) {
    _confirmAction(
      context: context,
      title: 'Rebuild Thumbnails?',
      content:
          'This may take a while for large libraries. Thumbnails will '
          'be regenerated as photos are viewed.',
      confirmLabel: 'Rebuild',
      onConfirm: () async {
        final messenger = ScaffoldMessenger.of(context);
        await ThumbnailCache.instance.clear();
        if (!context.mounted) return;
        // Force timeline tiles to regenerate on their next build.
        ref.read(thumbnailGenerationProvider.notifier).state++;
        ref.invalidate(storageUsageProvider);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Thumbnails will be rebuilt on next view'),
          ),
        );
      },
    );
  }

  void _confirmRepairMetadata(BuildContext context, WidgetRef ref) {
    _confirmAction(
      context: context,
      title: 'Repair Metadata?',
      content: 'This will scan and repair any corrupted metadata entries.',
      confirmLabel: 'Repair',
      onConfirm: () => _repairMetadata(context, ref),
    );
  }

  void _confirmOptimizeDatabase(BuildContext context, WidgetRef ref) {
    _confirmAction(
      context: context,
      title: 'Optimize Database?',
      content: 'This will compact the database. No data will be lost.',
      confirmLabel: 'Optimize',
      onConfirm: () => _optimizeDatabase(context, ref),
    );
  }

  void _confirmAction({
    required BuildContext context,
    required String title,
    required String content,
    required String confirmLabel,
    required Future<void> Function() onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onConfirm();
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _repairMetadata(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final gallery = ref.read(galleryRepositoryProvider);
      await gallery.hydrate();

      final validator = MetadataValidator(
        mediaItems: gallery.getTimelineItems(),
        searchTerms: const [],
      );
      final result = await validator.validate();
      final fixed = await validator.autoFix(result.issues);

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.issues.isEmpty
                ? 'Metadata is healthy (${result.itemsChecked} items)'
                : 'Metadata repair: ${result.issues.length} issue(s) found, '
                      '$fixed fixed',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Metadata repair failed: $e')),
      );
    }
  }

  Future<void> _optimizeDatabase(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final database = ref.read(appDatabaseProvider);
      await database.customStatement('PRAGMA optimize');
      await database.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
      if (!context.mounted) return;
      ref.invalidate(storageUsageProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Database optimized')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Database optimization failed: $e')),
      );
    }
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
