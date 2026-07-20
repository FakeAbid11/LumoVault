import 'dart:convert';

import 'package:flutter/material.dart';

/// Grid size for gallery display.
enum GridSize {
  small(3),
  medium(2),
  large(1);

  const GridSize(this.columns);
  final int columns;
}

/// Central application settings model.
///
/// Immutable with copyWith pattern. Persisted via flutter_secure_storage.
class AppSettings {
  const AppSettings({
    // General
    this.languageCode = 'en',
    this.onboardingCompleted = false,
    // Backup
    this.autoBackupEnabled = true,
    this.wifiOnly = true,
    this.chargingOnly = false,
    this.minBatteryLevel = 20,
    this.backgroundBackupEnabled = true,
    this.maxParallelUploads = 3,
    this.backupVideos = true,
    this.backupPhotos = true,
    this.includedFolders = const [],
    this.excludedFolders = const [],
    this.excludedAlbums = const [],
    this.excludedFileHashes = const [],
    this.uploadBatchSize = 10,
    this.uploadDelayMs = 2000,
    this.maxFileSizeBytes = 0,
    this.storageChannelId,
    // Storage
    this.maxCacheSizeMB = 500,
    this.trashDurationDays = 30,
    // Appearance
    this.themeMode = ThemeMode.system,
    this.useDynamicColor = false,
    this.gridSize = GridSize.medium,
    this.compactMode = false,
    this.animationsEnabled = true,
    // Privacy
    this.biometricLockEnabled = false,
    this.pinLockEnabled = false,
    this.pinHash,
    this.hideSensitiveAlbums = false,
    this.requireAuthOnAppOpen = false,
    this.clearClipboardAfterShare = true,
    // Notifications
    this.backupProgressNotification = true,
    this.backupCompletedNotification = true,
    this.backupFailedNotification = true,
    this.restoreCompletedNotification = true,
    this.storageWarningNotification = true,
  });

  /// Default settings instance.
  factory AppSettings.defaults() => const AppSettings();

  /// Deserialize from JSON string.
  factory AppSettings.fromJsonString(String jsonString) {
    try {
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      return AppSettings(
        languageCode: map['languageCode'] as String? ?? 'en',
        onboardingCompleted: map['onboardingCompleted'] as bool? ?? false,
        autoBackupEnabled: map['autoBackupEnabled'] as bool? ?? true,
        wifiOnly: map['wifiOnly'] as bool? ?? true,
        chargingOnly: map['chargingOnly'] as bool? ?? false,
        minBatteryLevel: map['minBatteryLevel'] as int? ?? 20,
        backgroundBackupEnabled:
            map['backgroundBackupEnabled'] as bool? ?? true,
        maxParallelUploads: map['maxParallelUploads'] as int? ?? 3,
        backupVideos: map['backupVideos'] as bool? ?? true,
        backupPhotos: map['backupPhotos'] as bool? ?? true,
        includedFolders:
            (map['includedFolders'] as List<dynamic>?)?.cast<String>() ?? [],
        excludedFolders:
            (map['excludedFolders'] as List<dynamic>?)?.cast<String>() ?? [],
        excludedAlbums:
            (map['excludedAlbums'] as List<dynamic>?)?.cast<String>() ?? [],
        excludedFileHashes:
            (map['excludedFileHashes'] as List<dynamic>?)?.cast<String>() ?? [],
        uploadBatchSize: map['uploadBatchSize'] as int? ?? 10,
        uploadDelayMs: map['uploadDelayMs'] as int? ?? 2000,
        maxFileSizeBytes: map['maxFileSizeBytes'] as int? ?? 0,
        storageChannelId: map['storageChannelId'] as int?,
        maxCacheSizeMB: map['maxCacheSizeMB'] as int? ?? 500,
        trashDurationDays: map['trashDurationDays'] as int? ?? 30,
        themeMode: ThemeMode.values[map['themeMode'] as int? ?? 0],
        useDynamicColor: map['useDynamicColor'] as bool? ?? false,
        gridSize: GridSize.values[map['gridSize'] as int? ?? 1],
        compactMode: map['compactMode'] as bool? ?? false,
        animationsEnabled: map['animationsEnabled'] as bool? ?? true,
        biometricLockEnabled: map['biometricLockEnabled'] as bool? ?? false,
        pinLockEnabled: map['pinLockEnabled'] as bool? ?? false,
        pinHash: map['pinHash'] as String?,
        hideSensitiveAlbums: map['hideSensitiveAlbums'] as bool? ?? false,
        requireAuthOnAppOpen: map['requireAuthOnAppOpen'] as bool? ?? false,
        clearClipboardAfterShare:
            map['clearClipboardAfterShare'] as bool? ?? true,
        backupProgressNotification:
            map['backupProgressNotification'] as bool? ?? true,
        backupCompletedNotification:
            map['backupCompletedNotification'] as bool? ?? true,
        backupFailedNotification:
            map['backupFailedNotification'] as bool? ?? true,
        restoreCompletedNotification:
            map['restoreCompletedNotification'] as bool? ?? true,
        storageWarningNotification:
            map['storageWarningNotification'] as bool? ?? true,
      );
    } catch (e) {
      return const AppSettings();
    }
  }
  // -- General --
  final String languageCode;
  final bool onboardingCompleted;

