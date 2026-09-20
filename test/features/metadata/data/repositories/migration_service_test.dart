import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/metadata/data/models/metadata_models.dart';
import 'package:lumovault/features/metadata/data/repositories/migration_service.dart';

/// Test-only migrations, used to verify registration and chain handling
/// without depending on any production migration existing.
class _TestMigrationV1 implements Migration {
  const _TestMigrationV1();

  @override
  int get version => 1;

  @override
  String get description => 'Test migration v1';

  @override
  Manifest migrate(Manifest manifest) => manifest;

  @override
  MetadataPartition migratePartition(MetadataPartition partition) => partition;
}

class _TestMigrationV2 implements Migration {
  const _TestMigrationV2();

  @override
  int get version => 2;

  @override
  String get description => 'Test migration v2';

  @override
  Manifest migrate(Manifest manifest) => manifest;

  @override
  MetadataPartition migratePartition(MetadataPartition partition) => partition;
}

void main() {
  group('MigrationService', () {
    late MigrationService service;

    setUp(() {
      service = MigrationService();
    });

    tearDown(() {
      service.dispose();
    });

    test('getCurrentVersion returns current version', () {
      expect(service.getCurrentVersion(), 2);
    });

    test('needsMigration returns false for current version', () {
      final manifest = Manifest.create(deviceHash: 'hash');
      expect(service.needsMigration(manifest), isFalse);
    });

    test('needsMigration returns true for older version', () {
      final manifest = Manifest.create(
        deviceHash: 'hash',
      ).copyWith(schemaVersion: 0);
      expect(service.needsMigration(manifest), isTrue);
    });

    test('getMigrationsNeeded returns empty for current version', () {
      final migrations = service.getMigrationsNeeded(1);
      expect(migrations, isEmpty);
    });

    test('getMigrationsNeeded returns migrations for older version', () {
      final migrations = service.getMigrationsNeeded(0);
      expect(migrations.length, 1);
      expect(migrations[0].version, 1);
    });

    test('migrateManifest returns same manifest for current version', () {
      final manifest = Manifest.create(deviceHash: 'hash');
      final migrated = service.migrateManifest(manifest);
      expect(migrated, isNotNull);
      expect(migrated!.schemaVersion, 2);
    });

    // The realistic upgrade path: a v1 manifest (the only format ever shipped)
    // advancing to the current schema. No transformation is required because
    // v2 was additive, so the manifest is accepted and its version advanced
    // rather than refused.
    test('migrateManifest advances an additive-gap manifest to current', () {
      final manifest = Manifest.create(
        deviceHash: 'hash',
      ).copyWith(schemaVersion: 1);
      final migrated = service.migrateManifest(manifest);
      expect(migrated, isNotNull);
      expect(migrated!.schemaVersion, 2);
    });

    // Guard against the silent-skip: if part of the version gap has a
    // registered migration and part does not, stamping the target version
    // would certify data that was only partly transformed. Refuse instead.
    test('migrateManifest refuses a partly covered version gap', () {
      final servicePartial = MigrationService();
      addTearDown(servicePartial.dispose);
      servicePartial.registerMigration(1, const _TestMigrationV1());
      // Gap is 0 -> 2 (two steps) but only a v1 migration is registered, so
      // the v1 -> 2 step is uncovered and the whole migration must be refused.
      final manifest = Manifest.create(
        deviceHash: 'hash',
      ).copyWith(schemaVersion: 0);
      expect(servicePartial.migrateManifest(manifest), isNull);
    });

    test('migrateManifest applies a fully covered chain', () {
      final serviceCovered = MigrationService();
      addTearDown(serviceCovered.dispose);
      serviceCovered.registerMigration(2, const _TestMigrationV2());
      // Gap is 1 -> 2 with a v2 migration registered: full coverage.
      final manifest = Manifest.create(
        deviceHash: 'hash',
      ).copyWith(schemaVersion: 1);
      final migrated = serviceCovered.migrateManifest(manifest);
      expect(migrated, isNotNull);
      expect(migrated!.schemaVersion, 2);
    });

    test('migratePartition returns same partition for current version', () {
      final partition = MetadataPartition(
        id: '2026/01',
        periodStart: DateTime(2026, 1),
        periodEnd: DateTime(2026, 2),
        lastModified: DateTime(2026, 1, 15),
      );
      final migrated = service.migratePartition(partition, fromVersion: 1);
      expect(migrated, isNotNull);
      expect(migrated!.id, '2026/01');
    });

    test('registerMigration adds custom migration', () {
      service.registerMigration(2, const _TestMigrationV2());
      final migrations = service.getMigrationsNeeded(1);
      expect(migrations.length, 1);
      expect(migrations[0].version, 2);
    });
  });
}
