import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import 'package:lumovault/core/di/backup_providers.dart';
import 'package:lumovault/core/storage/storage_channel_service.dart';
import 'package:lumovault/core/tdlib/tdlib_client.dart';
import 'package:lumovault/features/backup/data/models/backup_settings.dart';
import 'package:lumovault/features/backup/engine/backup_scheduler.dart';
import 'package:lumovault/features/gallery/data/models/device_folder.dart';
import 'package:lumovault/features/gallery/data/models/upload_task.dart';
import 'package:lumovault/features/gallery/data/repositories/gallery_repository.dart';
import 'package:lumovault/features/gallery/data/repositories/media_scanner_service.dart';
import 'package:lumovault/features/gallery/data/repositories/telegram_upload_service.dart';

/// A [BackupEngineNotifier] whose scan/backup entry points do nothing.
///
/// Widget tests that reach [_onAuthSuccess] (in TelegramConnectScreen) would
/// otherwise build the *real* [backupEngineProvider], which spins up
/// `Connectivity()`/`Battery()` plugins plus a periodic timer and then hangs on
/// `startBackup()` (it awaits a live TDLib connection and drains the whole
/// upload queue). Overriding the provider with this fake keeps that graph out
/// of the test entirely.
///
/// `scanAndEnqueue`/`startBackup` are overridden to no-ops, so the fake gallery,
/// upload, and storage-channel collaborators below are never exercised — they
/// only need to be constructible. The construction pattern mirrors the
/// CI-proven fakes in `test/features/backup/engine/backup_engine_test.dart`.
class FakeBackupEngineNotifier extends BackupEngineNotifier {
  FakeBackupEngineNotifier()
    : super(
        galleryRepository: GalleryRepository(scannerService: _NoopScanner()),
        uploadService: _NoopUploadService(),
        settings: const BackupSettings(),
        environment: const BackupEnvironment(),
        storageChannelService: StorageChannelService(
          client: TdLibClient.instance,
        ),
      );

  @override
  Future<void> scanAndEnqueue() async {}

  @override
  Future<void> startBackup() async {}
}

class _NoopScanner implements MediaScannerService {
  @override
  Future<bool> checkPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<ScanResult> scanDevice({
    List<String>? includedFolders,
    void Function(int current, int total)? onProgress,
  }) async => const ScanResult(
    mediaItems: [],
    folders: [],
    totalScanned: 0,
    newItems: 0,
    updatedItems: 0,
    duration: Duration.zero,
  );

  @override
  Future<List<AssetEntity>> listAllAssets({
    void Function(int loaded)? onProgress,
  }) async => const [];

  @override
  Future<Uint8List?> getThumbnail(String assetId) async => null;

  @override
  Future<File?> getFullFile(String assetId) async => null;

  @override
  Future<List<DeviceFolder>> getDeviceFolders() async => const [];
}

class _NoopUploadService implements UploadService {
  final _controller = StreamController<UploadProgress>.broadcast();

  @override
  Stream<UploadProgress> get progressStream => _controller.stream;

  @override
  Future<UploadResult> uploadFile({
    required UploadTask task,
    required int channelId,
    bool includeCaption = true,
  }) async => UploadResult(taskId: task.id, messageId: 0, fileId: 0);

  @override
  Future<void> cancelUpload(String taskId) async {}

  @override
  void dispose() => _controller.close();
}