  // -- Backup --
  final bool autoBackupEnabled;
  final bool wifiOnly;
  final bool chargingOnly;
  final int minBatteryLevel;
  final bool backgroundBackupEnabled;
  final int maxParallelUploads;
  final bool backupVideos;
  final bool backupPhotos;
  final List<String> includedFolders;
  final List<String> excludedFolders;
  final List<String> excludedAlbums;
  final List<String> excludedFileHashes;
  final int uploadBatchSize;
  final int uploadDelayMs;
  final int maxFileSizeBytes;

  /// The Telegram channel id used as the backup storage destination, once
  /// [StorageChannelService.findOrCreateChannel] has run. Persisted so a
  /// restart reuses the existing channel instead of creating a new one.
  final int? storageChannelId;

  // -- Storage --
  final int maxCacheSizeMB;
  final int trashDurationDays;

  // -- Appearance --
  final ThemeMode themeMode;
  final bool useDynamicColor;
  final GridSize gridSize;
  final bool compactMode;
  final bool animationsEnabled;

  // -- Privacy --
  final bool biometricLockEnabled;
  final bool pinLockEnabled;
  final String? pinHash;
  final bool hideSensitiveAlbums;
  final bool requireAuthOnAppOpen;
  final bool clearClipboardAfterShare;

  // -- Notifications --
  final bool backupProgressNotification;
  final bool backupCompletedNotification;
  final bool backupFailedNotification;
  final bool restoreCompletedNotification;
  final bool storageWarningNotification;

  AppSettings copyWith({
    String? languageCode,
    bool? onboardingCompleted,
    bool? autoBackupEnabled,
    bool? wifiOnly,
    bool? chargingOnly,
    int? minBatteryLevel,
    bool? backgroundBackupEnabled,
    int? maxParallelUploads,
    bool? backupVideos,
    bool? backupPhotos,
    List<String>? includedFolders,
    List<String>? excludedFolders,
    List<String>? excludedAlbums,
    List<String>? excludedFileHashes,
    int? uploadBatchSize,
    int? uploadDelayMs,
    int? maxFileSizeBytes,
    int? storageChannelId,
    int? maxCacheSizeMB,
    int? trashDurationDays,
    ThemeMode? themeMode,
    bool? useDynamicColor,
    GridSize? gridSize,
    bool? compactMode,
    bool? animationsEnabled,
    bool? biometricLockEnabled,
    bool? pinLockEnabled,
    String? pinHash,
    bool? clearPinHash,
    bool? hideSensitiveAlbums,
    bool? requireAuthOnAppOpen,
    bool? clearClipboardAfterShare,
    bool? backupProgressNotification,
    bool? backupCompletedNotification,
    bool? backupFailedNotification,
    bool? restoreCompletedNotification,
    bool? storageWarningNotification,
  }) {
    return AppSettings(
      languageCode: languageCode ?? this.languageCode,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      chargingOnly: chargingOnly ?? this.chargingOnly,
      minBatteryLevel: minBatteryLevel ?? this.minBatteryLevel,
      backgroundBackupEnabled:
          backgroundBackupEnabled ?? this.backgroundBackupEnabled,
      maxParallelUploads: maxParallelUploads ?? this.maxParallelUploads,
      backupVideos: backupVideos ?? this.backupVideos,
      backupPhotos: backupPhotos ?? this.backupPhotos,
      includedFolders: includedFolders ?? this.includedFolders,
      excludedFolders: excludedFolders ?? this.excludedFolders,
      excludedAlbums: excludedAlbums ?? this.excludedAlbums,
      excludedFileHashes: excludedFileHashes ?? this.excludedFileHashes,
      uploadBatchSize: uploadBatchSize ?? this.uploadBatchSize,
      uploadDelayMs: uploadDelayMs ?? this.uploadDelayMs,
      maxFileSizeBytes: maxFileSizeBytes ?? this.maxFileSizeBytes,
      storageChannelId: storageChannelId ?? this.storageChannelId,
      maxCacheSizeMB: maxCacheSizeMB ?? this.maxCacheSizeMB,
      trashDurationDays: trashDurationDays ?? this.trashDurationDays,
      themeMode: themeMode ?? this.themeMode,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      gridSize: gridSize ?? this.gridSize,
      compactMode: compactMode ?? this.compactMode,
      animationsEnabled: animationsEnabled ?? this.animationsEnabled,
      biometricLockEnabled: biometricLockEnabled ?? this.biometricLockEnabled,
      pinLockEnabled: pinLockEnabled ?? this.pinLockEnabled,
      pinHash: clearPinHash == true ? null : (pinHash ?? this.pinHash),
      hideSensitiveAlbums: hideSensitiveAlbums ?? this.hideSensitiveAlbums,
      requireAuthOnAppOpen: requireAuthOnAppOpen ?? this.requireAuthOnAppOpen,
      clearClipboardAfterShare:
          clearClipboardAfterShare ?? this.clearClipboardAfterShare,
      backupProgressNotification:
          backupProgressNotification ?? this.backupProgressNotification,
      backupCompletedNotification:
          backupCompletedNotification ?? this.backupCompletedNotification,
      backupFailedNotification:
          backupFailedNotification ?? this.backupFailedNotification,
      restoreCompletedNotification:
          restoreCompletedNotification ?? this.restoreCompletedNotification,
      storageWarningNotification:
          storageWarningNotification ?? this.storageWarningNotification,
    );
  }

