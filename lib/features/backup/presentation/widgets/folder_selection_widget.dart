import 'package:flutter/material.dart';

import '../../data/models/backup_settings.dart';
import '../../../gallery/data/models/device_folder.dart';

/// Folder selection widget for choosing which device folders are backed up.
///
/// Per PRD Section 7/9:
/// - Default: all folders included
/// - User can exclude specific folders
/// - UI shows folder list with toggle switches
class FolderSelectionWidget extends StatelessWidget {
  const FolderSelectionWidget({
    super.key,
    required this.folders,
    required this.settings,
    required this.onToggleFolder,
  });

  final List<DeviceFolder> folders;
  final BackupSettings settings;
  final void Function(String folderPath) onToggleFolder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'INCLUDED FOLDERS',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Text(
                settings.allFoldersIncluded
                    ? 'All folders'
                    : '${settings.includedFolders.length} selected',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (settings.allFoldersIncluded)
          _buildAllFoldersTile(context)
        else
          ...folders.map((folder) => _buildFolderTile(context, folder)),
      ],
    );
  }

  Widget _buildAllFoldersTile(BuildContext context) {
    return SwitchListTile(
      title: const Text('All Folders'),
      subtitle: const Text('Back up all device folders'),
      value: true,
      onChanged: (value) {
        if (!value) {
          // When turning off "all folders", exclude all folders.
          // User can then selectively include specific ones.
          for (final folder in folders) {
            onToggleFolder(folder.path);
          }
        }
      },
    );
  }

  Widget _buildFolderTile(BuildContext context, DeviceFolder folder) {
    final isExcluded = settings.isFolderExcluded(folder.path);

    return SwitchListTile(
      title: Text(folder.name),
      subtitle: Text(
        '${folder.totalItems} items (${_formatBytes(folder.totalSize)})',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      value: !isExcluded,
      onChanged: (value) => onToggleFolder(folder.path),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
