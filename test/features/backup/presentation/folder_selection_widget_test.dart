import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/backup/data/models/backup_settings.dart';
import 'package:lumovault/features/backup/presentation/widgets/folder_selection_widget.dart';
import 'package:lumovault/features/gallery/data/models/device_folder.dart';

DeviceFolder _folder(String path, String name) => DeviceFolder(
  path: path,
  name: name,
  lastScannedAt: DateTime(2026),
  createdAt: DateTime(2026),
);

const _cameraPath = '/storage/emulated/0/DCIM/Camera';
const _picsumPath = '/storage/emulated/0/Pictures/Picsum';
const _whatsappPath = '/storage/emulated/0/WhatsApp/Media';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required List<DeviceFolder> folders,
    required List<String> included,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FolderSelectionWidget(
            folders: folders,
            settings: BackupSettings(includedFolders: included),
            onToggleFolder: (_) {},
            onSelectAll: () {},
            onDeselectAll: () {},
          ),
        ),
      ),
    );
  }

  bool allFoldersSwitch(WidgetTester tester) {
    return tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .first
        .value;
  }

  group('FolderSelectionWidget', () {
    testWidgets('All Folders is ON only when every path is actually included', (
      tester,
    ) async {
      final folders = [
        _folder(_cameraPath, 'Camera'),
        _folder(_picsumPath, 'Picsum'),
        _folder(_whatsappPath, 'WhatsApp'),
      ];
      await pump(
        tester,
        folders: folders,
        included: folders.map((f) => f.path).toList(),
      );

      expect(allFoldersSwitch(tester), isTrue);
    });

    // Regression: the old check compared COUNTS. A stale path in the persisted
    // selection (a folder deleted from the device, or a selection synced from
    // another phone) made the counts match while the contents differed, so
    // "All Folders" read ON and the per-folder switches were hidden entirely
    // — the UI showed a selection that backup would not honour.
    testWidgets('a same-size but different-content selection is not "All"', (
      tester,
    ) async {
      final folders = [
        _folder(_cameraPath, 'Camera'),
        _folder(_picsumPath, 'Picsum'),
      ];
      await pump(
        tester,
        folders: folders,
        included: [_cameraPath, '/storage/emulated/0/Deleted/Folder'],
      );

      expect(allFoldersSwitch(tester), isFalse);
      // Per-folder tiles are reachable (they were suppressed by the bug) and
      // reflect real membership: Camera on, Picsum off.
      final switches = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList();
      expect(switches.length, 3); // All + 2 folders
      expect(switches[1].value, isTrue); // Camera is included
      expect(switches[2].value, isFalse); // Picsum is NOT, despite equal counts
    });

    testWidgets('per-folder switches follow membership, not counts', (
      tester,
    ) async {
      final folders = [
        _folder(_cameraPath, 'Camera'),
        _folder(_picsumPath, 'Picsum'),
      ];
      await pump(tester, folders: folders, included: [_picsumPath]);

      final switches = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList();
      expect(switches.first.value, isFalse);
      expect(switches[1].value, isFalse); // Camera
      expect(switches[2].value, isTrue); // Picsum
    });
  });
}
