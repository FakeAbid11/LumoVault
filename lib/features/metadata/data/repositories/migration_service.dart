import 'package:flutter/foundation.dart';

import '../models/metadata_models.dart';

/// Migration service per PRD Section 6.6.
///
/// Provides versioned metadata schema with a defined upgrade path.
/// Even though there's only one version today, future prompts can
/// add fields/restructure without breaking existing users' stored metadata.
///
/// Schema Version History:
///   v1 -> Initial format (V1.0)
///   v2 -> Add GPS coordinates to caption (future)
///   v3 -> Add face detection tags (future)
///   v4 -> Add AI-generated descriptions (future)
///   v5 -> End-to-end encryption metadata (future)
class MigrationService {
  MigrationService() {
    _registerDefaultMigrations();
  }
  static const int currentVersion = Manifest.currentSchemaVersion;

  final Map<int, Migration> _migrations = {};

  /// Register the default (no-op) migration for v1.
  void _registerDefaultMigrations() {
    _migrations[1] = const _MigrationV1();
  }

  /// Register a custom migration for a specific version.
  void registerMigration(int version, Migration migration) {
    _migrations[version] = migration;
  }

  /// Get the current schema version.
  int getCurrentVersion() => currentVersion;

  /// Check if a manifest needs migration.
  bool needsMigration(Manifest manifest) {
    return manifest.schemaVersion < currentVersion;
  }

  /// Get the list of migrations needed to upgrade to current version.
  List<Migration> getMigrationsNeeded(int fromVersion) {
    final maxVersion = _migrations.keys.isEmpty
        ? currentVersion
        : _migrations.keys.reduce((a, b) => a > b ? a : b);
    final needed = <Migration>[];
    for (var v = fromVersion + 1; v <= maxVersion; v++) {
      final migration = _migrations[v];
      if (migration != null) {
        needed.add(migration);
      }
    }
    return needed;
  }

  /// Migrate a manifest from one version to another.
  ///
  /// Returns the migrated manifest, or null if migration fails.
  Manifest? migrateManifest(Manifest manifest, {int? targetVersion}) {
    final target = targetVersion ?? currentVersion;

    if (manifest.schemaVersion >= target) {
      return manifest;
    }

    var current = manifest;
    final migrations = getMigrationsNeeded(manifest.schemaVersion);

    for (final migration in migrations) {
      debugPrint('[MigrationService] Applying migration v${migration.version}');
      try {
        current = migration.migrate(current);
      } catch (e) {
        debugPrint(
          '[MigrationService] Migration v${migration.version} failed: $e',
        );
        return null;
      }
    }

    return current.copyWith(schemaVersion: target);
  }

  /// Migrate partition data from one version to another.
  ///
  /// Returns the migrated partition, or null if migration fails.
  MetadataPartition? migratePartition(
    MetadataPartition partition, {
    int fromVersion = 1,
    int? targetVersion,
  }) {
    final target = targetVersion ?? currentVersion;

    if (fromVersion >= target) {
      return partition;
    }

    var current = partition;

    for (var v = fromVersion + 1; v <= target; v++) {
      final migration = _migrations[v];
      if (migration != null) {
        try {
          current = migration.migratePartition(current);
        } catch (e) {
          debugPrint('[MigrationService] Partition migration v$v failed: $e');
          return null;
        }
      }
    }

    return current;
  }

  void dispose() {
    _migrations.clear();
  }
}

/// Abstract migration interface.
abstract class Migration {
  int get version;
  String get description;

  Manifest migrate(Manifest manifest);
  MetadataPartition migratePartition(MetadataPartition partition);
}

/// Default v1 migration (no-op, initial format).
class _MigrationV1 implements Migration {
  const _MigrationV1();

  @override
  int get version => 1;

  @override
  String get description => 'Initial metadata format';

  @override
  Manifest migrate(Manifest manifest) {
    return manifest;
  }

  @override
  MetadataPartition migratePartition(MetadataPartition partition) {
    return partition;
  }
}

/// Example v2 migration for future use.
///
/// Adds GPS coordinates to caption metadata.
class MigrationV2 implements Migration {
  const MigrationV2();

  @override
  int get version => 2;

  @override
  String get description => 'Add GPS coordinates to caption';

  @override
  Manifest migrate(Manifest manifest) {
    return manifest;
  }

  @override
  MetadataPartition migratePartition(MetadataPartition partition) {
    // GPS fields are optional, old data remains valid.
    return partition;
  }
}

/// Example v3 migration for future use.
///
/// Adds face detection tags.
class MigrationV3 implements Migration {
  const MigrationV3();

  @override
  int get version => 3;

  @override
  String get description => 'Add face detection tags';

  @override
  Manifest migrate(Manifest manifest) {
    return manifest;
  }

  @override
  MetadataPartition migratePartition(MetadataPartition partition) {
    // Tags are appended; old data remains valid.
    return partition;
  }
}
