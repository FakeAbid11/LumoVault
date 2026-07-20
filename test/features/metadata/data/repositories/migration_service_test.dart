import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/features/metadata/data/models/metadata_models.dart';
import 'package:lumovault/features/metadata/data/repositories/migration_service.dart';

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
      expect(service.getCurrentVersion(), 1);
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
      expect(migrated!.schemaVersion, 1);
    });

    test('migrateManifest upgrades older version', () {
      final manifest = Manifest.create(
        deviceHash: 'hash',
      ).copyWith(schemaVersion: 0);
      final migrated = service.migrateManifest(manifest);
      expect(migrated, isNotNull);
      expect(migrated!.schemaVersion, 1);
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
      service.registerMigration(2, const MigrationV2());
      final migrations = service.getMigrationsNeeded(1);
      expect(migrations.length, 1);
      expect(migrations[0].version, 2);
    });
  });
}