  /// Serialize to JSON string for secure storage.
  String toJsonString() => jsonEncode(_toJson());

  Map<String, dynamic> _toJson() => {
    'languageCode': languageCode,
    'onboardingCompleted': onboardingCompleted,
    'autoBackupEnabled': autoBackupEnabled,
    'wifiOnly': wifiOnly,
    'chargingOnly': chargingOnly,
    'minBatteryLevel': minBatteryLevel,
    'backgroundBackupEnabled': backgroundBackupEnabled,
    'maxParallelUploads': maxParallelUploads,
    'backupVideos': backupVideos,
    'backupPhotos': backupPhotos,
    'includedFolders': includedFolders,
    'excludedFolders': excludedFolders,
    'excludedAlbums': excludedAlbums,
    'excludedFileHashes': excludedFileHashes,
    'uploadBatchSize': uploadBatchSize,
    'uploadDelayMs': uploadDelayMs,
    'maxFileSizeBytes': maxFileSizeBytes,
    'storageChannelId': storageChannelId,
    'maxCacheSizeMB': maxCacheSizeMB,
    'trashDurationDays': trashDurationDays,
    'themeMode': themeMode.index,
    'useDynamicColor': useDynamicColor,
    'gridSize': gridSize.index,
    'compactMode': compactMode,
    'animationsEnabled': animationsEnabled,
    'biometricLockEnabled': biometricLockEnabled,
    'pinLockEnabled': pinLockEnabled,
    'pinHash': pinHash,
    'hideSensitiveAlbums': hideSensitiveAlbums,
    'requireAuthOnAppOpen': requireAuthOnAppOpen,
    'clearClipboardAfterShare': clearClipboardAfterShare,
    'backupProgressNotification': backupProgressNotification,
    'backupCompletedNotification': backupCompletedNotification,
    'backupFailedNotification': backupFailedNotification,
    'restoreCompletedNotification': restoreCompletedNotification,
    'storageWarningNotification': storageWarningNotification,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          runtimeType == other.runtimeType &&
          languageCode == other.languageCode &&
          onboardingCompleted == other.onboardingCompleted &&
          autoBackupEnabled == other.autoBackupEnabled &&
          wifiOnly == other.wifiOnly &&
          chargingOnly == other.chargingOnly &&
          themeMode == other.themeMode &&
          gridSize == other.gridSize &&
          compactMode == other.compactMode &&
          biometricLockEnabled == other.biometricLockEnabled &&
          pinLockEnabled == other.pinLockEnabled;

  @override
  int get hashCode => Object.hash(
    languageCode,
    onboardingCompleted,
    autoBackupEnabled,
    wifiOnly,
    chargingOnly,
    themeMode,
    gridSize,
    compactMode,
    biometricLockEnabled,
    pinLockEnabled,
  );
}
