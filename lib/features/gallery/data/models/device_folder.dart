class DeviceFolder {
  const DeviceFolder({
    this.id,
    required this.path,
    required this.name,
    this.isIncluded = true,
    this.totalItems = 0,
    this.totalSize = 0,
    this.coverId,
    this.relativePath,
    required this.lastScannedAt,
    required this.createdAt,
  });

  /// photo_manager `AssetPathEntity.id` for this folder (path ids are
  /// strings in photo_manager 3.x) — stable within a session and
  /// collision-free (two folders named "Camera" get distinct ids), so the
  /// Albums tab routes by it rather than by name.
  final String? id;
  final String path;
  final String name;
  final bool isIncluded;
  final int totalItems;
  final int totalSize;

  /// Asset id of the folder's first item, used as the card cover without
  /// needing a scan. Null when the folder is empty or the lookup failed.
  final String? coverId;

  /// The folder's exact MediaStore RELATIVE_PATH (e.g. `DCIM/Camera/`) —
  /// required as the target for move/copy operations; the bucket display
  /// name is not a valid path.
  final String? relativePath;
  final DateTime lastScannedAt;
  final DateTime createdAt;

  DeviceFolder copyWith({
    String? id,
    String? path,
    String? name,
    bool? isIncluded,
    int? totalItems,
    int? totalSize,
    String? coverId,
    String? relativePath,
    DateTime? lastScannedAt,
    DateTime? createdAt,
  }) {
    return DeviceFolder(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      isIncluded: isIncluded ?? this.isIncluded,
      totalItems: totalItems ?? this.totalItems,
      totalSize: totalSize ?? this.totalSize,
      coverId: coverId ?? this.coverId,
      relativePath: relativePath ?? this.relativePath,
      lastScannedAt: lastScannedAt ?? this.lastScannedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
