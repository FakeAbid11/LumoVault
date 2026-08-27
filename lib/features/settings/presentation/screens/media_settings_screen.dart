import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/gallery_providers.dart';
import '../../../gallery/data/models/device_folder.dart';
import '../../data/models/app_settings.dart';
import '../providers/settings_providers.dart';
import '../../../../core/utils/format_utils.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Media settings — folders and backup content options.
///
/// Album-level exclusion is intentionally unsupported: the backup scheduler
/// filters on `includedFolders`/`excludedFolders` only, so a per-album control
/// would silently do nothing.
class MediaSettingsScreen extends ConsumerWidget {
  const MediaSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Media Settings')),
      body: ListView(
        children: [
          const _SectionHeader(title: 'Backup Content'),
          SwitchListTile(
            secondary: const Icon(Symbols.photo),
            title: const Text('Backup Photos'),
            subtitle: const Text('Include photos in backups'),
            value: settings.backupPhotos,
            onChanged: (value) {
              ref
                  .read(appSettingsProvider.notifier)
                  .updateField((s) => s.copyWith(backupPhotos: value));
            },
          ),
          SwitchListTile(
            secondary: const Icon(Symbols.videocam),
            title: const Text('Backup Videos'),
            subtitle: const Text('Include videos in backups'),
            value: settings.backupVideos,
            onChanged: (value) {
              ref
                  .read(appSettingsProvider.notifier)
                  .updateField((s) => s.copyWith(backupVideos: value));
            },
          ),

          const Divider(),

          const _SectionHeader(title: 'Folders'),
          ref
              .watch(deviceFoldersProvider)
              .when(
                data: (folders) => _FolderTiles(
                  folders: folders,
                  settings: settings,
                  ref: ref,
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Could not load folders: $e'),
                ),
              ),

          const Divider(),

          const _SectionHeader(title: 'Trash'),
          ListTile(
            leading: const Icon(Symbols.delete),
            title: const Text('Trash Duration'),
            subtitle: Text('${settings.trashDurationDays} days'),
            trailing: const Icon(Symbols.chevron_right),
            onTap: () => _showTrashDuration(context, ref, settings),
          ),

          const Divider(),

          const _SectionHeader(title: 'Size Limits'),
          ListTile(
            leading: const Icon(Symbols.file_upload),
            title: const Text('Max File Size'),
            subtitle: Text(_maxFileSizeDisplay(settings.maxFileSizeBytes)),
            trailing: const Icon(Symbols.chevron_right),
            onTap: () => _showMaxFileSize(context, ref, settings),
          ),
        ],
      ),
    );
  }

  String _maxFileSizeDisplay(int bytes) {
    if (bytes == 0) return 'No limit';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void _showTrashDuration(
    BuildContext context,
    WidgetRef ref,
    dynamic settings,
  ) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Trash Duration'),
        children: [
          _trashOption(context, ref, 7, '7 days'),
          _trashOption(context, ref, 14, '14 days'),
          _trashOption(context, ref, 30, '30 days'),
          _trashOption(context, ref, 60, '60 days'),
          _trashOption(context, ref, 90, '90 days'),
          _trashOption(context, ref, 365, '1 year'),
          _trashOption(context, ref, 0, 'Never delete'),
        ],
      ),
    );
  }

  SimpleDialogOption _trashOption(
    BuildContext context,
    WidgetRef ref,
    int days,
    String label,
  ) {
    return SimpleDialogOption(
      onPressed: () {
        ref
            .read(appSettingsProvider.notifier)
            .updateField((s) => s.copyWith(trashDurationDays: days));
        Navigator.of(context).pop();
      },
      child: Text(label),
    );
  }

  void _showMaxFileSize(BuildContext context, WidgetRef ref, dynamic settings) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Max File Size'),
        children: [
          _sizeOption(context, ref, 0, 'No limit'),
          _sizeOption(context, ref, 5 * 1024 * 1024, '5 MB'),
          _sizeOption(context, ref, 10 * 1024 * 1024, '10 MB'),
          _sizeOption(context, ref, 50 * 1024 * 1024, '50 MB'),
          _sizeOption(context, ref, 100 * 1024 * 1024, '100 MB'),
          _sizeOption(context, ref, 500 * 1024 * 1024, '500 MB'),
          _sizeOption(context, ref, 1024 * 1024 * 1024, '1 GB'),
        ],
      ),
    );
  }

  SimpleDialogOption _sizeOption(
    BuildContext context,
    WidgetRef ref,
    int bytes,
    String label,
  ) {
    return SimpleDialogOption(
      onPressed: () {
        ref
            .read(appSettingsProvider.notifier)
            .updateField((s) => s.copyWith(maxFileSizeBytes: bytes));
        Navigator.of(context).pop();
      },
      child: Text(label),
    );
  }
}

class _FolderTiles extends StatelessWidget {
  const _FolderTiles({
    required this.folders,
    required this.settings,
    required this.ref,
  });

  final List<DeviceFolder> folders;
  final AppSettings settings;
  final WidgetRef ref;

  bool get _allIncluded =>
      settings.includedFolders.length == folders.length && folders.isNotEmpty;

  bool _isFolderIncluded(String folderPath) =>
      settings.includedFolders.contains(folderPath);

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No folders found on this device.'),
      );
    }

    final allPaths = folders.map((f) => f.path).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('All Folders'),
          subtitle: Text(
            _allIncluded
                ? 'Back up all device folders'
                : '${settings.includedFolders.length} folder(s) selected',
          ),
          value: _allIncluded,
          onChanged: (value) {
            ref
                .read(appSettingsProvider.notifier)
                .updateField(
                  (s) => s.copyWith(
                    includedFolders: value ? allPaths : <String>[],
                  ),
                );
          },
        ),
        if (!_allIncluded)
          ...folders.map((folder) => _buildFolderTile(context, folder)),
      ],
    );
  }

  Widget _buildFolderTile(BuildContext context, DeviceFolder folder) {
    return SwitchListTile(
      title: Text(folder.name),
      subtitle: Text(
        '${folder.totalItems} items (${formatBytes(folder.totalSize)})',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      value: _isFolderIncluded(folder.path),
      onChanged: (_) => _toggleFolder(folder.path),
    );
  }

  void _toggleFolder(String folderPath) {
    final included = List<String>.of(settings.includedFolders);
    if (included.contains(folderPath)) {
      included.remove(folderPath);
    } else {
      included.add(folderPath);
    }
    ref
        .read(appSettingsProvider.notifier)
        .updateField((s) => s.copyWith(includedFolders: included));
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
