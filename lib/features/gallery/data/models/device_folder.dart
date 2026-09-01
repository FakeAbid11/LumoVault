class DeviceFolder {
  const DeviceFolder({
    this.id,
    required this.path,
    required this.name,
    this.isIncluded = true,
    this.totalItems = 0,
    this.totalSize = 0,
    required this.lastScannedAt,
    required this.createdAt,
  });
  final int? id;

  /// Stable selection key for backup scope. Holds photo_manager's
  /// [AssetPathEntity.id] (the OS album/bucket id), which survives album
  /// renames and disambiguates albums that share a display name. The
  /// field name is historical: earlier builds stored the album's display
  /// name here, which broke silently on renames and collided for albums
  /// sharing a name.
  final String path;
  final String name;
  final bool isIncluded;
  final int totalItems;
  final int totalSize;
  final DateTime lastScannedAt;
  final DateTime createdAt;

  DeviceFolder copyWith({
    int? id,
    String? path,
    String? name,
    bool? isIncluded,
    int? totalItems,
    int? totalSize,
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
      lastScannedAt: lastScannedAt ?? this.lastScannedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
