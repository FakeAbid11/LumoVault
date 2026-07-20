/// Persistent backup configuration per PRD Section 5 Collection 5.
///
/// Singleton record (id = 1) storing all user backup preferences.
class BackupSettings {
  const BackupSettings({
    this.id = 1,
    this.isAutoBackupEnabled = true,
    this.wifiOnly = true,
    this.chargingOnly = false,
    this.cellularAllowed = false,
    this.maxFileSize,
    this.backupPhotos = true,
    this.backupVideos = true,
    this.includedFolders = const [],
    this.excludedFolders = const [],
    this.excludedFileHashes = const [],
    this.uploadBatchSize = 10,
    this.uploadDelayMs = 2000,
    this.lastBackupAt,
    this.lastScanAt,
  });
  final int id;
  final bool isAutoBackupEnabled;
  final bool wifiOnly;
  final bool chargingOnly;
  final bool cellularAllowed;
  final int? maxFileSize;

  /// Whether photos (images) should be included in backup. There was no
  /// way to control this at all before — this field plus its equivalent
  /// for video are what "select photos/videos for backup" actually needed.
  final bool backupPhotos;

  /// Whether videos should be included in backup.
  final bool backupVideos;
  final List<String> includedFolders;
  final List<String> excludedFolders;
  final List<String> excludedFileHashes;
  final int uploadBatchSize;
  final int uploadDelayMs;
  final DateTime? lastBackupAt;
  final DateTime? lastScanAt;

  /// Whether all folders are included (empty includedFolders means all).
  bool get allFoldersIncluded => includedFolders.isEmpty;

  /// Whether a specific folder is included for backup.
  bool isFolderIncluded(String folderPath) {
    if (allFoldersIncluded) return true;
    return includedFolders.contains(folderPath);
  }

  /// Whether a specific folder is excluded from backup.
  bool isFolderExcluded(String folderPath) {
    return excludedFolders.contains(folderPath);
  }

  /// Whether a specific file hash is excluded from backup.
  bool isFileExcluded(String fileHash) {
    return excludedFileHashes.contains(fileHash);
  }

  /// Whether a file should be backed up based on size constraint.
  bool isFileSizeAllowed(int fileSize) {
    if (maxFileSize == null) return true;
    return fileSize <= maxFileSize!;
  }

  BackupSettings copyWith({
    int? id,
    bool? isAutoBackupEnabled,
    bool? wifiOnly,
    bool? chargingOnly,
    bool? cellularAllowed,
    int? Function()? clearMaxFileSize,
    int? maxFileSize,
    bool? backupPhotos,
    bool? backupVideos,
    List<String>? includedFolders,
    List<String>? excludedFolders,
    List<String>? excludedFileHashes,
    int? uploadBatchSize,
    int? uploadDelayMs,
    DateTime? lastBackupAt,
    DateTime? lastScanAt,
  }) {
    return BackupSettings(
      id: id ?? this.id,
      isAutoBackupEnabled: isAutoBackupEnabled ?? this.isAutoBackupEnabled,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      chargingOnly: chargingOnly ?? this.chargingOnly,
      cellularAllowed: cellularAllowed ?? this.cellularAllowed,
      maxFileSize: clearMaxFileSize != null
          ? null
          : (maxFileSize ?? this.maxFileSize),
      backupPhotos: backupPhotos ?? this.backupPhotos,
      backupVideos: backupVideos ?? this.backupVideos,
      includedFolders: includedFolders ?? this.includedFolders,
      excludedFolders: excludedFolders ?? this.excludedFolders,
      excludedFileHashes: excludedFileHashes ?? this.excludedFileHashes,
      uploadBatchSize: uploadBatchSize ?? this.uploadBatchSize,
      uploadDelayMs: uploadDelayMs ?? this.uploadDelayMs,
      lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      lastScanAt: lastScanAt ?? this.lastScanAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackupSettings &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          isAutoBackupEnabled == other.isAutoBackupEnabled &&
          wifiOnly == other.wifiOnly &&
          chargingOnly == other.chargingOnly &&
          backupPhotos == other.backupPhotos &&
          backupVideos == other.backupVideos;

  @override
  int get hashCode =>
      id.hashCode ^
      isAutoBackupEnabled.hashCode ^
      wifiOnly.hashCode ^
      chargingOnly.hashCode ^
      backupPhotos.hashCode ^
      backupVideos.hashCode;
}
