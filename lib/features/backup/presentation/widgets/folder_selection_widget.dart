import 'package:flutter/material.dart';

import '../../data/models/backup_settings.dart';
import '../../../gallery/data/models/device_folder.dart';
import '../../../../core/utils/format_utils.dart';

/// Folder selection widget for choosing which device folders are backed up.
///
/// Uses an inclusion model: the user selects which folders to back up.
/// An empty [BackupSettings.includedFolders] list means *no* folders are
/// backed up (backup is off). An [onSelectAll] callback sets the list to
/// every available folder path.
class FolderSelectionWidget extends StatelessWidget {
  const FolderSelectionWidget({
    super.key,
    required this.folders,
    required this.settings,
    required this.onToggleFolder,
    required this.onSelectAll,
    required this.onDeselectAll,
  });

  final List<DeviceFolder> folders;
  final BackupSettings settings;
  final void Function(String folderPath) onToggleFolder;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;

  // Set containment, not a length comparison: a stale path in
  // includedFolders (a folder deleted from the device, or a selection synced
  // from another phone) used to make the COUNTS match while the CONTENTS
  // differed, flipping every switch — and "All Folders" — ON while the real
  // selection was wrong. The UI was lying about what would back up.
  bool get _allIncluded =>
      folders.isNotEmpty &&
      folders.every((f) => settings.includedFolders.contains(f.path));

  bool _isFolderIncluded(String folderPath) =>
      settings.includedFolders.contains(folderPath);

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
                _allIncluded
                    ? 'All folders'
                    : '${settings.includedFolders.length} selected',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SwitchListTile(
          title: const Text('All Folders'),
          subtitle: const Text('Back up all device folders'),
          value: _allIncluded,
          onChanged: (value) {
            if (value) {
              onSelectAll();
            } else {
              onDeselectAll();
            }
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
      onChanged: (value) => onToggleFolder(folder.path),
    );
  }
}
