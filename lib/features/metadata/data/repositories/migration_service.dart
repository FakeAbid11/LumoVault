import 'package:flutter/foundation.dart';

import '../models/metadata_models.dart';

/// Migration service per PRD Section 6.6.
///
/// Provides versioned metadata schema with a defined upgrade path, so future
/// releases can add fields or restructure stored metadata without breaking
/// backups created by older app versions.
///
/// Schema version history:
///   v1 -> Initial format.
///   v2 -> Tombstones for deletions. Additive and forward-compatible: old
///         partitions remain valid because the new fields default on read,
///         so no transformation is required and v1 data is used as-is.
///
/// Only register a [Migration] for a version when that version changes the
/// format in a way old data cannot already express. An unregistered version
/// in the gap means "additive, no work needed"; a *partly* covered gap means
/// a format change would be silently skipped, which [migrateManifest] and
/// [migratePartition] refuse rather than perform.
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

  /// Migrate a manifest to the current schema version.
  ///
  /// Returns the migrated manifest, or null if migration fails or is refused.
  ///
  /// A gap is refused when it is only *partly* covered by registered
  /// migrations: the uncovered step would be silently skipped while the
  /// target version is stamped onto data that was never transformed. An
  /// entirely uncovered gap is not an error — it means every intervening
  /// version was additive and the stored manifest is already valid at the
  /// target version, so it is returned with the version advanced.
  Manifest? migrateManifest(Manifest manifest, {int? targetVersion}) {
    final target = targetVersion ?? currentVersion;

    if (manifest.schemaVersion >= target) {
      return manifest;
    }

    var current = manifest;
    final migrations = getMigrationsNeeded(manifest.schemaVersion);

    final gap = target - manifest.schemaVersion;
    if (migrations.isNotEmpty && migrations.length != gap) {
      debugPrint(
        '[MigrationService] Refusing to migrate manifest from '
        'v${manifest.schemaVersion}: only ${migrations.length} of $gap '
        'required migrations are registered',
      );
      return null;
    }

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

  /// Migrate partition data to the current schema version.
  ///
  /// Same partial-coverage contract as [migrateManifest]: a partly covered
  /// gap is refused rather than partly applied.
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

    final migrations = getMigrationsNeeded(fromVersion);
    final gap = target - fromVersion;
    if (migrations.isNotEmpty && migrations.length != gap) {
      debugPrint(
        '[MigrationService] Refusing to migrate partition from '
        'v$fromVersion: only ${migrations.length} of $gap required '
        'migrations are registered',
      );
      return null;
    }

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
