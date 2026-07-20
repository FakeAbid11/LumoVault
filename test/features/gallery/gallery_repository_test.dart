import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/gallery/data/models/media_item.dart';
import 'package:lumovault/features/gallery/data/models/device_folder.dart';
import 'package:lumovault/features/gallery/data/repositories/gallery_repository.dart';
import 'package:lumovault/features/gallery/data/repositories/media_scanner_service.dart';
import 'package:photo_manager/photo_manager.dart';

class MockMediaScannerService implements MediaScannerService {
  final List<MediaItem> _mediaItems = [];
  final List<DeviceFolder> _folders = [];
  bool _shouldFail = false;

  void setMediaItems(List<MediaItem> items) {
    _mediaItems.clear();
    _mediaItems.addAll(items);
  }

  void setFolders(List<DeviceFolder> folders) {
    _folders.clear();
    _folders.addAll(folders);
  }

  void setShouldFail(bool shouldFail) {
    _shouldFail = shouldFail;
  }

  @override
  Future<bool> checkPermission() async => !_shouldFail;

  @override
  Future<bool> requestPermission() async => !_shouldFail;

  @override
  Future<ScanResult> scanDevice({
    List<String>? includedFolders,
    void Function(int current, int total)? onProgress,
  }) async {
    if (_shouldFail) {
      throw Exception('Scan failed');
    }

    final filteredItems = includedFolders != null
        ? _mediaItems
              .where((item) => includedFolders.contains(item.albumName))
              .toList()
        : _mediaItems;

    return ScanResult(
      mediaItems: filteredItems,
      folders: _folders,
      totalScanned: filteredItems.length,
      newItems: filteredItems.length,
      updatedItems: 0,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  Future<List<AssetEntity>> listAllAssets({
    void Function(int loaded)? onProgress,
  }) async => [];

  @override
  Future<Uint8List?> getThumbnail(String assetId) async => null;

  @override
  Future<File?> getFullFile(String assetId) async => null;

  @override
  Future<List<DeviceFolder>> getDeviceFolders() async => _folders;
}

void main() {
  late MockMediaScannerService mockScanner;
  late GalleryRepository repository;

  setUp(() {
    mockScanner = MockMediaScannerService();
    repository = GalleryRepository(scannerService: mockScanner);
  });

  MediaItem createTestMediaItem({
    String localId = '1',
    String fileName = 'test.jpg',
    String mimeType = 'image/jpeg',
    int fileSize = 1000000,
    DateTime? createdAt,
    String? albumName,
    bool isFavorite = false,
    bool isHidden = false,
    bool isArchived = false,
    bool isTrashed = false,
  }) {
    return MediaItem(
      localId: localId,
      fileHash: 'hash_$localId',
      filePath: '/path/$fileName',
      fileName: fileName,
      mimeType: mimeType,
      fileSize: fileSize,
      width: 1920,
      height: 1080,
      createdAt: createdAt ?? DateTime(2026, 7, 14),
      modifiedAt: DateTime(2026, 7, 14),
      scannedAt: DateTime.now(),
      albumName: albumName,
      isFavorite: isFavorite,
      isHidden: isHidden,
      isArchived: isArchived,
      isTrashed: isTrashed,
    );
  }

  group('GalleryRepository', () {
    test('scanDevice populates media items and folders', () async {
      final items = [
        createTestMediaItem(localId: '1'),
        createTestMediaItem(localId: '2'),
      ];
      final folders = [
        DeviceFolder(
          path: '/path/Camera',
          name: 'Camera',
          lastScannedAt: DateTime.now(),
          createdAt: DateTime.now(),
        ),
      ];

      mockScanner.setMediaItems(items);
      mockScanner.setFolders(folders);

      final result = await repository.scanDevice();

      expect(result.mediaItems.length, 2);
      expect(result.folders.length, 1);
      expect(repository.totalCount, 2);
    });

    test('getTimelineItems returns all items when no filters', () async {
      final items = [
        createTestMediaItem(localId: '1'),
        createTestMediaItem(localId: '2'),
        createTestMediaItem(localId: '3'),
      ];

      mockScanner.setMediaItems(items);
      await repository.scanDevice();

      final timeline = repository.getTimelineItems();
      expect(timeline.length, 3);
    });

    test('getTimelineItems filters by date range', () async {
      final items = [
        createTestMediaItem(localId: '1', createdAt: DateTime(2026, 7, 10)),
        createTestMediaItem(localId: '2', createdAt: DateTime(2026, 7, 14)),
        createTestMediaItem(localId: '3', createdAt: DateTime(2026, 7, 20)),
      ];

      mockScanner.setMediaItems(items);
      await repository.scanDevice();

      final filtered = repository.getTimelineItems(
        startDate: DateTime(2026, 7, 12),
        endDate: DateTime(2026, 7, 18),
      );
      expect(filtered.length, 1);
      expect(filtered.first.localId, '2');
    });

    test('getTimelineItems filters by favorites', () async {
      final items = [
        createTestMediaItem(localId: '1', isFavorite: true),
        createTestMediaItem(localId: '2', isFavorite: false),
      ];

      mockScanner.setMediaItems(items);
      await repository.scanDevice();

      final favorites = repository.getTimelineItems(isFavorite: true);
      expect(favorites.length, 1);
      expect(favorites.first.localId, '1');
    });

    test('getAlbumItems returns items for specific album', () async {
      final items = [
        createTestMediaItem(localId: '1', albumName: 'Camera'),
        createTestMediaItem(localId: '2', albumName: 'Screenshots'),
        createTestMediaItem(localId: '3', albumName: 'Camera'),
      ];

      mockScanner.setMediaItems(items);
      await repository.scanDevice();

      final cameraItems = repository.getAlbumItems('Camera');
      expect(cameraItems.length, 2);
    });

    test('searchMedia finds items by filename', () async {
      final items = [
        createTestMediaItem(localId: '1', fileName: 'vacation_photo.jpg'),
        createTestMediaItem(localId: '2', fileName: 'screenshot.png'),
      ];

      mockScanner.setMediaItems(items);
      await repository.scanDevice();

      final results = repository.searchMedia('vacation');
      expect(results.length, 1);
      expect(results.first.fileName, 'vacation_photo.jpg');
    });

    test('searchMedia finds items by album name', () async {
      final items = [
        createTestMediaItem(localId: '1', albumName: 'Camera'),
        createTestMediaItem(localId: '2', albumName: 'Screenshots'),
      ];

      mockScanner.setMediaItems(items);
      await repository.scanDevice();

      final results = repository.searchMedia('camera');
      expect(results.length, 1);
    });

    test('toggleFavorite toggles favorite status', () async {
      final items = [createTestMediaItem(localId: '1', isFavorite: false)];

      mockScanner.setMediaItems(items);
      await repository.scanDevice();

      expect(repository.getItemById('1')?.isFavorite, false);

      await repository.toggleFavorite('1');
      expect(repository.getItemById('1')?.isFavorite, true);

      await repository.toggleFavorite('1');
      expect(repository.getItemById('1')?.isFavorite, false);
    });

    test('toggleHidden toggles hidden status', () async {
      final items = [createTestMediaItem(localId: '1', isHidden: false)];

      mockScanner.setMediaItems(items);
      await repository.scanDevice();

      await repository.toggleHidden('1');
      expect(repository.getItemById('1')?.isHidden, true);
    });

    test('toggleArchived toggles archived status', () async {
      final items = [createTestMediaItem(localId: '1', isArchived: false)];

      mockScanner.setMediaItems(items);
      await repository.scanDevice();

      await repository.toggleArchived('1');
      expect(repository.getItemById('1')?.isArchived, true);
    });

    test('moveToTrash sets trashedAt timestamp', () async {
      final items = [createTestMediaItem(localId: '1')];

      mockScanner.setMediaItems(items);
      await repository.scanDevice();

      await repository.moveToTrash('1');
      final item = repository.getItemById('1');
      expect(item?.isTrashed, true);
      expect(item?.trashedAt, isNotNull);
    });

    test('restoreFromTrash removes trashed status', () async {
      final items = [createTestMediaItem(localId: '1', isTrashed: true)];

      mockScanner.setMediaItems(items);
      await repository.scanDevice();

      await repository.restoreFromTrash('1');
      final item = repository.getItemById('1');
      expect(item?.isTrashed, false);
      expect(item?.trashedAt, null);
    });

    test('totalSize calculates sum of file sizes', () async {
      final items = [
        createTestMediaItem(localId: '1', fileSize: 1000),
        createTestMediaItem(localId: '2', fileSize: 2000),
      ];

      mockScanner.setMediaItems(items);
      await repository.scanDevice();

      expect(repository.totalSize, 3000);
    });

    test('getTimelineByDate groups items correctly', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));

      final items = [
        createTestMediaItem(
          localId: '1',
          createdAt: today.add(const Duration(hours: 10)),
        ),
        createTestMediaItem(
          localId: '2',
          createdAt: today.add(const Duration(hours: 14)),
        ),
        createTestMediaItem(localId: '3', createdAt: yesterday),
      ];

      mockScanner.setMediaItems(items);
      await repository.scanDevice();

      final grouped = repository.getTimelineByDate();
      expect(grouped.length, 2);
      expect(grouped.containsKey('Today'), true);
      expect(grouped['Today']?.length, 2);
    });

    test('getItemById returns null for non-existent id', () async {
      mockScanner.setMediaItems([]);
      await repository.scanDevice();

      expect(repository.getItemById('nonexistent'), null);
    });

    test('requestPermission delegates to scanner', () async {
      expect(await repository.requestPermission(), true);

      mockScanner.setShouldFail(true);
      expect(await repository.requestPermission(), false);
    });
  });
}
